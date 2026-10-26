import SwiftUI
import AppKit

struct ScrcpySettingsView: View {
    @ObservedObject var configuration: ScrcpyConfiguration
    @State private var path = ""

    var body: some View {
        SettingsCard(title: "scrcpy 投屏工具") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 11) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 23)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.isAutomatic ? "自动查找本机安装" : "使用指定的 scrcpy").fontWeight(.medium)
                        Text("使用这台 Mac 已安装的 scrcpy，在独立窗口中显示与操作设备。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if configuration.scanning { ProgressView().controlSize(.small).accessibilityLabel("正在查找 scrcpy") }
                    Button { configuration.scan() } label: { Label("重新扫描", systemImage: "arrow.clockwise") }
                        .buttonStyle(WeftButtonStyle()).disabled(configuration.scanning)
                        .accessibilityIdentifier("scrcpy.rescan")
                }
                Divider()
                HStack(spacing: 8) {
                    WeftTextField(title: "scrcpy 文件路径", placeholder: "自动查找，或填写 scrcpy 文件的完整路径", text: $path)
                        .onSubmit { applyPath() }
                    Button("应用路径") { applyPath() }.buttonStyle(WeftButtonStyle())
                        .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || path == configuration.customPath || configuration.scanning)
                    Button("选择文件…") { chooseFile() }.buttonStyle(WeftButtonStyle())
                        .disabled(configuration.scanning).accessibilityIdentifier("scrcpy.choose-file")
                }
                if let selected = configuration.selected {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("scrcpy \(selected.version) · 可用于投屏", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(WeftStyle.accentText).font(.caption)
                        Text(selected.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(2).truncationMode(.middle).help(selected.path)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                        .background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 9))
                } else if !configuration.error.isEmpty && !configuration.scanning {
                    Label(configuration.error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    Link("安装说明 ↗", destination: URL(string: "https://github.com/Genymobile/scrcpy/blob/master/doc/macos.md")!)
                    if !configuration.isAutomatic {
                        Button("恢复自动查找") { path = ""; configuration.select(path: "") }
                            .buttonStyle(.link).disabled(configuration.scanning)
                    }
                }.font(.caption)
            }
        }
        .onAppear {
            path = configuration.customPath
            if configuration.selected == nil && configuration.error.isEmpty && !configuration.scanning { configuration.scan() }
        }
        .onChange(of: configuration.customPath) { path = $0 }
    }

    private func applyPath() {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        configuration.select(path: path)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 scrcpy 文件"; panel.message = "请选择本机已安装的 scrcpy 可执行文件。"
        panel.prompt = "使用此文件"; panel.canChooseDirectories = false
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: configuration.selected?.path ?? "/opt/homebrew/bin/scrcpy").deletingLastPathComponent()
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            path = url.path; configuration.select(path: url.path)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
