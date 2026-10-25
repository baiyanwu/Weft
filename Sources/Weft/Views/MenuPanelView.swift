import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var store: DeviceStore
    let openSettings: () -> Void
    let quit: () -> Void
    private var deviceListHeight: CGFloat {
        min(store.profiles.reduce(CGFloat(0)) { $0 + (store.status($1.id).phase == .ready ? 38 : 30) }
            + CGFloat(max(0, store.profiles.count - 1)), 200)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                BrandMark(size: 27); Text("weft").font(.system(size: 19, weight: .bold))
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    StatusDot(phase: store.connectedCount > 0 ? .ready : .offline)
                    Text("\(store.connectedCount) 台已连接").font(.system(size: 11))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: store.activeDeviceID == nil ? "desktopcomputer" : "cursorarrow").font(.system(size: 16))
                    Text("\(store.switching ? "正在切换至" : "当前控制")：\(store.controlName)")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .background(WeftStyle.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                Text("⌃⌥M 切换 Mac/上次设备 · 左⌥/Esc 返回 Mac")
                    .font(.system(size: 10.5)).foregroundStyle(WeftStyle.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.95).allowsTightening(true)
                    .padding(.horizontal, 2).padding(.vertical, 4)
                    .accessibilityLabel("Control、Option 和 M 切换 Mac 与上次设备；左 Option 或 Escape 返回 Mac")
            }
            if !store.permissionGranted {
                HStack(spacing: 7) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    Text("需要辅助功能权限").font(.system(size: 11))
                    Spacer(minLength: 0)
                    Button("前往授权") { store.requestPermission() }
                        .buttonStyle(WeftButtonStyle(height: 26, fontSize: 11)).fixedSize()
                }.padding(8).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("切换控制").font(.system(size: 10)).foregroundStyle(WeftStyle.secondaryText)
                VStack(spacing: 0) {
                    controlRow("Mac", icon: "desktopcomputer", subtitle: nil, current: store.activeDeviceID == nil, available: true) { store.returnToMac() }
                    if !store.profiles.isEmpty { Divider().padding(.leading, 30) }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.profiles) { device in
                                controlRow(device.name, icon: device.kind == .tablet ? "ipad" : "iphone", subtitle: store.status(device.id).phase == .ready ? store.status(device.id).transport : nil,
                                    current: store.activeDeviceID == device.id, available: store.status(device.id).phase == .ready,
                                    unavailableLabel: store.status(device.id).label) { store.enterDevice(device.id) }
                                if device.id != store.profiles.last?.id { Divider().padding(.leading, 30) }
                            }
                        }
                    }.frame(height: deviceListHeight)
                }
            }
            Divider()
            VStack(spacing: 0) {
                action(store.paused ? "恢复全部" : "暂停全部", icon: store.paused ? "play.fill" : "pause.fill") { store.togglePause() }
                action("设置", icon: "gearshape", shortcut: "⌘,") { openSettings() }
                action("退出", icon: "rectangle.portrait.and.arrow.right", shortcut: "⌘Q") { quit() }
            }
        }.padding(12).frame(width: 280).font(.system(size: 12)).tint(WeftStyle.accent)
            .background { MenuPanelBackdrop() }
    }
    private func controlRow(_ name: String, icon: String, subtitle: String?, current: Bool, available: Bool, unavailableLabel: String = "离线", perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 21)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(WeftStyle.secondaryText) }
                }
                Spacer(minLength: 4)
                if current {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(WeftStyle.accentText)
                    Text("当前").font(.system(size: 11)).foregroundStyle(WeftStyle.accentText)
                } else {
                    Text(available ? "进入" : unavailableLabel).font(.system(size: 11))
                        .foregroundStyle(available ? WeftStyle.accentText : WeftStyle.secondaryText)
                }
            }.frame(height: subtitle == nil ? 30 : 38).contentShape(Rectangle())
                .foregroundStyle(current || available ? Color.primary : WeftStyle.secondaryText)
        }.buttonStyle(.plain).disabled(!available)
    }
    private func action(_ title: String, icon: String, shortcut: String? = nil, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 9) {
                Image(systemName: icon).resizable().scaledToFit()
                    .frame(width: 16, height: 16).frame(width: 21)
                Text(title); Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 10)).foregroundStyle(WeftStyle.secondaryText) }
            }.frame(height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
