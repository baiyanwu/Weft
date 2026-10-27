import Foundation

public struct KeyboardInputFrame: Equatable {
    public var modifiers: UInt8
    public var capsLock: Bool
    public var usages: [UInt8]
    public var action: KeyboardMappingAction?

    public func command(epoch: Int, sequence: Int) -> String {
        let keys = usages.isEmpty ? "-" : usages.map { String(format: "%02x", $0) }.joined()
        return "keyboard \(epoch) \(sequence) \(modifiers) \(capsLock ? 1 : 0) \(action?.rawValue ?? "none") \(keys)"
    }
}

extension KeyboardModifiers {
    /// Both physical sides for matching; output chords use the left-side bits.
    var hidMask: UInt8 {
        var bits: UInt8 = 0
        if contains(.control) { bits |= 0x11 }
        if contains(.shift) { bits |= 0x22 }
        if contains(.option) { bits |= 0x44 }
        if contains(.command) { bits |= 0x88 }
        return bits
    }
    var hidOutput: UInt8 { hidMask & 0x0f }
    init(hid: UInt8) {
        self = []
        if hid & 0x11 != 0 { insert(.control) }
        if hid & 0x22 != 0 { insert(.shift) }
        if hid & 0x44 != 0 { insert(.option) }
        if hid & 0x88 != 0 { insert(.command) }
    }
}

/// Full snapshots preserve held keys, overlapping mapped keys and release ordering.
public struct KeyboardInputMapper {
    private struct HeldKey {
        var usage: UInt8?
        var modifiers: UInt8 = 0
        var consumed: UInt8 = 0
        var action: KeyboardMappingAction?
    }
    private let rules: [KeyboardMappingRule]
    private var held: [UInt16: HeldKey] = [:]
    private var physical: UInt8 = 0
    private var deferred: UInt8 = 0
    private var used: UInt8 = 0
    private var consumed: UInt8 = 0
    private var capsLock = false
    public var heldKeyCodes: Set<UInt16> { Set(held.keys) }

    public init(mapping: KeyboardMapping) { rules = mapping.rules.filter { !$0.shortcut.isReserved } }

    public mutating func begin(modifiers: UInt8, capsLock: Bool) -> KeyboardInputFrame {
        held.removeAll(); physical = modifiers; used = 0; consumed = 0
        deferred = modifiers & potentialMappingModifiers
        self.capsLock = capsLock
        return snapshot()
    }

    public mutating func modifiersChanged(_ modifiers: UInt8, capsLock: Bool) -> [KeyboardInputFrame] {
        var frames: [KeyboardInputFrame] = []
        let released = physical & ~modifiers
        // A modifier pressed alone still reaches Android, but a mapped Command chord
        // must not first produce a standalone Android Meta press/release.
        let standalone = released & deferred & ~used
        if standalone != 0 {
            let forward = deferred & ~used
            frames.append(snapshot(allowDeferred: forward))
            deferred &= ~forward; used |= forward
        }
        let pressed = modifiers & ~physical
        physical = modifiers; deferred &= modifiers; used &= modifiers; consumed &= modifiers
        if held.isEmpty { deferred |= pressed & potentialMappingModifiers }
        else { used |= pressed }
        self.capsLock = capsLock
        frames.append(snapshot())
        return frames
    }

    public mutating func keyDown(_ code: UInt16, repeat repeated: Bool) -> [KeyboardInputFrame] {
        if let existing = held[code] {
            if repeated, existing.action?.repeatsWhileHeld == true {
                return [snapshot(action: existing.action)]
            }
            return [] // Native Android keyboard repeat owns ordinary held keys.
        }
        let sourceModifiers = KeyboardModifiers(hid: physical)
        let rule = rules.first { $0.shortcut.keyCode == code && $0.shortcut.modifiers == sourceModifiers }
        var key = HeldKey(usage: Self.hidUsage(for: code))
        if let rule {
            key.consumed = rule.shortcut.modifiers.hidMask
            switch rule.target.action {
            case .key:
                if let target = rule.target.shortcut, let usage = Self.hidUsage(for: target.keyCode) {
                    key.usage = usage; key.modifiers = target.modifiers.hidOutput
                } else { key = HeldKey(usage: Self.hidUsage(for: code)) }
            case .disabled: key.usage = nil
            default: key.usage = nil; key.action = rule.target.action
            }
            consumed |= key.consumed & physical
        } else {
            // An unmapped chord, following a mapped one with the same modifier held,
            // resumes the original modifier rather than inheriting the old mapping.
            consumed &= ~physical
        }
        held[code] = key; deferred = 0; used |= physical
        return [snapshot(action: key.action)]
    }

    public mutating func keyUp(_ code: UInt16) -> [KeyboardInputFrame] {
        guard held.removeValue(forKey: code) != nil else { return [] }
        return [snapshot()]
    }

    public mutating func release() -> KeyboardInputFrame {
        held.removeAll(); physical = 0; deferred = 0; used = 0; consumed = 0
        return snapshot()
    }

    private var potentialMappingModifiers: UInt8 {
        rules.reduce(UInt8(0)) { $0 | $1.shortcut.modifiers.hidMask }
    }
    private func snapshot(action: KeyboardMappingAction? = nil, allowDeferred: UInt8 = 0) -> KeyboardInputFrame {
        let hidden = held.values.reduce(consumed) { $0 | $1.consumed }
        let mapped = held.values.reduce(UInt8(0)) { $0 | $1.modifiers }
        let modifiers = (physical & ~hidden & ~(deferred & ~allowDeferred)) | mapped
        return KeyboardInputFrame(modifiers: modifiers, capsLock: capsLock,
            usages: Set(held.values.compactMap(\.usage)).sorted(), action: action)
    }

    /// Apple virtual key codes -> USB HID Keyboard/Keypad usages (physical positions).
    public static func hidUsage(for code: UInt16) -> UInt8? { usages[code] }
    private static let usages: [UInt16: UInt8] = [
        0:0x04, 1:0x16, 2:0x07, 3:0x09, 4:0x0b, 5:0x0a, 6:0x1d, 7:0x1b, 8:0x06, 9:0x19,
        10:0x64, 11:0x05, 12:0x14, 13:0x1a, 14:0x08, 15:0x15, 16:0x1c, 17:0x17,
        18:0x1e, 19:0x1f, 20:0x20, 21:0x21, 22:0x23, 23:0x22, 24:0x2e, 25:0x26, 26:0x24,
        27:0x2d, 28:0x25, 29:0x27, 30:0x30, 31:0x12, 32:0x18, 33:0x2f, 34:0x0c, 35:0x13,
        36:0x28, 37:0x0f, 38:0x0d, 39:0x34, 40:0x0e, 41:0x33, 42:0x31, 43:0x36, 44:0x38,
        45:0x11, 46:0x10, 47:0x37, 48:0x2b, 49:0x2c, 50:0x35, 51:0x2a, 53:0x29, 57:0x39,
        64:0x6c, 65:0x63, 67:0x55, 69:0x57, 71:0x53, 72:0x80, 73:0x81, 74:0x7f,
        75:0x54, 76:0x58, 78:0x56, 79:0x6d, 80:0x6e, 81:0x67, 82:0x62, 83:0x59, 84:0x5a,
        85:0x5b, 86:0x5c, 87:0x5d, 88:0x5e, 89:0x5f, 90:0x6f, 91:0x60, 92:0x61,
        93:0x89, 94:0x87, 95:0x85, 96:0x3e, 97:0x3f, 98:0x40, 99:0x3c, 100:0x41, 101:0x42,
        102:0x91, 103:0x44, 104:0x90, 105:0x68, 106:0x6b, 107:0x69, 109:0x43, 111:0x45,
        113:0x6a, 114:0x49, 115:0x4a, 116:0x4b, 117:0x4c, 118:0x3d, 119:0x4d, 120:0x3b,
        121:0x4e, 122:0x3a, 123:0x50, 124:0x4f, 125:0x51, 126:0x52
    ]
}
