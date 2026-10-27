import AppKit
import WeftCore

/// Owns local keyboard state only for the current control lease.
final class KeyboardController {
    var onFrame: ((KeyboardInputFrame, Int, Int) -> Void)?
    private(set) var sharing = false
    private var mapper = KeyboardInputMapper(mapping: KeyboardMapping())
    private var epoch = 0
    private var sequence = 0
    private var lastFrame: KeyboardInputFrame?
    private var suppressedUps: Set<UInt16> = []
    private var entryKeys: Set<UInt16> = []
    private var ignoredModifiers: UInt8 = 0

    var canBegin: Bool {
        (UInt16(0)...126).allSatisfy { code in
            KeyboardInputMapper.hidUsage(for: code) == nil || code == 57 || suppressedUps.contains(code) ||
                !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        }
    }

    func consumeShortcut(_ code: UInt16) { suppressedUps.insert(code) }

    func begin(mapping: KeyboardMapping, epoch: Int) {
        sharing = mapping.enabled; self.epoch = epoch; sequence = 0; lastFrame = nil
        guard sharing else { return }
        suppressedUps = suppressedUps.filter { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
        mapper = KeyboardInputMapper(mapping: mapping)
        entryKeys = suppressedUps
        let flags = CGEventSource.flagsState(.combinedSessionState)
        // The modifiers used to enter via ⌃⌥M must not become the first Android chord.
        ignoredModifiers = suppressedUps.contains(46) ? Self.hidModifiers(flags) : 0
        emit(mapper.begin(modifiers: Self.hidModifiers(flags) & ~ignoredModifiers, capsLock: flags.contains(.maskAlphaShift)))
    }

    func end() {
        guard sharing else { return }
        suppressedUps.formUnion(mapper.heldKeyCodes)
        emit(mapper.release())
        sharing = false; entryKeys.removeAll(); ignoredModifiers = 0; lastFrame = nil
    }

    /// True means this event belongs to the remote session and must be suppressed locally.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return false }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, suppressedUps.remove(code) != nil {
            entryKeys.remove(code)
            return true
        }
        if !sharing {
            if type == .keyDown, suppressedUps.contains(code) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
                suppressedUps.remove(code) // Recover if a key-up was lost while the tap was disabled.
            }
            return false
        }
        if entryKeys.contains(code) { return true }
        let physical = Self.hidModifiers(event.flags)
        ignoredModifiers &= physical
        for frame in mapper.modifiersChanged(physical & ~ignoredModifiers, capsLock: event.flags.contains(.maskAlphaShift)) { emit(frame) }
        if type == .keyDown {
            for frame in mapper.keyDown(code, repeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) { emit(frame) }
        } else if type == .keyUp {
            for frame in mapper.keyUp(code) { emit(frame) }
        }
        return true
    }

    private func emit(_ frame: KeyboardInputFrame) {
        guard frame.action != nil || frame != lastFrame else { return }
        sequence += 1; onFrame?(frame, epoch, sequence)
        var state = frame; state.action = nil; lastFrame = state
    }

    private static func hidModifiers(_ flags: CGEventFlags) -> UInt8 {
        // Device-side flags from IOKit/hidsystem/IOLLEvent.h preserve left/right keys.
        let raw = flags.rawValue
        var bits: UInt8 = 0
        let sides: [(UInt64, UInt8)] = [(0x1,0x01),(0x2,0x02),(0x20,0x04),(0x8,0x08),
                                       (0x2000,0x10),(0x4,0x20),(0x40,0x40),(0x10,0x80)]
        for (mask, hid) in sides {
            if raw & mask != 0 { bits |= hid }
        }
        // Synthetic/layout events may provide only the device-independent flags.
        if flags.contains(.maskControl), bits & 0x11 == 0 { bits |= 0x01 }
        if flags.contains(.maskShift), bits & 0x22 == 0 { bits |= 0x02 }
        if flags.contains(.maskAlternate), bits & 0x44 == 0 { bits |= 0x04 }
        if flags.contains(.maskCommand), bits & 0x88 == 0 { bits |= 0x08 }
        return bits
    }
}
