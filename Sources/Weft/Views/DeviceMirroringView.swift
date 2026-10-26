import SwiftUI

struct DeviceMirroringButton: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var configuration: ScrcpyConfiguration
    @ObservedObject var manager: ScrcpySessionManager
    let deviceID: String

    private var state: MirroringState { manager.state(deviceID) }
    private var needsConfiguration: Bool { configuration.selected == nil && !configuration.scanning }
    private var title: String {
        if state == .stopping { return "正在停止…" }
        if state.isActive { return "停止投屏" }
        return needsConfiguration ? "配置投屏" : "开始投屏"
    }

    var body: some View {
        Button {
            if state.isActive { manager.stop(deviceID) }
            else if needsConfiguration { store.section = .general }
            else { store.startMirroring(deviceID) }
        } label: {
            HStack(spacing: 5) {
                if state == .stopping { ProgressView().controlSize(.mini) }
                else { Image(systemName: state.isActive ? "stop.circle" : "rectangle.on.rectangle") }
                Text(title)
            }
        }
        .buttonStyle(WeftButtonStyle(prominent: !state.isActive, height: 30, fontSize: 12))
        .fixedSize()
        .disabled(state == .stopping || (!state.isActive && (configuration.scanning || (!needsConfiguration && store.mirroringEndpoint(deviceID) == nil))))
        .help(state.isActive ? "关闭此投屏窗口，鼠标跨屏继续按当前设置运行" : needsConfiguration ? "前往通用设置，查找或选择本机的 scrcpy" : store.mirroringEndpoint(deviceID) == nil ? "请先连接设备并允许调试" : "使用本机 scrcpy 打开独立投屏窗口")
        .accessibilityLabel("\(title)：\(store.profile(deviceID)?.name ?? "设备")")
        .accessibilityIdentifier("device-card.mirroring.\(deviceID)")
    }
}

struct DeviceMirroringStatusView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var configuration: ScrcpyConfiguration
    @ObservedObject var manager: ScrcpySessionManager
    let deviceID: String
    var expanded: Bool

    private var state: MirroringState { manager.state(deviceID) }
    private var failed: Bool { if case .failed = state { return true }; return false }

    var body: some View {
        if expanded || failed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: failed ? "exclamationmark.triangle" : "rectangle.on.rectangle")
                Text(message).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Spacer(minLength: 0)
                if configuration.selected == nil && !configuration.scanning {
                    Button("前往设置") { store.section = .general }.buttonStyle(.link).fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(failed ? Color.orange : state == .running ? WeftStyle.accentText : .secondary)
            .padding(.horizontal, 16).padding(.bottom, 12)
            .accessibilityIdentifier("device-card.mirroring-status.\(deviceID)")
        }
    }

    private var message: String {
        if state == .idle {
            if configuration.scanning { return "正在查找本机 scrcpy…" }
            if configuration.selected == nil { return "配置本机 scrcpy 后，即可在独立窗口中投屏。" }
            return "使用本机 scrcpy 投屏，鼠标跨屏按当前设置运行。"
        }
        return state.message
    }
}
