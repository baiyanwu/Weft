import Foundation

struct WirelessAddressInput {
    var octets = Array(repeating: "", count: 4)
    var port = ""

    var endpoint: String? {
        guard Self.validOctets(octets), Self.validNumber(port, maximum: 65535),
              let number = Int(port), number > 0 else { return nil }
        return octets.map { String(Int($0)!) }.joined(separator: ".") + ":\(number)"
    }

    mutating func paste(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count) else { return false }
        let values = parts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard Self.validOctets(values) else { return false }
        if parts.count == 2 {
            guard Self.validNumber(parts[1], maximum: 65535), Int(parts[1])! > 0 else { return false }
            port = parts[1]
        }
        octets = values
        return true
    }

    private static func validOctets(_ values: [String]) -> Bool {
        values.count == 4 && values.allSatisfy { validNumber($0, maximum: 255) }
    }

    private static func validNumber(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.count <= String(maximum).count &&
            value.utf8.allSatisfy { (48...57).contains($0) } &&
            Int(value).map { $0 <= maximum } == true
    }
}
