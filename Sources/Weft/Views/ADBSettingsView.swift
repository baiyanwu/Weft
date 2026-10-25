import SwiftUI
import AppKit

struct ADBSettingsView: View {
    @ObservedObject var configuration: ADBConfiguration = .shared
    @State private var path = ""

    var body: some View {
        SettingsCard(title: "ADB 连接工具") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 11) {
                    Image(systemName: "terminal").font(.system(size: 23)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.isAutomatic ? "自动查找" : "使用指定的 ADB").fontWeight(.medium)
                        Text(configuration.isAutomatic ? "优先使用已安装版本，未找到时使用应用内置版本。" : "始终使用指定文件；不可用时会提示你重新选择。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if configuration.scanning { ProgressView().controlSize(.small).accessibilityLabel("正在扫描 ADB") }
                    Button { configuration.scan() } label: { Label("重新扫描", systemImage: "arrow.clockwise") }
                        .buttonStyle(WeftButtonStyle()).disabled(configuration.scanning)
                        .help(configuration.isAutomatic ? "重新查找本机已安装的 ADB" : "重新验证指定的 ADB，保留当前选择")
                }
                Divider()
                HStack(spacing: 8) {
                    WeftTextField(title: "ADB 文件路径", placeholder: "自动查找，或填写 ADB 文件的完整路径", text: $path)
                        .onSubmit { applyPath() }
                    Button("应用路径") { applyPath() }.buttonStyle(WeftButtonStyle())
                        .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || path == configuration.customPath || configuration.scanning)
                    Button("选择文件…") { chooseFile() }.buttonStyle(WeftButtonStyle()).disabled(configuration.scanning)
                }
                if let selected = configuration.selected {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Label(selected.source.rawValue, systemImage: "checkmark.circle.fill").foregroundStyle(WeftStyle.accentText)
                            Text("·").foregroundStyle(.tertiary)
                            Text("ADB \(selected.version)").foregroundStyle(.secondary)
                        }.font(.caption)
                        Text(selected.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(2).truncationMode(.middle).help(selected.path)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                        .background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 9))
                } else if !configuration.error.isEmpty && !configuration.scanning {
                    Label(configuration.error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !configuration.isAutomatic {
                    Button("恢复自动查找") { path = ""; configuration.select(path: "") }
                        .buttonStyle(.link).font(.caption).disabled(configuration.scanning)
                }
            }
        }
        .onAppear { path = configuration.customPath }
        .onChange(of: configuration.customPath) { path = $0 }
    }

    private func applyPath() {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        configuration.select(path: path)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 ADB 文件"; panel.message = "请选择 platform-tools 中的 adb 可执行文件。"
        panel.prompt = "使用此文件"; panel.canChooseDirectories = false
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        if let selected = configuration.selected {
            panel.directoryURL = URL(fileURLWithPath: selected.path).deletingLastPathComponent()
        }
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            path = url.path; configuration.select(path: url.path)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
