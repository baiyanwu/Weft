import SwiftUI
import WeftCore

struct SettingsView: View {
    @ObservedObject var store: DeviceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(store: store).frame(width: 235)
                Divider().overlay(WeftStyle.border)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !store.permissionGranted {
                            HStack(spacing: 10) {
                                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                                Text("允许辅助功能后，即可在设备间切换鼠标。").font(.callout)
                                Spacer()
                                Button("前往授权") { store.requestPermission() }.buttonStyle(WeftButtonStyle())
                            }.padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        switch store.section {
                        case .devices: devicesContent
                        case .general: GeneralSettingsView(store: store)
                        case .help: HelpView(store: store)
                        }
                    }.padding(24)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.opacity(0.25))
            }
            Divider()
            HStack(spacing: 9) {
                Image(systemName: "checkmark"); Text("更改自动保存")
                Spacer()
                if store.paused { Text("全部连接已暂停").foregroundStyle(.orange) }
                Text("仅共享鼠标")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).frame(height: 38)
        }
        .background(.regularMaterial).tint(WeftStyle.accent)
        .frame(minWidth: 960, minHeight: 700)
        .sheet(isPresented: $store.showingAddDevice) { AddDeviceView(store: store) }
    }

    private var devicesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("设备与布局").font(.system(size: 27, weight: .bold))
                    Text("\(store.connectedCount) 台设备已连接 · \(store.switching ? "正在切换至" : "当前控制") \(store.controlName)")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("一次控制一台设备")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WeftStyle.border, lineWidth: 1))
            }
            if store.paused {
                HStack { Text("所有连接已暂停，布局与设置已保留。"); Spacer(); Button("恢复全部") { store.togglePause() }.buttonStyle(WeftButtonStyle()) }
                    .font(.callout).padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            LayoutCanvasView(store: store)
            if let device = store.selected { DeviceDetailView(store: store, device: device).id(device.id) }
            else {
                HStack(spacing: 15) {
                    Image(systemName: "desktopcomputer").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mac · 本机").font(.headline)
                        Text("选择左侧设备，设置跨屏位置与鼠标速度。").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("添加设备") { store.showingAddDevice = true }.buttonStyle(WeftButtonStyle())
                }.frame(maxWidth: .infinity, minHeight: 85).padding(.horizontal, 8)
            }
        }
    }
}
