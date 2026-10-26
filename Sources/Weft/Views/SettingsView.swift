import SwiftUI
import WeftCore

struct SettingsView: View {
    @ObservedObject var store: DeviceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(store: store).frame(width: 235)
                Divider().overlay(WeftStyle.border)
                GeometryReader { geometry in
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
                            case .devices: devicesContent(viewportHeight: geometry.size.height)
                            case .mouseButtons: MouseButtonMappingView(store: store)
                            case .general: GeneralSettingsView(store: store)
                            case .help: HelpView(store: store)
                            }
                        }.padding(24)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.opacity(0.25))
            }
        }
        .background(.regularMaterial).tint(WeftStyle.accent)
        .frame(minWidth: 960, minHeight: 700)
        .sheet(isPresented: $store.showingAddDevice) { AddDeviceView(store: store) }
    }

    private func devicesContent(viewportHeight: CGFloat) -> some View {
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
            LayoutCanvasView(store: store, boardHeight: layoutBoardHeight(in: viewportHeight))
            DeviceListView(store: store)
        }
    }

    private func layoutBoardHeight(in viewportHeight: CGFloat) -> CGFloat {
        // Reserve room for two device cards and the selected card's inline settings.
        let listHeight = 58 + CGFloat(min(store.profiles.count, 2)) * 70 + (store.selected == nil ? 0 : 150)
        let pageChrome: CGFloat = 48 + 58 + 28 + 104
        let noticeHeight: CGFloat = (store.permissionGranted ? 0 : 60) + (store.paused ? 60 : 0)
        return min(280, max(180, viewportHeight - listHeight - pageChrome - noticeHeight))
    }
}
