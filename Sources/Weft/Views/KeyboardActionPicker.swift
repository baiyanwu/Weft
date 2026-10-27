import SwiftUI
import WeftCore

struct KeyboardActionPicker: View {
    @Binding var selection: KeyboardMappingTarget?
    @State private var showing = false
    @State private var recordingTarget = false
    @State private var recordingError = ""

    var body: some View {
        HStack(spacing: 5) {
            if recordingTarget {
                KeyboardShortcutField(shortcut: Binding(get: { nil }, set: { shortcut in
                    guard let shortcut else { return }
                    guard KeyboardInputMapper.hidUsage(for: shortcut.keyCode) != nil else {
                        recordingError = "此按键暂不支持，请重新录入"; return
                    }
                    selection = KeyboardMappingTarget(action: .key, shortcut: shortcut)
                    recordingError = ""
                    recordingTarget = false
                }), placeholder: "录入目标按键", autoRecord: true, onEnd: { recordingTarget = false })
                Button { recordingTarget = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20, height: 30)
                }.buttonStyle(.plain).accessibilityLabel("取消录入目标按键")
            } else {
                Button { showing.toggle() } label: {
                    SelectionField(title: recordingError.isEmpty ? selection?.title ?? "选择操作" : recordingError, expanded: showing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Android 操作：\(selection?.title ?? "尚未选择")")
                .popover(isPresented: $showing, arrowEdge: .bottom) {
                    options
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择 Android 操作").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(KeyboardActionGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.rawValue).font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.top, 4)
                            ForEach(KeyboardMappingAction.allCases.filter { $0.group == group }) { action in
                                SelectionOptionRow(title: action.title, subtitle: action.detail, icon: action.icon,
                                    selected: selection?.action == action) {
                                    showing = false
                                    if action == .key {
                                        // Do not persist a partial target while recording or cancelling.
                                        recordingError = ""; recordingTarget = true
                                    } else {
                                        recordingError = ""
                                        selection = KeyboardMappingTarget(action: action)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: 288)
        }
        .padding(10).frame(width: 320).tint(WeftStyle.accent)
    }
}
