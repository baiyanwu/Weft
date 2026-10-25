import SwiftUI
import WeftCore

struct DirectionSelectionView: View {
    @ObservedObject var store: DeviceStore
    let device: DeviceProfile
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { SelectionField(title: device.direction.label, expanded: showing) }
            .buttonStyle(.plain).accessibilityLabel("设备位置：\(device.direction.label)")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择设备位置").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
                    VStack(spacing: 4) {
                        ForEach(Direction.allCases, id: \.self) { direction in
                            let option = presentation(direction)
                            SelectionOptionRow(title: option.title, subtitle: option.subtitle, icon: option.icon, selected: device.direction == direction) {
                                store.update(device.id) { $0.direction = direction; $0.edgeOffsetMM = nil }
                                showing = false
                            }
                        }
                    }
                    Divider().padding(.horizontal, 8)
                    Text("按\(device.name)相对 Mac 的摆放位置选择方向，也可在布局图中拖动调整。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.bottom, 4)
                }.padding(10).frame(width: 340).tint(WeftStyle.accent)
            }
    }

    private func presentation(_ direction: Direction) -> (title: String, subtitle: String, icon: String) {
        switch direction {
        case .below: return ("Mac 下方", "从 Mac 屏幕下边缘进入", "arrow.down")
        case .above: return ("Mac 上方", "从 Mac 屏幕上边缘进入", "arrow.up")
        case .left: return ("Mac 左侧", "从 Mac 屏幕左边缘进入", "arrow.left")
        case .right: return ("Mac 右侧", "从 Mac 屏幕右边缘进入", "arrow.right")
        }
    }
}
