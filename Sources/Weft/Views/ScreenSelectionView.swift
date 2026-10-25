import SwiftUI
import AppKit
import WeftCore

struct ScreenSelectionView: View {
    @ObservedObject var store: DeviceStore
    let device: DeviceProfile
    @State private var showing = false
    private var title: String {
        if device.displayID == 0 { return "跟随主显示器" }
        return store.screens.first { $0.id == device.displayID }?.name ?? "屏幕已断开 · 暂用主屏幕"
    }
    var body: some View {
        Button { showing.toggle() } label: { SelectionField(title: title, expanded: showing) }
            .buttonStyle(.plain).accessibilityLabel("Mac 出入口屏幕：\(title)")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择 Mac 屏幕").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
                    ScrollView {
                        VStack(spacing: 4) {
                            screenRow(id: 0, name: "跟随主显示器", detail: "使用当前主显示器", icon: "display")
                            ForEach(store.screens) { screen in
                                screenRow(id: screen.id, name: screen.name,
                                          detail: screen.id == CGMainDisplayID() ? "主显示器" : "扩展显示器",
                                          icon: CGDisplayIsBuiltin(screen.id) != 0 ? "laptopcomputer" : "desktopcomputer")
                            }
                            if device.displayID != 0 && !store.screens.contains(where: { $0.id == device.displayID }) {
                                HStack(spacing: 13) {
                                    Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 23)).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("原屏幕已断开").fontWeight(.medium)
                                        Text("当前暂用主显示器").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "checkmark").foregroundStyle(WeftStyle.accentText)
                                }.padding(12).background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }.frame(height: min(CGFloat(store.screens.count + 1 + (device.displayID != 0 && !store.screens.contains { $0.id == device.displayID } ? 1 : 0)) * 64, 300))
                    Divider().padding(.horizontal, 8)
                    PopoverAction(title: "识别屏幕", icon: "viewfinder", pending: true)
                    Text("鼠标将从所选屏幕设置的出入口进入\(device.name)。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 4)
                }.padding(10).frame(width: 340).tint(WeftStyle.accent)
            }
    }

    private func screenRow(id: UInt32, name: String, detail: String, icon: String) -> some View {
        SelectionOptionRow(title: name, subtitle: detail, icon: icon, selected: device.displayID == id) {
            store.update(device.id) { $0.displayID = id; $0.edgeOffsetMM = nil }
            store.layoutDisplayID = id == 0 ? CGMainDisplayID() : id
            showing = false
        }
    }
}
