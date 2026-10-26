import Foundation
import WeftCore

enum KeyboardPhase: Equatable { case idle, connecting, initializing, waitingForKeys, active, failed }

struct KeyboardStatus: Equatable {
    var phase: KeyboardPhase = .idle
    var message = ""
    var label: String {
        switch phase {
        case .idle: return "进入设备后启用键盘"
        case .connecting: return "键盘正在连接，鼠标可继续使用"
        case .initializing: return "键盘正在初始化，鼠标可继续使用"
        case .waitingForKeys: return "松开按键后启用键盘"
        case .active: return "键盘已共享"
        case .failed: return message
        }
    }
}

/// Separate process, connection, timeout and visit counter from DeviceSession's mouse.
final class KeyboardSession {
    let connection: AgentTransport
    var serial = ""
    var transportStarted = false
    var agentReady = false
    var deviceReady = false
    var enterSent = false
    var epoch = 0
    var controlEpoch: Int?
    var startedAt = 0.0
    var lastMessage = 0.0
    var mapping = KeyboardMapping()

    init(connection: AgentTransport = AgentConnection(role: .keyboard)) { self.connection = connection }
}
