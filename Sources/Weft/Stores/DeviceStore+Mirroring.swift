import Foundation

extension DeviceStore {
    func mirroringEndpoint(_ id: String) -> DeviceEndpoint? {
        let usable = endpoints.filter { $0.hardwareID == id && $0.usable }
        return usable.first { $0.serial == sessions[id]?.endpoint }
            ?? usable.first { $0.usb } ?? usable.first
    }

    func startMirroring(_ id: String) {
        guard !preview, !stopped, let device = profile(id), !mirroring.state(id).isActive else { return }
        guard let endpoint = mirroringEndpoint(id) else {
            mirroring.fail(id, message: "设备未连接，请检查 USB 或无线调试连接。")
            return
        }
        do {
            let tool = try scrcpy.requireExecutable()
            let adb = try ADBConfiguration.shared.requireExecutable()
            mirroring.start(id: id, serial: endpoint.serial, name: device.name, executable: tool.path, adb: adb.path)
        } catch {
            mirroring.fail(id, message: error.localizedDescription)
        }
    }
}
