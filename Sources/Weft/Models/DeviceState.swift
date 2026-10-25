import AppKit
import WeftCore

struct DeviceEndpoint: Identifiable, Equatable {
    var id: String { serial }
    let serial: String
    let hardwareID: String
    let model: String
    let kind: DeviceKind
    let usb: Bool
    let authorization: String
    var transport: String { usb ? "USB" : "Wi-Fi" }
    var usable: Bool { authorization == "device" }
}
enum ConnectionPhase: String { case offline, unauthorized, connecting, ready, paused, failed }
struct DeviceStatus: Equatable {
    var phase: ConnectionPhase = .offline
    var transport = ""
    var message = ""
    var retryStopped = false
    var label: String {
        switch phase {
        case .offline: return "离线"
        case .unauthorized: return "等待调试授权"
        case .connecting: return "正在连接…"
        case .ready: return "\(transport) · 已连接"
        case .paused: return "已暂停"
        case .failed: return retryStopped ? "已停止重连" : "连接失败"
        }
    }
}
struct MacScreen: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let bounds: CGRect
    var sizeMM: CGSize = .zero
    var estimatedSize = false
    var layoutSize: CGSize { sizeMM.width > 0 && sizeMM.height > 0 ? sizeMM : CGSize(width: bounds.width * 25.4 / 72, height: bounds.height * 25.4 / 72) }
}
struct ScreenPlacement: Identifiable, Equatable {
    var id: String { deviceID }
    let deviceID: String
    let displayID: UInt32
    let seam: ScreenSeam
}
enum SettingsSection { case devices, general, help }
final class DeviceSession {
    let connection: AgentTransport
    var endpoint = ""
    var lastMessage = 0.0
    var attemptAt = -100.0
    var automaticAttempt = false
    var retry = ConnectionRetryState()
    var lastFailure = ""
    var failureMessage: String {
        guard retry.isExhausted else { return lastFailure }
        return "连续连接失败 \(ConnectionRetryState.maximumAttempts) 次，已停止重连。请点击“连接设备”重试。\n原因：\(lastFailure)"
    }
    init(connection: AgentTransport = AgentConnection()) { self.connection = connection }
}
