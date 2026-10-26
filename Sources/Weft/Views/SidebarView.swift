import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: DeviceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) { BrandMark(size: 44); Text("weft").font(.system(size: 25, weight: .bold)) }
                .padding(.horizontal, 24).padding(.vertical, 21)
            Divider().padding(.horizontal, 20)
            navigation("设备与布局", icon: "display.2", section: .devices).padding(.top, 8)
            navigation("鼠标按键", icon: "computermouse", section: .mouseButtons).padding(.top, 4)
            navigation("键盘映射", icon: "keyboard", section: .keyboard).padding(.top, 4)
            Spacer(minLength: 24)
            Divider().padding(.horizontal, 20)
            navigation("通用设置", icon: "gearshape", section: .general).padding(.top, 8)
            navigation("帮助与诊断", icon: "book", section: .help).padding(.bottom, 15)
        }.background(.ultraThinMaterial)
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
            .accessibilityLabel(title)
            .accessibilityAddTraits(store.section == section ? .isSelected : [])
    }
}
