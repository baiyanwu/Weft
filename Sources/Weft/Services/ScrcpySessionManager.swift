import Foundation
import Combine

enum MirroringState: Equatable {
    case idle, running, stopping, failed(String)

    var isActive: Bool { self == .running || self == .stopping }
    var message: String {
        switch self {
        case .idle: return "在独立窗口中显示与操作设备"
        case .running: return "投屏已启动 · 画面在独立窗口中显示"
        case .stopping: return "正在停止投屏…"
        case .failed(let message): return message
        }
    }
}

final class ScrcpySessionManager: ObservableObject {
    @Published private(set) var states: [String: MirroringState] = [:]
    private struct Session {
        let token: UUID
        let serial: String
        let process: ScrcpyProcessRunning
    }
    private var sessions: [String: Session] = [:]
    private let makeProcess: () -> ScrcpyProcessRunning

    init(makeProcess: @escaping () -> ScrcpyProcessRunning = { ScrcpyProcess() }) {
        self.makeProcess = makeProcess
    }
    deinit { for session in sessions.values { session.process.stop() } }

    func state(_ id: String) -> MirroringState { states[id] ?? .idle }

    func start(id: String, serial: String, name: String, executable: String, adb: String) {
        guard sessions[id] == nil else { return }
        let process = makeProcess(), token = UUID()
        let request = ScrcpyLaunchRequest(executable: executable, adb: adb, serial: serial, name: name)
        sessions[id] = Session(token: token, serial: serial, process: process)
        states[id] = .running
        do {
            try process.start(request) { [weak self] code, output in
                DispatchQueue.main.async { self?.finished(id: id, token: token, code: code, output: output) }
            }
            Log.write("scrcpy started for device: \(id)")
        } catch {
            sessions.removeValue(forKey: id)
            states[id] = .failed("投屏启动失败：\(error.localizedDescription)")
        }
    }

    func fail(_ id: String, message: String) {
        guard sessions[id] == nil else { return }
        states[id] = .failed(message)
    }

    func stop(_ id: String) {
        guard let session = sessions[id], state(id) != .stopping else { return }
        states[id] = .stopping
        session.process.stop()
    }

    func forget(_ id: String) {
        let session = sessions.removeValue(forKey: id)
        states.removeValue(forKey: id)
        session?.process.stop()
    }

    func stopAll() { for id in Array(sessions.keys) { stop(id) } }

    func reconcile(endpoints: [DeviceEndpoint]) {
        for (id, session) in sessions {
            if !endpoints.contains(where: { $0.hardwareID == id && $0.serial == session.serial && $0.usable }) {
                stop(id)
            }
        }
    }

    private func finished(id: String, token: UUID, code: Int32, output: String) {
        guard sessions[id]?.token == token else { return }
        let stopped = state(id) == .stopping
        sessions.removeValue(forKey: id)
        if stopped || code == 0 {
            states[id] = .idle
        } else {
            let lines = output.split(whereSeparator: \.isNewline)
            let detail = lines.last(where: { $0.contains("ERROR:") }) ?? lines.last
            let message = detail.map { String($0.suffix(300)) } ?? "scrcpy 已退出（代码 \(code)），请检查设备连接和 scrcpy 安装。"
            states[id] = .failed("投屏未能继续：\(message)")
        }
        Log.write("scrcpy exited for device: \(id), code=\(code), stopped=\(stopped)")
    }
}
