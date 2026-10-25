import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var store: DeviceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            PageHeading(title: "通用设置", subtitle: "统一管理启动、跨屏与快捷键", badge: "应用于这台 Mac")
            SettingsCard(title: "启动与运行") {
                VStack(spacing: 12) {
                    PreferenceRow(title: "登录时启动", subtitle: "登录 Mac 后在菜单栏运行") {
                        PendingBadge()
                        Toggle("登录时启动，暂未开放", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).disabled(true)
                    }
                    Divider()
                    PreferenceRow(title: "启动时打开设置窗口", subtitle: "关闭窗口后，weft 继续在菜单栏运行") {
                        Toggle("启动时打开设置窗口", isOn: $store.showOnLaunch).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
            ADBSettingsView()
            SettingsCard(title: "跨屏切换") {
                VStack(spacing: 12) {
                    PreferenceRow(title: "自动跨屏", subtitle: "按设备分别设置，开关互不影响") {
                        Button("前往设备设置") { store.section = .devices }.buttonStyle(WeftButtonStyle())
                    }
                    Label("在“设备与布局”中选择设备，配置该设备的自动跨屏；关闭后仍可通过菜单或快捷键进入。", systemImage: "cursorarrow")
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11).background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            SettingsCard(title: "快捷键") {
                VStack(spacing: 11) {
                    PreferenceRow(title: "切换 Mac / 上次设备") {
                        HStack(spacing: 6) { KeyCap(title: "⌃"); KeyCap(title: "⌥"); KeyCap(title: "M") }
                    }
                    Divider()
                    PreferenceRow(title: "立即返回 Mac", subtitle: "也可从设备靠近 Mac 的边缘返回") {
                        HStack(spacing: 8) { KeyCap(title: "左 ⌥"); Text("或").font(.caption).foregroundStyle(.secondary); KeyCap(title: "Esc") }
                    }
                    Divider()
                    PreferenceRow(title: "菜单栏面板", subtitle: "在 weft 窗口内使用") {
                        HStack(spacing: 6) { KeyCap(title: "⌘"); KeyCap(title: "⇧"); KeyCap(title: "M") }
                    }
                }
            }
            SettingsCard(title: "系统权限") {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield").font(.system(size: 25))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("辅助功能权限").fontWeight(.medium)
                        Text("用于捕获鼠标并在设备间切换").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(store.permissionGranted ? "已授权" : "未授权", systemImage: store.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.callout).foregroundStyle(store.permissionGranted ? WeftStyle.accentText : .orange)
                    Button { store.requestPermission() } label: { Label("管理权限", systemImage: "arrow.up.right") }.buttonStyle(WeftButtonStyle())
                }
            }
        }
    }
}
