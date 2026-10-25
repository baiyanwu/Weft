import SwiftUI
import WeftCore

struct DeviceListView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(spacing: 10) {
            macRow
            ForEach(store.profiles) { device in
                DeviceCardView(store: store, device: device)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设备列表")
    }

    private var macRow: some View {
        HStack(spacing: 14) {
            Button { store.select(nil) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer").font(.system(size: 28)).frame(width: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mac · 本机").font(.headline)
                        Text(store.activeDeviceID == nil ? "当前控制本机" : "本机")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看本机与全部设备")
            .accessibilityIdentifier("device-list.mac")
            .contextMenu { allConnectionsAction }

            Button {
                store.showingAddDevice = true
                store.discovery.scan()
            } label: {
                Label("添加设备", systemImage: "plus")
                    .frame(width: 132)
            }
            .buttonStyle(WeftButtonStyle(prominent: true, height: 36))
            .accessibilityIdentifier("device-list.add")
        }
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 10))
    }

    private var allConnectionsAction: some View {
        Button(store.connectedCount > 0 ? "断开所有设备连接" : "连接所有设备") {
            if store.connectedCount > 0 { store.disconnectAll() } else { store.connectAll() }
        }
        .disabled(store.profiles.isEmpty)
    }
}
