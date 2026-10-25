import SwiftUI
import WeftCore

struct SidebarView: View {
    @ObservedObject var store: DeviceStore
    private var hasConnections: Bool { store.connectedCount > 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) { BrandMark(size: 44); Text("weft").font(.system(size: 25, weight: .bold)) }
                .padding(.horizontal, 24).padding(.vertical, 21)
            Divider().padding(.horizontal, 20)
            Button { store.select(nil) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer").font(.system(size: 28)).frame(width: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mac").fontWeight(.medium)
                        Text(store.activeDeviceID == nil ? "本机 · 当前控制" : "本机").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 18).frame(height: 68).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 6)
            Divider().padding(.horizontal, 20)
            HStack(spacing: 6) {
                Text("我的设备").fontWeight(.semibold)
                Text("\(store.profiles.count)").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 3)
                Button(hasConnections ? "断开连接" : "全部连接") {
                    if hasConnections { store.disconnectAll() } else { store.connectAll() }
                }
                    .buttonStyle(WeftButtonStyle(height: 26, fontSize: 11))
                    .disabled(store.profiles.isEmpty)
                    .help(hasConnections ? "断开所有设备连接" : "尝试连接所有已添加设备")
                    .accessibilityLabel(hasConnections ? "断开所有设备连接" : "尝试连接所有已添加设备")
            }.padding(.horizontal, 20).padding(.top, 19).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.profiles) { device in deviceRow(device) }
                }.padding(.horizontal, 8)
            }.frame(maxHeight: min(CGFloat(store.profiles.count) * 70 + 4, 360))
            Button { store.showingAddDevice = true; store.discovery.scan() } label: {
                Label("添加设备", systemImage: "plus").frame(maxWidth: .infinity).frame(height: 20)
            }.buttonStyle(WeftButtonStyle(prominent: true)).padding(.horizontal, 20).padding(.top, 16)
            Spacer(minLength: 24)
            Divider().padding(.horizontal, 20)
            navigation("通用设置", icon: "gearshape", section: .general).padding(.top, 8)
            navigation("帮助与诊断", icon: "book", section: .help).padding(.bottom, 15)
        }.background(.ultraThinMaterial)
    }

    private func deviceRow(_ device: DeviceProfile) -> some View {
        let selected = store.selectedID == device.id && store.section == .devices
        let phase = store.status(device.id).phase
        return HStack(spacing: 8) {
            Button { store.select(device.id) } label: {
                HStack(spacing: 14) {
                    DeviceGlyph(kind: device.kind, size: 27)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).fontWeight(selected ? .semibold : .medium).lineLimit(1)
                        Text(store.status(device.id).label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    StatusDot(phase: phase)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(role: .destructive) { store.remove(device.id) } label: {
                Image(systemName: "trash").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red).frame(width: 28, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help("永久删除\(device.name)及其设置")
                .accessibilityLabel("删除\(device.name)")
                .accessibilityHint("永久删除设备及其设置，重新使用时需要手动添加")
        }.padding(.leading, 17).padding(.trailing, 13).frame(height: 64)
            .background(selected ? WeftStyle.selection : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .leading) { if selected { Rectangle().fill(WeftStyle.accent).frame(width: 3) } }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func navigation(_ title: String, icon: String, section: SettingsSection) -> some View {
        Button { store.section = section } label: {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.system(size: 21)).frame(width: 26)
                Text(title); Spacer(); Image(systemName: "chevron.right").font(.caption)
            }.padding(.horizontal, 16).frame(height: 46).contentShape(Rectangle())
                .foregroundStyle(store.section == section ? WeftStyle.accentText : Color.primary)
                .background(store.section == section ? WeftStyle.selection : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .leading) { if store.section == section { Rectangle().fill(WeftStyle.accent).frame(width: 3) } }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }
}
