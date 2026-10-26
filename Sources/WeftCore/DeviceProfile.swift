import Foundation

public enum DeviceKind: String, Codable, CaseIterable {
    case tablet, phone
}

public struct DeviceProfile: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var model: String
    public var kind: DeviceKind
    public var direction: Direction
    public var displayID: UInt32
    public var position: Double
    public var speed: Double
    public var autoConnect: Bool
    public var autoCross: Bool
    public var mouseMapping = MouseButtonMapping()
    public var keyboardMapping = KeyboardMapping()
    public var screenGeometry: RemoteScreenGeometry?
    public var edgeOffsetMM: Double?

    public init(id: String, name: String, model: String, kind: DeviceKind,
                direction: Direction = .below, displayID: UInt32 = 0,
                position: Double = 0.5, speed: Double = 1, autoConnect: Bool = true, autoCross: Bool = true) {
        self.id = id; self.name = name; self.model = model; self.kind = kind
        self.direction = direction; self.displayID = displayID
        self.position = position; self.speed = speed; self.autoConnect = autoConnect; self.autoCross = autoCross
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, model, kind, direction, displayID, position, speed, autoConnect, autoCross, mouseMapping, keyboardMapping, screenGeometry, edgeOffsetMM
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        model = try values.decode(String.self, forKey: .model)
        kind = try values.decode(DeviceKind.self, forKey: .kind)
        direction = try values.decode(Direction.self, forKey: .direction)
        displayID = try values.decode(UInt32.self, forKey: .displayID)
        position = try values.decode(Double.self, forKey: .position)
        speed = try values.decode(Double.self, forKey: .speed)
        autoConnect = try values.decode(Bool.self, forKey: .autoConnect)
        // Legacy profiles had no device-level setting; do not carry a global disable into every device.
        autoCross = try values.decodeIfPresent(Bool.self, forKey: .autoCross) ?? true
        mouseMapping = (try? values.decode(MouseButtonMapping.self, forKey: .mouseMapping)) ?? MouseButtonMapping()
        keyboardMapping = (try? values.decode(KeyboardMapping.self, forKey: .keyboardMapping)) ?? KeyboardMapping()
        screenGeometry = try values.decodeIfPresent(RemoteScreenGeometry.self, forKey: .screenGeometry)
        edgeOffsetMM = try values.decodeIfPresent(Double.self, forKey: .edgeOffsetMM)
    }
}

public struct EdgeSegment: Equatable {
    public var lower: Double
    public var upper: Double
    public init(lower: Double = 0, upper: Double = 1) { self.lower = lower; self.upper = upper }
    public func contains(_ fraction: Double) -> Bool {
        fraction >= lower && (fraction < upper || upper == 1 && fraction <= 1)
    }
    public func toRemote(_ fraction: Double) -> Double {
        min(1, max(0, (fraction - lower) / max(0.0001, upper - lower)))
    }
    public func toMac(_ fraction: Double) -> Double {
        lower + min(1, max(0, fraction)) * (upper - lower)
    }
}

public struct ControlLease: Equatable {
    public let deviceID: String
    public let epoch: Int
    public init(deviceID: String, epoch: Int) { self.deviceID = deviceID; self.epoch = epoch }
    public func accepts(deviceID: String, epoch: Int) -> Bool {
        self.deviceID == deviceID && self.epoch == epoch
    }
}

public enum PairingValidation {
    public static func endpoint(_ text: String) -> Bool {
        guard text.count < 260, let colon = text.lastIndex(of: ":"),
              let port = Int(text[text.index(after: colon)...]), (1...65535).contains(port) else { return false }
        let host = String(text[..<colon])
        guard !host.isEmpty, !host.hasPrefix("-") else { return false }
        let permitted = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]")
        return host.unicodeScalars.allSatisfy { permitted.contains($0) }
    }
    public static func code(_ text: String) -> Bool {
        text.count == 6 && text.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}
