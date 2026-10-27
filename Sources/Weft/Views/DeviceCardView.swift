import SwiftUI
import WeftCore

struct DeviceCardView: View {
    @ObservedObject var store: DeviceStore
    let device: DeviceProfile

    private var selected: Bool { store.selectedID == device.id }
    private var status: DeviceStatus { store.status(device.id) }
    private var connected: Bool { status.phase == .ready || status.phase == .connecting }

    var body: some View {
        VStack(spacing: 0) {
            header
            if selected {
                Divider().padding(.horizontal, 14)
                DeviceDetailView(store: store, device: device)
            }
            DeviceMirroringStatusView(store: store, configuration: store.scrcpy, manager: store.mirroring,
                                      deviceID: device.id, expanded: selected)
        }
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(selected ? WeftStyle.accent.opacity(0.65) : WeftStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(device.name)
        .accessibilityIdentifier("device-card.\(device.id)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: toggleSelection) {
                HStack(spacing: 14) {
                    DeviceGlyph(kind: device.kind, size: 23)
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 6) {
                            if !status.transport.isEmpty {
                                Text("\(status.transport) 连接")
                                Text("·")
                            }
                            StatusDot(phase: status.phase).accessibilityHidden(true)
                            Text(status.phase == .ready ? (store.activeDeviceID == device.id ? "当前控制" : "已连接") : status.label)
                        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(selected ? "收起\(device.name)的设置" : "展开\(device.name)的设置")
            .accessibilityLabel("\(device.name)，\(status.label)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("device-card.select.\(device.id)")
            .contextMenu {
                Button(connected ? "断开连接" : "连接设备", action: toggleConnection).disabled(store.paused)
                Divider()
                Button(store.connectedCount > 0 ? "断开所有设备连接" : "连接所有设备") {
                    if store.connectedCount > 0 { store.disconnectAll() } else { store.connectAll() }
                }
            }

            DeviceMirroringButton(store: store, configuration: store.scrcpy, manager: store.mirroring, deviceID: device.id)

            if selected {
                Button(connected ? "断开连接" : "连接设备", action: toggleConnection)
                    .buttonStyle(WeftButtonStyle(height: 30, fontSize: 12))
                    .disabled(store.paused)
                    .accessibilityLabel("\(connected ? "断开连接" : "连接设备")：\(device.name)")
                    .accessibilityIdentifier("device-card.connection.\(device.id)")

                Button(role: .destructive) { store.remove(device.id) } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red).frame(width: 8)
                }
                .buttonStyle(WeftButtonStyle(height: 30))
                .help("永久删除\(device.name)及其设置")
                .accessibilityLabel("删除\(device.name)")
                .accessibilityHint("永久删除设备及其设置，重新使用时需要手动添加")
                .accessibilityIdentifier("device-card.remove.\(device.id)")
            }

            Button(action: toggleSelection) {
                Image(systemName: selected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(selected ? "收起" : "展开")\(device.name)设置")
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
    }

    private func toggleSelection() { store.select(selected ? nil : device.id) }

    private func toggleConnection() {
        if connected { store.disconnect(device.id) } else { store.connect(device.id) }
    }
}
