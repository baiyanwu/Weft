import Foundation

public struct KeyboardModifiers: OptionSet, Codable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

/// A physical Mac key and its modifier groups, independent of display text.
public struct KeyboardKeyCombination: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    public var modifiers: KeyboardModifiers
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: KeyboardModifiers = [], keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }

    public var isReserved: Bool {
        keyCode == 46 && modifiers.contains([.control, .option])
    }

    public func matches(_ other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

public enum KeyboardMappingAction: String, Codable, CaseIterable, Identifiable {
    case key
    case click, doubleClick, longClick, rightClick, middleClick
    case scrollUp, scrollDown, scrollLeft, scrollRight
    case back, home, recents, forward, notifications, quickSettings, collapsePanels, settings
    case dpadUp, dpadDown, dpadLeft, dpadRight, dpadCenter, pageUp, pageDown
    case volumeUp, volumeDown, mute, playPause, nextTrack, previousTrack, mediaStop
    case screenshot, power, wake, sleep, brightnessUp, brightnessDown, camera, search, assistant, menu
    case disabled
    public var id: Self { self }

    /// These operations use the existing pointer, including its position and held buttons.
    public var isPointerAction: Bool {
        switch self {
        case .click, .doubleClick, .longClick, .rightClick, .middleClick,
             .scrollUp, .scrollDown, .scrollLeft, .scrollRight: return true
        default: return false
        }
    }

    public var repeatsWhileHeld: Bool {
        switch self {
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight, .volumeUp, .volumeDown,
             .brightnessUp, .brightnessDown, .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
             .pageUp, .pageDown: return true
        default: return false
        }
    }
}

public struct KeyboardMappingTarget: Codable, Equatable {
    public var action: KeyboardMappingAction
    public var shortcut: KeyboardKeyCombination?

    public init(action: KeyboardMappingAction, shortcut: KeyboardKeyCombination? = nil) {
        self.action = action; self.shortcut = shortcut
    }
}

public struct KeyboardMappingRule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var shortcut: KeyboardKeyCombination
    public var target: KeyboardMappingTarget

    public init(id: UUID = UUID(), shortcut: KeyboardKeyCombination, target: KeyboardMappingTarget) {
        self.id = id; self.shortcut = shortcut; self.target = target
    }
}

public struct KeyboardMapping: Codable, Equatable {
    public var enabled: Bool
    public var rules: [KeyboardMappingRule]

    public init(enabled: Bool = false, rules: [KeyboardMappingRule]? = nil) {
        self.enabled = enabled; self.rules = rules ?? Self.defaultRules
    }

    public static var defaultRules: [KeyboardMappingRule] {
        [(UInt16(8), "C"), (UInt16(9), "V"), (UInt16(0), "A")].map { code, label in
            KeyboardMappingRule(shortcut: KeyboardKeyCombination(keyCode: code, modifiers: .command, keyLabel: label),
                target: KeyboardMappingTarget(action: .key,
                    shortcut: KeyboardKeyCombination(keyCode: code, modifiers: .control, keyLabel: label)))
        }
    }
}
