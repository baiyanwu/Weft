import Foundation
import WeftCore

extension DeviceStore {
    func keyboardStatus(_ id: String) -> KeyboardStatus { keyboardStatuses[id] ?? KeyboardStatus() }

    func startKeyboardControl(_ id: String) {
        guard !stopped, !preview, let device = profile(id), device.keyboardMapping.enabled,
              mouse.activeDeviceID == id, mouse.mode == .remote, let controlEpoch = mouse.lease?.epoch,
              let serial = sessions[id]?.endpoint, !serial.isEmpty else { return }
        let session = keyboardSessions[id] ?? KeyboardSession()
        keyboardSessions[id] = session
        if session.serial != serial {
            session.connection.stop(); session.transportStarted = false; session.agentReady = false
        }
        session.serial = serial; session.controlEpoch = controlEpoch; session.mapping = device.keyboardMapping
        session.epoch += 1; session.deviceReady = false; session.enterSent = false; session.startedAt = now
        keyboardStatuses[id] = KeyboardStatus(phase: session.agentReady ? .initializing : .connecting)
        if !session.transportStarted {
            session.transportStarted = true; session.lastMessage = now
            session.connection.onEvent = { [weak self, weak session] event in
                guard let self, let session, self.keyboardSessions[id] === session else { return }
                self.receiveKeyboard(id, event)
            }
            session.connection.onFailure = { [weak self, weak session] message in
                guard let self, let session, self.keyboardSessions[id] === session else { return }
                self.keyboardFailed(id, message: message, disconnect: true)
            }
            session.connection.start(serial: serial)
        }
        advanceKeyboard(id, session)
    }

    func stopKeyboardControl(_ id: String) {
        guard let session = keyboardSessions[id] else { return }
        if mouse.activeDeviceID == id { mouse.keyboard.end(); mouse.cancelKeyboardPointerActions() }
        session.controlEpoch = nil; session.enterSent = false; session.deviceReady = false
        if session.agentReady { session.connection.send("release \(session.epoch)") }
        else { session.connection.stop(); session.transportStarted = false }
        if keyboardStatus(id).phase != .failed { keyboardStatuses[id] = KeyboardStatus() }
    }

    func closeKeyboardConnection(_ id: String) {
        stopKeyboardControl(id)
        guard let session = keyboardSessions.removeValue(forKey: id) else { return }
        session.connection.onEvent = nil; session.connection.onFailure = nil; session.connection.stop()
        keyboardStatuses.removeValue(forKey: id)
    }

    func retryKeyboard(_ id: String) {
        closeKeyboardConnection(id)
        startKeyboardControl(id)
    }

    func receiveKeyboard(_ id: String, _ event: [String: Any]) {
        guard !stopped, profile(id) != nil, let session = keyboardSessions[id],
              let type = event["type"] as? String else { return }
        session.lastMessage = now
        switch type {
        case "ready":
            guard event["protocol"] as? Int == 1 else {
                keyboardFailed(id, message: "键盘控制程序版本不匹配，鼠标可继续使用", disconnect: true); return
            }
            session.agentReady = true; advanceKeyboard(id, session)
        case "entered":
            guard event["epoch"] as? Int == session.epoch, session.controlEpoch != nil else { return }
            session.deviceReady = true; advanceKeyboard(id, session)
        case "action-error":
            guard event["epoch"] as? Int == session.epoch, session.controlEpoch != nil else { return }
            let action = (event["action"] as? String).flatMap(KeyboardMappingAction.init(rawValue:))
            notice = "未能执行\(action.map { "「\($0.title)」" } ?? "Android 操作")"
            Log.write("Keyboard action failed: \(id), \(event)")
        case "keyboard-error", "error":
            if let epoch = event["epoch"] as? Int, epoch != 0 && epoch != session.epoch { return }
            if let detail = event["detail"] as? String { Log.write("Keyboard failed: \(id), \(detail)") }
            keyboardFailed(id, message: event["message"] as? String ?? "键盘不可用，鼠标可继续使用",
                           disconnect: !session.agentReady)
        default: break
        }
    }

    func keyboardFailed(_ id: String, message: String, disconnect: Bool) {
        guard !stopped, profile(id) != nil, let session = keyboardSessions[id] else { return }
        if mouse.activeDeviceID == id { mouse.keyboard.end(); mouse.cancelKeyboardPointerActions() }
        session.controlEpoch = nil; session.deviceReady = false; session.enterSent = false
        if disconnect {
            session.connection.stop(); session.transportStarted = false; session.agentReady = false
        } else if session.agentReady { session.connection.send("release \(session.epoch)") }
        keyboardStatuses[id] = KeyboardStatus(phase: .failed, message: message)
        Log.write("Keyboard unavailable; mouse unchanged: \(id), \(message)")
    }

    func tickKeyboards() {
        guard !stopped, !preview else { return }
        for (id, session) in keyboardSessions where session.transportStarted {
            if session.agentReady {
                if now - session.lastMessage > 3 {
                    keyboardFailed(id, message: "键盘响应超时，鼠标可继续使用", disconnect: true); continue
                }
                session.connection.send("ping")
            } else if now - session.startedAt > 14 {
                keyboardFailed(id, message: "键盘连接超时，鼠标可继续使用", disconnect: true); continue
            }
            if session.enterSent && !session.deviceReady && now - session.startedAt > 4 {
                keyboardFailed(id, message: "键盘初始化超时，鼠标可继续使用", disconnect: true); continue
            }
            advanceKeyboard(id, session)
        }
    }

    private func advanceKeyboard(_ id: String, _ session: KeyboardSession) {
        guard session.agentReady, let controlEpoch = session.controlEpoch,
              mouse.activeDeviceID == id, mouse.mode == .remote, mouse.lease?.epoch == controlEpoch else { return }
        guard mouse.keyboard.canBegin else {
            if !mouse.keyboard.sharing { keyboardStatuses[id] = KeyboardStatus(phase: .waitingForKeys) }
            return
        }
        if !session.enterSent {
            session.enterSent = true; session.startedAt = now
            keyboardStatuses[id] = KeyboardStatus(phase: .initializing)
            session.connection.send("enter \(session.epoch)")
        } else if session.deviceReady && !mouse.keyboard.sharing {
            mouse.keyboard.begin(mapping: session.mapping, epoch: session.epoch)
            keyboardStatuses[id] = KeyboardStatus(phase: .active)
        }
    }
}
