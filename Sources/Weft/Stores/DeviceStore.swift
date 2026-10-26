import AppKit
import ApplicationServices
import Combine
import WeftCore

final class DeviceStore: ObservableObject {
    @Published var profiles: [DeviceProfile] = []
    @Published var statuses: [String: DeviceStatus] = [:]
    @Published var endpoints: [DeviceEndpoint] = []
    @Published var screens: [MacScreen] = []
    @Published var selectedID: String?
    @Published var section: SettingsSection = .devices
    @Published var layoutDisplayID: UInt32 = CGMainDisplayID()
    @Published var activeDeviceID: String?
    @Published var switching = false
    @Published var paused = false
    @Published var permissionGranted = false
    @Published var notice = ""
    @Published var discoveryError = ""
    @Published var showingAddDevice = false
    @Published var pairingBusy = false
    @Published var pairingMessage = ""
    @Published var showOnLaunch = true {
        didSet { if !preview { defaults.set(showOnLaunch, forKey: "showSettingsOnLaunch") } }
    }
    let mouse = MouseController()
    let discovery = DeviceDiscovery()
    let defaults: UserDefaults
    let preview: Bool
    let scrcpy: ScrcpyConfiguration
    let mirroring: ScrcpySessionManager
    var sessions: [String: DeviceSession] = [:]
    var suspended: Set<String> = []
    var requested: Set<String> = []
    var firstImport: Bool
    var sleeping = false
    var sessionActive = true
    var stopped = false
    var lastScan = -100.0
    var lastControlledID: String?
    var heartbeatTimer: Timer?
    var motionTimer: Timer?
    var adbObservation: AnyCancellable?
    var adbErrorObservation: AnyCancellable?
    var beforeEntry: (() -> Void)?
    var onStateChange: (() -> Void)?
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var connectedCount: Int { statuses.values.filter { $0.phase == .ready }.count }
    var selected: DeviceProfile? { profiles.first { $0.id == selectedID } }
    var controlName: String { activeDeviceID.flatMap { profile($0)?.name } ?? "Mac" }
    var available: [DeviceEndpoint] {
        var seen = Set<String>()
        return endpoints.sorted { $0.usb && !$1.usb }.filter { endpoint in
            !profiles.contains(where: { $0.id == endpoint.hardwareID }) && seen.insert(endpoint.hardwareID).inserted
        }
    }

    init(defaults: UserDefaults = .standard, preview: Bool = false,
         scrcpy: ScrcpyConfiguration = .shared, mirroring: ScrcpySessionManager = ScrcpySessionManager()) {
        self.defaults = defaults; self.preview = preview
        self.scrcpy = scrcpy; self.mirroring = mirroring
        firstImport = defaults.data(forKey: "deviceProfiles.v2") == nil
        if !preview, let data = defaults.data(forKey: "deviceProfiles.v2"),
           let saved = try? JSONDecoder().decode([DeviceProfile].self, from: data) { profiles = saved }
        showOnLaunch = defaults.object(forKey: "showSettingsOnLaunch") as? Bool ?? true
        lastControlledID = defaults.string(forKey: "lastControlledDevice")
        selectedID = profiles.first?.id
        refreshScreens()
        wireMouse()
        discovery.onUpdate = { [weak self] values in self?.discovered(values) }
        discovery.onFailure = { [weak self] message in self?.discoveryError = message }
        if preview { loadPreview() }
    }

    func profile(_ id: String) -> DeviceProfile? { profiles.first { $0.id == id } }
    func status(_ id: String) -> DeviceStatus { statuses[id] ?? DeviceStatus() }
    func select(_ id: String?) {
        selectedID = id; section = .devices
        if let id, let profile = profile(id) { layoutDisplayID = effectiveDisplay(profile) }
    }
    func effectiveDisplay(_ profile: DeviceProfile) -> UInt32 {
        screens.contains { $0.id == profile.displayID } ? profile.displayID : CGMainDisplayID()
    }
    func save() {
        guard !preview, let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: "deviceProfiles.v2")
    }
    func update(_ id: String, _ body: (inout DeviceProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let previous = profiles[index]
        var changed = previous; body(&changed)
        changed.speed = min(3, max(0.1, changed.speed))
        changed.position = min(1, max(0, changed.position))
        if mouse.activeDeviceID == id { mouse.returnToMac("设备设置已更改") }
        profiles[index] = changed
        if !previous.autoConnect && changed.autoConnect { suspended.remove(id) }
        if previous.autoConnect && !changed.autoConnect {
            requested.remove(id)
            sessions[id]?.retry.cancel()
            if status(id).phase == .connecting, let session = sessions[id], session.automaticAttempt {
                session.connection.stop(); session.automaticAttempt = false
                setStatus(id, DeviceStatus(phase: .paused, transport: status(id).transport))
            }
        }
        save(); refreshPortals(); reconcile()
    }
    func resetLayout() {
        mouse.returnToMac("布局已重置")
        for index in profiles.indices {
            profiles[index].direction = .below
            profiles[index].position = Double(index + 1) / Double(profiles.count + 1)
            profiles[index].edgeOffsetMM = nil
            profiles[index].displayID = CGMainDisplayID()
        }
        layoutDisplayID = CGMainDisplayID(); save(); refreshPortals()
    }
    func add(_ endpoint: DeviceEndpoint) {
        guard endpoint.usable, !profiles.contains(where: { $0.id == endpoint.hardwareID }) else { return }
        let name = endpoint.model == "OPD2413" ? "一加平板" : endpoint.model == "Seeker" ? "Seeker 手机" : endpoint.model
        var device = DeviceProfile(id: endpoint.hardwareID, name: name, model: endpoint.model, kind: endpoint.kind,
            position: 0.5 + Double(profiles.count) * 0.01)
        if firstImport, defaults.string(forKey: "deviceSerial") == endpoint.serial {
            device.direction = Direction(rawValue: defaults.string(forKey: "direction") ?? "below") ?? .below
            device.speed = defaults.object(forKey: "speed") as? Double ?? 1
            device.displayID = UInt32(defaults.integer(forKey: "displayID"))
        }
        profiles.append(device); select(device.id); requested.insert(device.id); save(); reconcile()
    }
    func remove(_ id: String) {
        guard profile(id) != nil else { return }
        mirroring.forget(id)
        if mouse.activeDeviceID == id { mouse.returnToMac("设备已删除") }
        if let session = sessions.removeValue(forKey: id) {
            session.connection.onEvent = nil; session.connection.onFailure = nil
            session.connection.stop()
        }
        profiles.removeAll { $0.id == id }
        statuses.removeValue(forKey: id)
        suspended.remove(id); requested.remove(id)
        if lastControlledID == id {
            lastControlledID = nil
            if !preview { defaults.removeObject(forKey: "lastControlledDevice") }
        }
        if selectedID == id {
            selectedID = profiles.first?.id
            if let selected { layoutDisplayID = effectiveDisplay(selected) }
        }
        if !preview, let legacySerial = defaults.string(forKey: "deviceSerial"),
           profiles.isEmpty || legacySerial == id || endpoints.contains(where: { $0.hardwareID == id && $0.serial == legacySerial }) {
            for key in ["deviceSerial", "direction", "speed", "displayID"] { defaults.removeObject(forKey: key) }
        }
        // Persist an empty list too, so discovery and relaunch cannot import deleted devices again.
        firstImport = false
        save(); refreshPortals(); onStateChange?()
    }
    func connect(_ id: String) {
        guard !paused, profile(id) != nil, ![.ready, .connecting].contains(status(id).phase) else { return }
        beginConnectionRound(id)
        discovery.scan(); reconcile()
    }
    func beginConnectionRound(_ id: String) {
        guard profile(id) != nil else { return }
        let session = sessions[id] ?? DeviceSession()
        session.retry.beginRound(); session.lastFailure = ""; session.attemptAt = -100
        sessions[id] = session
        suspended.remove(id); requested.insert(id)
    }
    func connectAll() {
        guard !profiles.isEmpty else { return }
        paused = false
        for device in profiles {
            suspended.remove(device.id)
            guard ![.ready, .connecting].contains(status(device.id).phase) else { continue }
            beginConnectionRound(device.id)
        }
        discovery.scan(); reconcile(); refreshPortals(); onStateChange?()
    }
    func disconnect(_ id: String) {
        suspended.insert(id); requested.remove(id)
        if mouse.activeDeviceID == id { mouse.returnToMac("设备连接已暂停") }
        sessions[id]?.connection.stop()
        sessions[id]?.automaticAttempt = false
        sessions[id]?.retry.cancel()
        setStatus(id, DeviceStatus(phase: .paused)); refreshPortals()
    }
    func disconnectAll() {
        for device in profiles { disconnect(device.id) }
    }
    func togglePause() {
        paused.toggle()
        if paused {
            mouse.returnToMac("已暂停全部连接")
            for profile in profiles {
                if status(profile.id).phase == .ready { requested.insert(profile.id) }
                sessions[profile.id]?.connection.stop()
                sessions[profile.id]?.retry.cancel()
                setStatus(profile.id, DeviceStatus(phase: .paused))
            }
        } else {
            for session in sessions.values { session.attemptAt = -100 }
            reconcile()
        }
        refreshPortals(); onStateChange?()
    }
    func enterDevice(_ id: String) {
        guard !paused, status(id).phase == .ready else { return }
        guard mouse.hasTap else { requestPermission(); return }
        beforeEntry?()
        if mouse.mode != .local { mouse.returnToMac("切换控制设备") }
        guard let portal = mouse.portals.first(where: { $0.deviceID == id }) else { return }
        mouse.beginEntry(portal: portal)
    }
    func returnToMac() { mouse.returnToMac("已返回 Mac") }
    func enterLast() {
        let id = [lastControlledID, selectedID].compactMap { $0 }.first { status($0).phase == .ready }
            ?? profiles.first { status($0.id).phase == .ready }?.id
        if let id { enterDevice(id) }
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func refreshScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            let bounds = CGDisplayBounds(id)
            var size = CGDisplayScreenSize(id)
            if Int(CGDisplayRotation(id).rounded()) % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            let estimated = size.width <= 0 || size.height <= 0
            if estimated { size = CGSize(width: bounds.width * 25.4 / 72, height: bounds.height * 25.4 / 72) }
            return MacScreen(id: id, name: screen.localizedName, bounds: bounds, sizeMM: size, estimatedSize: estimated)
        }
        if !screens.contains(where: { $0.id == layoutDisplayID }) { layoutDisplayID = CGMainDisplayID() }
        refreshPortals()
    }
    func refreshPortals() {
        guard !paused, !sleeping, sessionActive else { mouse.portals = []; return }
        mouse.portals = placements.compactMap { placement in
            guard status(placement.deviceID).phase == .ready, placement.seam.hasContact,
                  let device = profile(placement.deviceID),
                  let screen = screens.first(where: { $0.id == placement.displayID }) else { return nil }
            return MousePortal(deviceID: device.id, displayID: screen.id, bounds: screen.bounds,
                speed: device.speed, autoCross: device.autoCross, seam: placement.seam)
        }
    }
}
