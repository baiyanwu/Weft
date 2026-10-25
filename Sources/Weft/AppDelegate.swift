import AppKit
import SwiftUI
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var store: DeviceStore!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var window: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []
    private var localPopoverMonitor: Any?
    private var globalPopoverMonitor: Any?
    private var popoverClosing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        signal(SIGPIPE, SIG_IGN)
        for code in [SIGTERM, SIGINT] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }; source.resume(); signalSources.append(source)
        }
        store = DeviceStore()
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let mark = WeftStyle.logo.copy() as! NSImage; mark.size = NSSize(width: 22, height: 22)
        statusItem.button?.image = mark
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Keep the native animated container, with one owner for outside-click dismissal.
        popover = NSPopover(); popover.behavior = .applicationDefined; popover.animates = true
        popover.delegate = self
        let menuController = NSHostingController(rootView: MenuPanelView(store: store,
            openSettings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) }))
        menuController.view.wantsLayer = true
        menuController.view.layer?.backgroundColor = NSColor.clear.cgColor
        menuController.view.layer?.isOpaque = false
        popover.contentViewController = menuController
        store.onStateChange = { [weak self] in self?.updateStatus() }
        store.beforeEntry = { [weak self] in self?.popover.performClose(nil) }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionInactive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(activeApplicationChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        store.start(); updateStatus()
        Log.write("weft 0.2.0 started; multi-device mode")
        if store.showOnLaunch { DispatchQueue.main.async { self.showSettings() } }
    }
    func applicationWillTerminate(_ notification: Notification) { stopPopoverMonitoring(); store?.stop() }
    func applicationDidResignActive(_ notification: Notification) { popover?.performClose(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) { store.returnToMac() }

    func popoverDidShow(_ notification: Notification) {
        stopPopoverMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Global monitors cover other apps; local monitors cover our settings window.
        globalPopoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            guard let self, !self.statusButtonContainsMouse else { return }
            self.popover.performClose(nil)
        }
        localPopoverMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.popover.performClose(nil); return nil }
                return event
            }
            if event.window === self.popover.contentViewController?.view.window { return event }
            // Let the status button toggle normally instead of closing on down and reopening on up.
            if self.statusButtonContainsMouse { return event }
            self.popover.performClose(nil)
            return event
        }
    }
    func popoverWillClose(_ notification: Notification) { popoverClosing = true; stopPopoverMonitoring() }
    func popoverDidClose(_ notification: Notification) { popoverClosing = false }
    private var statusButtonContainsMouse: Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else { return false }
        let bounds = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return bounds.contains(NSEvent.mouseLocation)
    }
    private func stopPopoverMonitoring() {
        if let monitor = localPopoverMonitor { NSEvent.removeMonitor(monitor); localPopoverMonitor = nil }
        if let monitor = globalPopoverMonitor { NSEvent.removeMonitor(monitor); globalPopoverMonitor = nil }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard !popoverClosing else { return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }
    @objc private func toggleControl() {
        if store.mouse.mode == .local { store.enterLast() } else { store.returnToMac() }
    }
    @objc func showSettings() {
        store.returnToMac()
        popover?.performClose(nil)
        if window == nil {
            let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 900)
            let frame = NSRect(x: 0, y: 0, width: min(1120, visible.width - 50), height: min(880, visible.height - 50))
            let created = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            created.title = "weft 设置"; created.minSize = NSSize(width: 960, height: 740)
            created.isReleasedWhenClosed = false; created.delegate = self
            created.contentViewController = NSHostingController(rootView: SettingsView(store: store))
            created.setFrameAutosaveName("weft.settings.v2"); created.center(); window = created
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func updateStatus() {
        guard statusItem != nil else { return }
        statusItem.button?.toolTip = "weft · \(store.connectedCount) 台已连接 · 当前控制 \(store.controlName)"
    }
    private func buildMainMenu() {
        let main = NSMenu(), appItem = NSMenuItem(), app = NSMenu(title: "weft")
        let settings = NSMenuItem(title: "weft 设置…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self
        app.addItem(settings)
        let panel = NSMenuItem(title: "菜单栏面板", action: #selector(togglePopover), keyEquivalent: "m")
        panel.keyEquivalentModifierMask = [.command, .shift]; panel.target = self; app.addItem(panel)
        let control = NSMenuItem(title: "切换 Mac / 上次设备", action: #selector(toggleControl), keyEquivalent: "m")
        control.keyEquivalentModifierMask = [.control, .option]; control.target = self; app.addItem(control)
        app.addItem(.separator())
        app.addItem(withTitle: "退出 weft", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app; main.addItem(appItem)
        let editItem = NSMenuItem(), edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    @objc private func willSleep() { store.willSleep() }
    @objc private func didWake() { store.didWake() }
    @objc private func sessionInactive() { store.sessionActive = false; store.returnToMac(); store.refreshPortals() }
    @objc private func sessionActive() { store.sessionActive = true; store.refreshPortals() }
    @objc private func displaysChanged() { store.mouse.returnToMac("显示器布局已变化"); store.refreshScreens() }
    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard store.mouse.mode != .local, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != store.mouse.entryApplicationPID else { return }
        store.mouse.returnToMac("已切换 Mac 应用")
    }

}
