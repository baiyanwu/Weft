import AppKit
import ApplicationServices
import WeftCore

extension DeviceStore {
    func start() {
        guard !preview else { return }
        stopped = false
        scrcpy.scan()
        let adb = ADBConfiguration.shared
        observeADBConfiguration(adb)
        adb.scan()
        mouse.installTap(); permissionGranted = mouse.hasTap
        heartbeatTimer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        motionTimer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.mouse.tick() }
        RunLoop.main.add(heartbeatTimer!, forMode: .common)
        RunLoop.main.add(motionTimer!, forMode: .common)
        tick()
    }
    func observeADBConfiguration(_ adb: ADBConfiguration) {
        adbObservation = adb.$selected.map { $0?.path }.removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.adbConfigurationChanged() }
        adbErrorObservation = adb.$error.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self, !self.stopped else { return }
                self.discoveryError = message
            }
    }
    func stop() {
        stopped = true; mouse.returnToMac("weft 已退出"); mouse.uninstallTap()
        for id in Array(keyboardSessions.keys) { closeKeyboardConnection(id) }
        heartbeatTimer?.invalidate(); motionTimer?.invalidate()
        adbObservation = nil; adbErrorObservation = nil
        mirroring.stopAll()
        for session in sessions.values { session.connection.stop() }
    }
    func adbConfigurationChanged() {
        guard !stopped, !preview else { return }
        mirroring.stopAll()
        mouse.returnToMac("ADB 配置已更改")
        for id in Array(keyboardSessions.keys) { closeKeyboardConnection(id) }
        requested.formUnion(profiles.filter {
            !suspended.contains($0.id) && ([.ready, .connecting].contains(status($0.id).phase) ||
                sessions[$0.id]?.retry.isActive == true)
        }.map(\.id))
        for session in sessions.values {
            session.connection.onEvent = nil; session.connection.onFailure = nil
            session.connection.stop()
        }
        sessions.removeAll(); statuses.removeAll(); endpoints.removeAll()
        discovery.invalidate()
        lastScan = -100
        if ADB.path != nil { discovery.scan() }
        refreshPortals(); onStateChange?()
    }
    func wireMouse() {
        mouse.keyboard.onFrame = { [weak self] frame, epoch, sequence in
            guard let self, let id = self.mouse.activeDeviceID, let session = self.keyboardSessions[id],
                  session.controlEpoch != nil, session.epoch == epoch else { return }
            var keyboardFrame = frame
            if frame.action?.isPointerAction == true { keyboardFrame.action = nil }
            session.connection.send(keyboardFrame.command(epoch: epoch, sequence: sequence))
            if let action = frame.action, action.isPointerAction { self.mouse.performKeyboardPointerAction(action) }
        }
        mouse.onPointerAction = { [weak self] id, epoch, sequence, action in
            self?.sessions[id]?.connection.send("pointer-action \(epoch) \(sequence) \(action?.rawValue ?? "cancel")")
        }
        mouse.onEnter = { [weak self] id, position, epoch in
            guard let self, let device = self.profile(id), let seam = self.mouse.activePortal?.seam else { return }
            let geometry = seam.remote
            self.sessions[id]?.connection.send(device.mouseMapping.command(epoch: epoch))
            self.sessions[id]?.connection.send("enter-abs \(epoch) 0 \(Int(position.x.rounded())) \(Int(position.y.rounded())) \(geometry.width) \(geometry.height) \(geometry.rotation)")
        }
        mouse.onRelease = { [weak self] id, epoch, reason in
            self?.stopKeyboardControl(id)
            self?.sessions[id]?.connection.send("release \(epoch)"); self?.notice = reason
        }
        mouse.onInput = { [weak self] id, frame in
            self?.sessions[id]?.connection.sendPointer(frame)
        }
        mouse.onShortcut = { [weak self] in self?.enterLast() }
        mouse.onChange = { [weak self] in
            guard let self else { return }
            self.activeDeviceID = self.mouse.activeDeviceID
            self.switching = self.mouse.mode == .entering
            self.permissionGranted = self.mouse.hasTap
            self.onStateChange?()
        }
    }
    func tick() {
        guard !stopped, !preview else { return }
        if mouse.hasTap && !AXIsProcessTrusted() { mouse.uninstallTap() }
        if !mouse.hasTap { mouse.installTap() }
        if permissionGranted != mouse.hasTap { permissionGranted = mouse.hasTap; onStateChange?() }
        if now - lastScan > 2, ADB.path != nil { lastScan = now; discovery.scan() }
        if !paused && !sleeping {
            for device in profiles {
                guard let session = sessions[device.id] else { continue }
                switch status(device.id).phase {
                case .ready:
                    if now - session.lastMessage > 2.2 { failed(device.id, "设备响应超时") }
                    else { session.connection.send("ping") }
                case .connecting:
                    if now - session.attemptAt > 18 { failed(device.id, "连接超时") }
                default: break
                }
            }
            reconcile()
        }
        tickKeyboards()
    }
    func discovered(_ values: [DeviceEndpoint]) {
        guard !stopped else { return }
        mirroring.reconcile(endpoints: values)
        if endpoints != values { endpoints = values }
        discoveryError = ""
        if firstImport, values.contains(where: \.usable) {
            for endpoint in values.filter(\.usable) { add(endpoint) }
            firstImport = false; save(); select(profiles.first?.id)
        }
        reconcile()
    }
    func setStatus(_ id: String, _ value: DeviceStatus) {
        if statuses[id] != value { statuses[id] = value; refreshPortals(); onStateChange?() }
    }
    func reconcile() {
        guard !stopped, !preview, !sleeping, !paused else { return }
        for device in profiles {
            let id = device.id
            if suspended.contains(id) { setStatus(id, DeviceStatus(phase: .paused)); continue }
            let previous = sessions[id]
            if let previous, previous.retry.isExhausted, !requested.contains(id) {
                setStatus(id, DeviceStatus(phase: .failed, transport: status(id).transport,
                    message: previous.failureMessage, retryStopped: true))
                continue
            }
            let known = endpoints.filter { $0.hardwareID == id }
            let usable = known.filter(\.usable).sorted { $0.usb && !$1.usb }
            let endpoint = usable.first { $0.serial == previous?.endpoint } ?? usable.first
            guard let endpoint else {
                if [.ready, .connecting].contains(status(id).phase) {
                    failed(id, "当前设备已断开")
                }
                if previous?.retry.isExhausted == true { continue }
                setStatus(id, DeviceStatus(phase: known.contains { $0.authorization == "unauthorized" } ? .unauthorized : .offline))
                continue
            }
            if let previous, previous.endpoint != endpoint.serial, [.ready, .connecting].contains(status(id).phase) {
                failed(id, "设备连接方式已变化")
                if previous.retry.isExhausted { continue }
                previous.attemptAt = -100
            }
            if [.ready, .connecting].contains(status(id).phase) { continue }
            guard device.autoConnect || requested.contains(id) || previous?.retry.isActive == true else {
                if status(id).phase != .failed { setStatus(id, DeviceStatus(phase: .paused)) }
                continue
            }
            let session = previous ?? DeviceSession()
            guard now - session.attemptAt > 3 else { continue }
            let manualRequest = requested.remove(id) != nil
            if manualRequest || !session.retry.isActive { session.retry.beginRound() }
            guard session.retry.admitAttempt() else { continue }
            session.automaticAttempt = !manualRequest
            sessions[id] = session
            session.endpoint = endpoint.serial; session.attemptAt = now
            session.connection.onEvent = { [weak self] event in self?.receive(id, event) }
            session.connection.onFailure = { [weak self] message in self?.failed(id, message) }
            Log.write("Connecting device: \(id), attempt=\(session.retry.attempts)/\(ConnectionRetryState.maximumAttempts), automatic=\(session.automaticAttempt), autoConnect=\(device.autoConnect)")
            setStatus(id, DeviceStatus(phase: .connecting, transport: endpoint.transport))
            session.connection.start(serial: endpoint.serial)
        }
    }
    func receive(_ id: String, _ event: [String: Any]) {
        guard !stopped, profile(id) != nil, let type = event["type"] as? String, let session = sessions[id] else { return }
        session.lastMessage = now
        switch type {
        case "ready":
            guard event["protocol"] as? Int == 4, event["pointerMode"] as? String == "absolute" else { failed(id, "控制程序版本不匹配"); return }
            receiveScreenGeometry(id, event)
            requested.remove(id)
            session.automaticAttempt = false
            session.retry.succeed(); session.lastFailure = ""
            let transport = endpoints.first { $0.serial == session.endpoint }?.transport ?? status(id).transport
            setStatus(id, DeviceStatus(phase: .ready, transport: transport))
            Log.write("Device ready: \(id), \(transport), \(event)")
        case "entered":
            guard mouse.accepts(event, from: id), mouse.mode == .entering else {
                // Do not release a newer visit to the same device for a stale ACK.
                if mouse.activeDeviceID != id, let epoch = event["epoch"] as? Int { session.connection.send("release \(epoch)") }
                return
            }
            mouse.didEnter(event, from: id); lastControlledID = id
            if mouse.mode == .remote, mouse.activeDeviceID == id { startKeyboardControl(id) }
            if !status(id).message.isEmpty {
                var current = status(id); current.message = ""; setStatus(id, current)
            }
            if event["reused"] as? Bool == true {
                Log.write("Reused device pointer: \(id), mouse=\(event["mouseId"] ?? "?"), generation=\(event["generation"] ?? "?"), entry=\(event["entryMs"] ?? "?")ms")
            }
            defaults.set(id, forKey: "lastControlledDevice")
        case "cursor": mouse.receiveCursor(event, from: id)
        case "heartbeat":
            receiveScreenGeometry(id, event)
            if let lease = mouse.lease, lease.deviceID == id {
                var dimensions = event; dimensions["epoch"] = lease.epoch
                mouse.receiveCursor(dimensions, from: id)
            }
        case "entryFailed":
            if mouse.accepts(event, from: id) {
                let message = event["message"] as? String ?? "设备定位失败"
                mouse.returnToMac(message)
                var current = status(id); current.message = message; setStatus(id, current)
                if let detail = event["detail"] as? String { Log.write("Input entry failed: \(id), \(detail)") }
            }
        case "pointer-action-error":
            guard mouse.accepts(event, from: id) else { return }
            notice = "点击或滚动操作未能执行"
            Log.write("Pointer action failed: \(id), \(event)")
        case "error": failed(id, event["message"] as? String ?? "设备控制失败")
        default: break
        }
    }
    func failed(_ id: String, _ message: String) {
        guard !stopped, profile(id) != nil else { return }
        requested.remove(id)
        if mouse.activeDeviceID == id { mouse.returnToMac(message) }
        sessions[id]?.connection.stop(); sessions[id]?.attemptAt = now
        sessions[id]?.automaticAttempt = false
        sessions[id]?.lastFailure = message
        sessions[id]?.retry.recordFailure()
        let transport = status(id).transport
        let session = sessions[id]
        setStatus(id, DeviceStatus(phase: .failed, transport: transport,
            message: session?.failureMessage ?? message, retryStopped: session?.retry.isExhausted ?? false))
        Log.write("Device failed: \(id), attempt=\(session?.retry.attempts ?? 0)/\(ConnectionRetryState.maximumAttempts), retryStopped=\(session?.retry.isExhausted ?? false), \(message)")
    }
    func willSleep() {
        mirroring.stopAll()
        sleeping = true; mouse.returnToMac("Mac 即将休眠")
        for id in Array(keyboardSessions.keys) { closeKeyboardConnection(id) }
        for session in sessions.values {
            session.connection.stop(); session.retry.cancel(); session.automaticAttempt = false
        }
        for device in profiles { setStatus(device.id, DeviceStatus(phase: .offline)) }
        refreshPortals()
    }
    func didWake() {
        sleeping = false; for session in sessions.values { session.attemptAt = -100 }
        discovery.scan(); reconcile()
    }
}
