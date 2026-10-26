import SwiftUI
import AppKit

struct HelpView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject private var adb = ADBConfiguration.shared
    @State private var expanded: String? = "entry"
    private var adbInstalled: Bool { ADB.path != nil }
    private var summary: String {
        if store.paused { return "连接已暂停" }
        if !store.permissionGranted { return "需要辅助功能权限" }
        if !adbInstalled { return "未找到连接工具" }
        if !store.discoveryError.isEmpty { return "设备发现异常" }
        return store.connectedCount > 0 ? "设备已连接" : "等待设备连接"
    }
    private var ready: Bool { !store.paused && store.permissionGranted && adbInstalled && store.discoveryError.isEmpty && store.connectedCount > 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            PageHeading(title: "帮助与诊断", subtitle: "了解使用方式，排查连接与跨屏问题")
            connectionSummary
            Text("快速帮助").font(.system(size: 16, weight: .semibold)).padding(.top, 2)
            VStack(spacing: 0) {
                helpItem("connect", title: "如何连接 Android 设备", icon: "ipad") {
                    Text("使用 USB 连接设备，开启 USB 调试并允许这台 Mac。无线连接请使用 Android 的无线调试配对码和连接地址。")
                    helpLink("添加设备", icon: "plus") { store.showingAddDevice = true }
                }
                Divider()
                helpItem("entry", title: "鼠标无法进入设备", icon: "cursorarrow") {
                    Text("确认设备已连接并已授权辅助功能，检查该设备的出入口屏幕、位置和自动跨屏设置。到对应边缘后继续向外推；按住鼠标拖拽时不会跨屏。")
                    HStack(spacing: 18) {
                        helpLink("管理权限", icon: "arrow.up.right") { store.requestPermission() }
                        helpLink("前往通用设置", icon: "chevron.right") { store.section = .general }
                    }
                }
                Divider()
                helpItem("connection", title: "连接中断或鼠标无响应", icon: "exclamationmark.triangle") {
                    Text("先按 Control + Option + M 返回 Mac，再检查设备连接与调试授权。未共享键盘时也可按左 Option 或 Esc 返回。自动连接开启时，weft 会尝试重新连接；手动断开的设备需点击“连接设备”。")
                    helpLink("查看设备设置", icon: "chevron.right") { store.section = .devices }
                }
            }.background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(WeftStyle.border, lineWidth: 1))
            Text("诊断工具").font(.system(size: 16, weight: .semibold)).padding(.top, 2)
            HStack(spacing: 14) {
                toolCard("查看诊断日志", subtitle: "查看连接与切换记录", icon: "doc.text") { NSWorkspace.shared.open(Log.url) }
                toolCard("导出诊断报告", subtitle: "保存当前状态，供排查问题使用", icon: "arrow.down.to.line") { store.exportDiagnostics() }
            }
        }
    }

    private var connectionSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Image(systemName: ready ? "checkmark.circle" : "info.circle")
                    .font(.system(size: 42, weight: .light)).foregroundStyle(ready ? WeftStyle.accent : .secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary).font(.system(size: 23, weight: .semibold))
                    Text("\(store.connectedCount) 台设备已连接 · \(store.switching ? "正在切换至" : "当前控制") \(store.controlName)")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button { store.discovery.scan() } label: { Label("刷新设备", systemImage: "arrow.clockwise") }.buttonStyle(WeftButtonStyle())
            }
            Divider()
            HStack(spacing: 18) {
                statusItem("辅助功能", detail: store.permissionGranted ? "已授权" : "未授权", available: store.permissionGranted)
                Divider().frame(height: 34)
                statusItem("连接工具", detail: adb.selected?.source.rawValue ?? (adb.scanning ? "正在查找" : "不可用"), available: adbInstalled)
                Divider().frame(height: 34)
                statusItem("设备连接", detail: store.paused ? "已暂停" : "\(store.connectedCount) / \(store.profiles.count) 台在线", available: !store.paused && store.connectedCount > 0)
            }
            if !store.discoveryError.isEmpty && store.discoveryError != adb.error {
                Text(store.discoveryError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if !adb.error.isEmpty && !adb.scanning {
                Text(adb.error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                helpLink("配置 ADB", icon: "chevron.right") { store.section = .general }
            }
        }.padding(20).background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(WeftStyle.accent.opacity(0.19), lineWidth: 1))
    }
    private func statusItem(_ title: String, detail: String, available: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? WeftStyle.accent : .secondary).font(.system(size: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(available ? WeftStyle.accentText : .secondary)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func helpItem<Content: View>(_ id: String, title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded = expanded == id ? nil : id } } label: {
                HStack(spacing: 16) {
                    Image(systemName: icon).font(.system(size: 23)).frame(width: 28)
                    Text(title).font(.system(size: 14, weight: .medium)); Spacer()
                    Image(systemName: expanded == id ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .medium))
                }.padding(.horizontal, 18).frame(height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded == id {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 51).padding(.trailing, 16).padding(.vertical, 14)
                    .background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }
    private func helpLink(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 5) { Text(title); Image(systemName: icon).font(.caption) } }
            .buttonStyle(.plain).foregroundStyle(WeftStyle.accentText)
    }
    private func toolCard(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.system(size: 25)).frame(width: 29)
                VStack(alignment: .leading, spacing: 5) { Text(title).fontWeight(.medium); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 3); Image(systemName: "chevron.right").font(.caption)
            }.padding(19).frame(maxWidth: .infinity, minHeight: 75).contentShape(Rectangle())
                .background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(WeftStyle.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
