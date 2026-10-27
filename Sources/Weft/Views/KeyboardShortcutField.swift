import AppKit
import SwiftUI
import WeftCore

struct KeyboardShortcutField: View {
    @Binding var shortcut: KeyboardKeyCombination?
    var placeholder = "点击录入按键"
    var autoRecord = false
    var onEnd: () -> Void = {}
    @State private var recording = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 4) {
            if recording {
                Image(systemName: "keyboard").foregroundStyle(WeftStyle.accentText)
                Text("请按下按键…").foregroundStyle(WeftStyle.accentText)
            } else if let shortcut {
                ForEach(Array(shortcut.keyCaps.enumerated()), id: \.offset) { _, label in
                    Text(label).font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(WeftStyle.border, lineWidth: 1))
                }
            } else {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text(placeholder).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12)).padding(.horizontal, 9).frame(height: 35)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(recording ? WeftStyle.accent : WeftStyle.border, lineWidth: 1))
        .overlay {
            ShortcutCaptureBridge(enabled: enabled, autoRecord: autoRecord,
                label: shortcut?.displayTitle ?? placeholder,
                onRecord: { shortcut = $0 }, onRecording: { recording = $0 }, onEnd: onEnd)
        }
        .opacity(enabled ? 1 : 0.45)
        .help("点击后录入单键或组合键，按 Esc 取消")
    }
}

private struct ShortcutCaptureBridge: NSViewRepresentable {
    let enabled: Bool
    let autoRecord: Bool
    let label: String
    let onRecord: (KeyboardKeyCombination) -> Void
    let onRecording: (Bool) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView { ShortcutCaptureView() }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.enabled = enabled
        view.onRecord = onRecord; view.onRecording = onRecording; view.onEnd = onEnd
        view.setAccessibilityLabel("快捷键：\(label)")
        if autoRecord && enabled && !view.didAutoRecord {
            view.didAutoRecord = true
            DispatchQueue.main.async { [weak view] in
                guard let view, view.enabled else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }

    static func dismantleNSView(_ view: ShortcutCaptureView, coordinator: ()) {
        view.onRecord = nil; view.onRecording = nil; view.onEnd = nil
        if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
    }
}

/// This responder exists only inside the settings input. It installs no global event monitor.
final class ShortcutCaptureView: NSView {
    var enabled = true
    var didAutoRecord = false
    private(set) var recording = false
    var onRecord: ((KeyboardKeyCombination) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onEnd: (() -> Void)?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { stopMonitoring() }
    override var acceptsFirstResponder: Bool { enabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { enabled }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        window?.makeFirstResponder(self)
    }
    override func becomeFirstResponder() -> Bool {
        guard enabled else { return false }
        recording = true; onRecording?(true)
        stopMonitoring()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.window?.makeFirstResponder(nil)
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in self?.window?.makeFirstResponder(nil) }
        return true
    }
    override func resignFirstResponder() -> Bool {
        let wasRecording = recording
        stopMonitoring()
        recording = false; onRecording?(false)
        if wasRecording { onEnd?() }
        return true
    }
    private func stopMonitoring() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
    }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        return window?.makeFirstResponder(self) ?? false
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.isKeyWindow == true, window?.firstResponder === self else { return false }
        record(event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        record(event)
    }
    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let shortcut = KeyboardKeyCombination(event: event)
        if !(event.keyCode == 53 && shortcut.modifiers.isEmpty) { onRecord?(shortcut) }
        window?.makeFirstResponder(nil)
    }
}
