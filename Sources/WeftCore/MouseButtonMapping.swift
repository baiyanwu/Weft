import Foundation

public enum MouseMappingButton: Int, Codable, CaseIterable, Identifiable {
    case left = 1, right, middle, back, forward
    public var id: Int { rawValue }
    public var mask: Int { 1 << (rawValue - 1) }
}

public enum MouseMappingAction: String, Codable, CaseIterable, Identifiable {
    case original, back, home, recents, volumeUp, volumeDown
    public var id: Self { self }
}

public struct MouseButtonMapping: Codable, Equatable {
    public var enabled: Bool
    private var assignments: [String: MouseMappingAction] = [:]

    public init(enabled: Bool = false) { self.enabled = enabled }

    public subscript(_ button: MouseMappingButton) -> MouseMappingAction {
        get { assignments[String(button.rawValue)] ?? .original }
        set {
            let key = String(button.rawValue)
            if newValue == .original { assignments.removeValue(forKey: key) }
            else { assignments[key] = newValue }
        }
    }

    public func command(epoch: Int) -> String {
        let actions = MouseMappingButton.allCases.map { self[$0].rawValue }.joined(separator: " ")
        return "map-buttons \(epoch) \(enabled ? 1 : 0) \(actions)"
    }

    private enum CodingKeys: String, CodingKey { case enabled, assignments }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? values.decode(Bool.self, forKey: .enabled)) ?? false
        let saved = (try? values.decode([String: String].self, forKey: .assignments)) ?? [:]
        for button in MouseMappingButton.allCases {
            if let value = saved[String(button.rawValue)], let action = MouseMappingAction(rawValue: value) {
                self[button] = action
            }
        }
    }
}
