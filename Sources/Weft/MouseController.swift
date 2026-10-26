import AppKit
import ApplicationServices
import WeftCore

struct MousePortal {
    let deviceID: String
    let displayID: UInt32
    let bounds: CGRect
    let speed: Double
    let autoCross: Bool
    let seam: ScreenSeam
    var direction: Direction { seam.direction }
}

final class MouseController {
    enum Mode: String { case local, entering, remote }
    var portals: [MousePortal] = []
    var onEnter: ((String, CGPoint, Int) -> Void)?
    var onRelease: ((String, Int, String) -> Void)?
    var onInput: ((String, PointerFrame) -> Void)?
    var onPointerAction: ((String, Int, Int, KeyboardMappingAction?) -> Void)?
    var onShortcut: (() -> Void)?
    var onChange: (() -> Void)?
    let keyboard = KeyboardController()
    private(set) var mode: Mode = .local
    private(set) var hasTap = false
    private(set) var activePortal: MousePortal?
    private(set) var lease: ControlLease?
    private var sequence = 0
    var activeDeviceID: String? { activePortal?.deviceID }
    private var direction: Direction { activePortal?.direction ?? .below }
    private var speed: Double { activePortal?.speed ?? 1 }
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let cursor = MacCursorCapture()
    private(set) var entryApplicationPID: pid_t?
    private var buttons = 0
    private var suppressedReleases = 0
    private var path: PointerPath?
    private var motionDirty = false
    private var inputSequence = 0
    private var lastLocalPoint: CGPoint?
    private var scrollX = 0.0, scrollY = 0.0
    private var entryFraction = 0.5
    private var enteredAt = 0.0
    private var androidWidth = 0.0, androidHeight = 0.0
    private var androidRotation = -1
    private var activeBounds = CGRect.zero

    var bounds: CGRect { activePortal?.bounds ?? CGDisplayBounds(CGMainDisplayID()) }
    var now: Double { ProcessInfo.processInfo.systemUptime }

    @discardableResult func installTap() -> Bool {
        guard !hasTap else { return true }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
            .otherMouseDragged, .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MouseController>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }, userInfo: opaque) else { return false }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        hasTap = true
        Log.write("Global mouse capture ready")
        onChange?()
        return true
    }

    func uninstallTap() {
        returnToMac("鼠标监听已停止")
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; runLoopSource = nil; hasTap = false
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            returnToMac("系统暂停了鼠标监听，已返回 Mac")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return Unmanaged.passUnretained(event) }
        // Let the focused settings recorder handle even reserved chords for validation.
        if mode == .local, let recorder = NSApp.keyWindow?.firstResponder as? ShortcutCaptureView, recorder.recording,
           type == .keyDown || type == .flagsChanged {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            if key == 46 && event.flags.contains([.maskControl, .maskAlternate]) {
                keyboard.consumeShortcut(46)
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                if mode == .local { onShortcut?() } else { returnToMac("快捷键返回 Mac") }
                return nil
            }
            if mode != .local && !keyboard.sharing && key == 53 {
                keyboard.consumeShortcut(53); returnToMac("Esc 返回 Mac"); return nil
            }
        }
        if type == .flagsChanged && mode != .local && !keyboard.sharing && key == 58 && event.flags.contains(.maskAlternate) && !event.flags.contains(.maskControl) {
            returnToMac("Option 返回 Mac")
            return nil
        }
        if keyboard.handle(type, event) { return nil }
        let mouseTypes: Set<CGEventType> = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        guard mouseTypes.contains(type) else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return Unmanaged.passUnretained(event) }
        let bit = buttonBit(type, event)
        if mode == .local {
            if isUp(type), bit & suppressedReleases != 0 {
                suppressedReleases &= ~bit
                return nil
            }
            if hasTap && type == .mouseMoved {
                let p = event.location
                let previous = lastLocalPoint ?? p
                lastLocalPoint = p
                let dx = event.getDoubleValueField(.mouseEventDeltaX)
                let dy = event.getDoubleValueField(.mouseEventDeltaY)
                let candidate = portals.first { portal in
                    portal.autoCross && portal.direction.onMacEdge(p, bounds: portal.bounds, tolerance: (portal.direction == .below || portal.direction == .right) ? 1 : 0) &&
                    portal.seam.macSegment.contains(portal.direction.fraction(p, bounds: portal.bounds)) &&
                    !anotherDisplayOccupies(portal.direction.beyondEdge(p, bounds: portal.bounds), except: portal.displayID)
                }
                if let portal = candidate, EdgeGate.shouldCross(atEdge: true,
                    outward: portal.direction.outward(dx: dx, dy: dy), buttonsDown: physicalButtonsDown()) {
                    let remainder = PointerPath.entryRemainder(direction: portal.direction, previous: previous,
                        bounds: portal.bounds, dx: dx, dy: dy)
                    let intersection = CGPoint(x: p.x - remainder.dx, y: p.y - remainder.dy)
                    let macFraction = portal.direction.fraction(intersection, bounds: portal.bounds)
                    guard portal.seam.macSegment.contains(macFraction) else { return Unmanaged.passUnretained(event) }
                    let fraction = portal.seam.toRemote(macFraction)
                    beginEntry(portal: portal, fraction: fraction,
                        remainder: CGVector(dx: remainder.dx * portal.speed, dy: remainder.dy * portal.speed))
                    return mode == .local ? Unmanaged.passUnretained(event) : nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            if var trajectory = path {
                let landing = trajectory.move(dx: dx, dy: dy, speed: speed,
                    allowReturn: buttons == 0 && !physicalButtonsDown())
                path = trajectory
                if let landing {
                    returnToMac("从设备边缘返回 Mac", at: landing)
                    return nil
                }
                motionDirty = true
            }
        } else if isDown(type) {
            flush()
            buttons |= bit
            flush(force: true)
        } else if isUp(type) {
            if suppressedReleases & bit != 0 { suppressedReleases &= ~bit }
            else {
                flush()
                buttons &= ~bit
                flush(force: true)
            }
        } else if type == .scrollWheel {
            let smooth = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            scrollY += smooth ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) / 12 : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            scrollX += smooth ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) / 12 : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            flush()
        }
        return nil
    }

    func beginEntry(portal: MousePortal, fraction: Double? = nil, remainder: CGVector = .zero) {
        guard hasTap, mode == .local, !physicalButtonsDown() else { return }
        activeBounds = portal.bounds
        guard activeBounds.width > 0, activeBounds.height > 0 else { return }
        entryFraction = min(1, max(0, fraction ?? portal.seam.defaultEntryFraction))
        entryApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let parkingPoint = portal.seam.macPoint(remoteFraction: entryFraction, bounds: activeBounds, inset: 1)
        let result = cursor.capture(at: parkingPoint)
        guard result == .success else {
            entryApplicationPID = nil
            Log.write("Cursor capture failed: \(result.rawValue)")
            onRelease?(portal.deviceID, sequence, "无法在后台捕获鼠标，已保留 Mac 控制")
            return
        }
        mode = .entering
        activePortal = portal; sequence += 1
        lease = ControlLease(deviceID: portal.deviceID, epoch: sequence)
        enteredAt = now
        androidWidth = Double(portal.seam.remote.width); androidHeight = Double(portal.seam.remote.height)
        androidRotation = portal.seam.remote.rotation
        path = PointerPath(seam: portal.seam, macBounds: activeBounds, fraction: entryFraction, remainder: remainder)
        buttons = 0; inputSequence = 0; motionDirty = false; scrollX = 0; scrollY = 0
        Log.write("Enter requested: \(portal.deviceID), \(direction.rawValue), epoch=\(sequence)")
        onEnter?(portal.deviceID, path!.position, sequence)
        onChange?()
    }

    func accepts(_ event: [String: Any], from deviceID: String) -> Bool {
        lease?.accepts(deviceID: deviceID, epoch: (event["epoch"] as? Int) ?? -1) == true
    }

    func didEnter(_ event: [String: Any], from deviceID: String) {
        guard mode == .entering, accepts(event, from: deviceID) else { return }
        let entryMilliseconds = Int((now - enteredAt) * 1000)
        mode = .remote; enteredAt = now
        androidWidth = number(event, "width"); androidHeight = number(event, "height")
        androidRotation = (event["rotation"] as? Int) ?? -1
        if let seam = activePortal?.seam,
           (androidWidth != Double(seam.remote.width) || androidHeight != Double(seam.remote.height) || androidRotation != seam.remote.rotation) {
            returnToMac("设备方向已变化，重新越过边缘即可连接")
            return
        }
        Log.write("Controlling Android: \(deviceID), entry=\(entryMilliseconds)ms")
        onChange?()
    }

    func receiveCursor(_ event: [String: Any], from deviceID: String) {
        guard mode != .local, accepts(event, from: deviceID) else { return }
        if number(event, "width") != androidWidth || number(event, "height") != androidHeight
            || (event["rotation"] as? Int) != androidRotation {
            returnToMac("设备方向已变化，重新越过边缘即可连接")
        }
        // Feedback checks geometry and health, never overwrites the logical path.
    }

    func tick() {
        if mode == .local && cursor.isCaptured { cursor.restore() }
        if mode == .entering && now - enteredAt > 3.2 { returnToMac("设备定位超时，已返回 Mac") }
        if mode != .local { flush() }
    }

    func returnToMac(_ reason: String, at landing: CGPoint? = nil) {
        guard mode != .local || cursor.isCaptured else { return }
        let portal = activePortal, epoch = lease?.epoch ?? sequence
        let fraction = path?.fraction ?? entryFraction
        suppressedReleases |= buttons
        keyboard.end()
        mode = .local; buttons = 0
        motionDirty = false; scrollX = 0; scrollY = 0
        let frame = activeBounds.isEmpty ? bounds : activeBounds
        let returnPoint = landing ?? portal?.seam.macPoint(remoteFraction: fraction, bounds: frame, inset: 1)
        // Queue release before showing Mac; epoch fencing protects a rapid next visit.
        if let portal { onRelease?(portal.deviceID, epoch, reason) }
        let result = cursor.restore(at: returnPoint)
        if result != .success { Log.write("Cursor restore failed: \(result.rawValue)") }
        lastLocalPoint = returnPoint
        entryApplicationPID = nil
        activePortal = nil; lease = nil; path = nil
        onChange?()
        Log.write(reason)
    }

    private func flush(force: Bool = false) {
        guard mode != .local, let path, let lease else { return }
        let v = max(-127, min(127, Int(scrollY))), h = max(-127, min(127, Int(scrollX)))
        guard force || motionDirty || v != 0 || h != 0 else { return }
        motionDirty = false
        scrollY -= Double(v); scrollX -= Double(h)
        inputSequence += 1
        onInput?(lease.deviceID, PointerFrame(epoch: lease.epoch, sequence: inputSequence,
            position: path.position, buttons: buttons, wheel: v, pan: h))
    }

    func performKeyboardPointerAction(_ action: KeyboardMappingAction) {
        guard action.isPointerAction else { return }
        sendKeyboardPointerAction(action)
    }

    func cancelKeyboardPointerActions() { sendKeyboardPointerAction(nil) }

    private func sendKeyboardPointerAction(_ action: KeyboardMappingAction?) {
        guard mode == .remote, let lease else { return }
        // Position and physical buttons must reach Android before the mapped operation.
        flush(force: true)
        inputSequence += 1
        onPointerAction?(lease.deviceID, lease.epoch, inputSequence, action)
    }

    private func number(_ data: [String: Any], _ key: String) -> Double { (data[key] as? NSNumber)?.doubleValue ?? 0 }
    private func physicalButtonsDown() -> Bool { (0..<5).contains { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) } }
    private func anotherDisplayOccupies(_ p: CGPoint, except displayID: UInt32) -> Bool {
        NSScreen.screens.contains { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value, id != displayID else { return false }
            return CGDisplayBounds(id).contains(p)
        }
    }
    private func isDown(_ t: CGEventType) -> Bool { [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(t) }
    private func isUp(_ t: CGEventType) -> Bool { [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(t) }
    private func buttonBit(_ type: CGEventType, _ event: CGEvent) -> Int {
        if [.leftMouseDown, .leftMouseUp].contains(type) { return 1 }
        if [.rightMouseDown, .rightMouseUp].contains(type) { return 2 }
        let index = event.getIntegerValueField(.mouseEventButtonNumber)
        return index >= 2 && index <= 4 ? 1 << Int(index) : 0
    }
}
