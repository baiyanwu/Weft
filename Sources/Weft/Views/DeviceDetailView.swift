import SwiftUI
import WeftCore

struct DeviceDetailView: View {
    @ObservedObject var store: DeviceStore
    let device: DeviceProfile
    private var connected: Bool { [.ready, .connecting].contains(store.status(device.id).phase) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Divider()
            HStack(alignment: .top, spacing: 15) {
                DeviceGlyph(kind: device.kind, size: 31).padding(.top, 2)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text(device.name).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                        StatusDot(phase: store.status(device.id).phase)
                        Text(store.status(device.id).label).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("以下设置仅对这台设备生效").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(connected ? "断开连接" : "连接设备") {
                    if connected { store.disconnect(device.id) } else { store.connect(device.id) }
                }.disabled(store.paused).buttonStyle(WeftButtonStyle())
            }.padding(.horizontal, 6)
            HStack(alignment: .top, spacing: 30) {
                VStack(spacing: 9) {
                    Divider()
                    setting("Mac 出入口屏幕") { ScreenSelectionView(store: store, device: device).frame(width: 180) }
                    Divider()
                    setting("鼠标速度") {
                        SpeedPicker(selection: Binding(get: { device.speed }, set: { value in store.update(device.id) { $0.speed = value } }))
                            .frame(width: 204)
                    }
                }.frame(maxWidth: .infinity)
                VStack(spacing: 9) {
                    Divider()
                    setting("设备位置") {
                        DirectionSelectionView(store: store, device: device).frame(width: 180)
                    }
                    Divider()
                    PreferenceRow(title: "自动连接", subtitle: "设备可用时自动连接") {
                        Toggle("自动连接", isOn: Binding(get: { device.autoConnect }, set: { value in store.update(device.id) { $0.autoConnect = value } }))
                            .labelsHidden().toggleStyle(.switch)
                    }.frame(height: 38)
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 6)
            if !store.status(device.id).message.isEmpty {
                Text(store.status(device.id).message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            Surface(highlighted: true) {
                HStack(spacing: 14) {
                    Image(systemName: "display.2").font(.system(size: 25))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动跨屏").fontWeight(.semibold)
                        Text("仅对\(device.name)生效；关闭后仍可通过菜单或快捷键进入")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("自动跨屏", isOn: Binding(get: { device.autoCross }, set: { value in
                        store.update(device.id) { $0.autoCross = value }
                    })).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).fontWeight(.medium).fixedSize()
            Spacer(minLength: 0)
            content()
        }.frame(height: 34)
    }
}

private struct SpeedPicker: View {
    @Binding var selection: Double
    var body: some View {
        HStack(spacing: 0) {
            ForEach([0.7, 1.0, 1.4], id: \.self) { speed in
                Button { selection = speed } label: {
                    Text(speed == 1 ? "1×" : String(format: "%.1f×", speed))
                        .font(.system(size: 12, weight: selection == speed ? .semibold : .regular))
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .foregroundStyle(selection == speed ? Color.primary : .secondary)
                        .background(selection == speed ? WeftStyle.accent.opacity(0.19) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selection == speed ? WeftStyle.accent : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(speed == 1 ? "标准速度 1 倍" : String(format: "鼠标速度 %.1f 倍", speed))
                    .accessibilityAddTraits(selection == speed ? .isSelected : [])
            }
        }.background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WeftStyle.border, lineWidth: 1))
            .accessibilityElement(children: .contain).accessibilityLabel("鼠标速度")
    }
}
