import SwiftUI
import WeftCore

struct DeviceDetailView: View {
    @ObservedObject var store: DeviceStore
    let device: DeviceProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 10) {
                    setting("Mac 出入口屏幕") { ScreenSelectionView(store: store, device: device).frame(width: 178) }
                    Divider()
                    PreferenceRow(title: "自动连接", subtitle: "设备可用时自动连接") {
                        Toggle("自动连接", isOn: Binding(get: { device.autoConnect }, set: { value in store.update(device.id) { $0.autoConnect = value } }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.frame(height: 38)
                }.frame(maxWidth: .infinity)

                Rectangle().fill(WeftStyle.border).frame(width: 1)

                VStack(spacing: 10) {
                    setting("鼠标速度") {
                        SpeedPicker(selection: Binding(get: { device.speed }, set: { value in store.update(device.id) { $0.speed = value } }))
                            .frame(width: 190)
                    }
                    Divider()
                    PreferenceRow(title: "自动跨屏", subtitle: "鼠标移至屏幕边缘时切换") {
                        Toggle("自动跨屏", isOn: Binding(get: { device.autoCross }, set: { value in
                            store.update(device.id) { $0.autoCross = value }
                        }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityHint("关闭后仍可通过菜单或快捷键进入")
                    }.frame(height: 38)
                        .help("关闭后仍可通过菜单或快捷键进入")
                }.frame(maxWidth: .infinity)
            }.fixedSize(horizontal: false, vertical: true)

            if !store.status(device.id).message.isEmpty {
                Text(store.status(device.id).message).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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
