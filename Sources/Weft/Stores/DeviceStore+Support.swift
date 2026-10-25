import AppKit
import WeftCore

extension DeviceStore {
    func pair(pairAddress: String, code: String, connectAddress: String, alreadyPaired: Bool) {
        guard !pairingBusy else { return }
        guard PairingValidation.endpoint(connectAddress), alreadyPaired ||
                (PairingValidation.endpoint(pairAddress) && PairingValidation.code(code)) else {
            pairingMessage = "请填写有效的 IP:端口；配对码为 6 位数字。"; return
        }
        pairingBusy = true; pairingMessage = alreadyPaired ? "正在连接…" : "正在配对…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let adb = try ADBConfiguration.shared.requireExecutable().path
                if !alreadyPaired {
                    let output = try ADB.run(at: adb, ["pair", pairAddress], input: code + "\n", timeout: 20)
                    guard output.lowercased().contains("successfully paired") else { throw BridgeError.message("配对未成功，请检查配对码和端口。") }
                }
                let output = try ADB.run(at: adb, ["connect", connectAddress], timeout: 10)
                guard output.lowercased().contains("connected to") else { throw BridgeError.message("连接未成功，请确认无线调试页的连接端口。") }
                DispatchQueue.main.async {
                    self?.pairingBusy = false; self?.pairingMessage = "连接成功，请在下方列表中添加设备。"; self?.discovery.scan()
                }
            } catch {
                DispatchQueue.main.async { self?.pairingBusy = false; self?.pairingMessage = error.localizedDescription }
            }
        }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "weft-diagnostics.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: [String: Any] = ["version": "0.2.0", "time": Date().ISO8601Format(),
            "permission": permissionGranted, "paused": paused,
            "activeDevice": activeDeviceID ?? "Mac",
            "devices": profiles.map { device -> [String: Any] in
                ["name": device.name, "model": device.model, "direction": device.direction.rawValue,
                 "autoCross": device.autoCross, "state": status(device.id).label, "message": status(device.id).message]
            }]
        do { try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
        catch { notice = "导出失败：\(error.localizedDescription)" }
    }
    func loadPreview() {
        firstImport = false
        profiles = [DeviceProfile(id: "preview-pad", name: "一加平板", model: "OPD2413", kind: .tablet),
            DeviceProfile(id: "preview-phone", name: "Seeker 手机", model: "Seeker", kind: .phone, direction: .right),
            DeviceProfile(id: "preview-offline", name: "Pixel 8", model: "Pixel 8", kind: .phone, direction: .left)]
        selectedID = profiles[0].id; permissionGranted = true
        profiles[0].screenGeometry = RemoteScreenGeometry(width: 3392, height: 2400, rotation: 1,
            widthMM: 273, heightMM: 193, estimated: true)
        profiles[1].screenGeometry = RemoteScreenGeometry(width: 1200, height: 2670, rotation: 0,
            widthMM: 68, heightMM: 151, estimated: true)
        profiles[2].screenGeometry = RemoteScreenGeometry(width: 1080, height: 2400, rotation: 0,
            widthMM: 66, heightMM: 147, estimated: true)
        statuses = ["preview-pad": DeviceStatus(phase: .ready, transport: "USB"),
                    "preview-phone": DeviceStatus(phase: .ready, transport: "USB"),
                    "preview-offline": DeviceStatus()]
    }
}
