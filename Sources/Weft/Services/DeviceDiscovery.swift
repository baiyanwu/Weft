import Foundation
import WeftCore

final class DeviceDiscovery {
    var onUpdate: (([DeviceEndpoint]) -> Void)?
    var onFailure: ((String) -> Void)?
    private let queue = DispatchQueue(label: "weft.discovery", qos: .utility)
    private var metadata: [String: (String, String, DeviceKind)] = [:]
    private var busy = false
    func scan() {
        guard !busy else { return }; busy = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let text = try ADB.run(["devices", "-l"])
                var devices: [DeviceEndpoint] = []
                for line in text.split(separator: "\n") {
                    let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    guard fields.count > 1, ["device", "offline", "unauthorized"].contains(fields[1]) else { continue }
                    let serial = fields[0], authorization = fields[1]
                    let model = fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? "Android 设备"
                    let usb = fields.contains { $0.hasPrefix("usb:") }
                    if authorization == "device", self.metadata[serial] == nil {
                        let hardware = (try? ADB.run(["-s", serial, "shell", "getprop", "ro.serialno"], timeout: 3)) ?? ""
                        let traits = (try? ADB.run(["-s", serial, "shell", "getprop", "ro.build.characteristics"], timeout: 3)) ?? ""
                        let lower = model.lowercased()
                        let tablet = traits.contains("tablet") || lower.contains("pad") || lower.contains("tab") || lower.hasPrefix("opd")
                        self.metadata[serial] = (hardware.isEmpty || hardware == "unknown" ? serial : hardware, model, tablet ? .tablet : .phone)
                    }
                    let meta = self.metadata[serial] ?? (serial, model, .phone)
                    devices.append(DeviceEndpoint(serial: serial, hardwareID: meta.0, model: meta.1, kind: meta.2, usb: usb, authorization: authorization))
                }
                DispatchQueue.main.async { self.busy = false; self.onUpdate?(devices) }
            } catch { DispatchQueue.main.async { self.busy = false; self.onFailure?(error.localizedDescription) } }
        }
    }
}
