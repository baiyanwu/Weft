import SwiftUI
import WeftCore

struct MouseButtonMappingView: View {
    @ObservedObject var store: DeviceStore
    @State private var selectedDeviceID: String?
    @State private var showingDevices = false
    @State private var selectedButton: MouseMappingButton

    init(store: DeviceStore, selectedButton: MouseMappingButton = .left) {
        self.store = store
        _selectedButton = State(initialValue: selectedButton)
    }

    private var selectedDevice: DeviceProfile? {
        store.profiles.first { $0.id == selectedDeviceID } ?? store.selected ?? store.profiles.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader
            deviceSelector
            GeometryReader { geometry in workspace(width: geometry.size.width) }
                .frame(height: 410)
            Divider()
        }
        .onChange(of: store.profiles.map(\.id)) { ids in
            if let selectedDeviceID, !ids.contains(selectedDeviceID) { self.selectedDeviceID = nil }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("鼠标按键映射").font(.system(size: 27, weight: .bold))
                Text("为五个按键分配常用操作").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Label("控制设备时生效", systemImage: "computermouse")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(WeftStyle.border, lineWidth: 1))
        }
    }

    private var deviceSelector: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let device = selectedDevice {
                    DeviceGlyph(kind: device.kind, size: 23)
                } else {
                    Image(systemName: "iphone").font(.system(size: 23)).frame(width: 31)
                }
                Text("应用设备").font(.system(size: 13, weight: .medium)).fixedSize()
                Button { showingDevices.toggle() } label: {
                    SelectionField(title: selectedDevice?.name ?? "尚未添加设备", expanded: showingDevices)
                }
                .buttonStyle(.plain)
                .frame(width: 175)
                .disabled(store.profiles.isEmpty)
                .accessibilityLabel("应用设备：\(selectedDevice?.name ?? "尚未添加设备")")
                .popover(isPresented: $showingDevices, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(store.profiles) { device in
                                SelectionOptionRow(title: device.name, subtitle: store.status(device.id).label,
                                    icon: device.kind == .tablet ? "ipad" : "iphone", selected: selectedDevice?.id == device.id) {
                                    selectedDeviceID = device.id
                                    showingDevices = false
                                }
                            }
                        }
                    }.frame(width: 290, height: min(CGFloat(store.profiles.count) * 64, 320))
                        .padding(10).tint(WeftStyle.accent)
                }
                Text("每台设备独立配置").font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).layoutPriority(-1)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("启用映射").font(.system(size: 12))
                        Toggle("启用映射", isOn: Binding(get: { selectedDevice?.mouseMapping.enabled ?? false }, set: { enabled in
                            guard let id = selectedDevice?.id else { return }
                            store.update(id) { $0.mouseMapping.enabled = enabled }
                        }))
                            .labelsHidden().toggleStyle(.switch).disabled(selectedDevice == nil)
                    }
                }.help("启用后，仅在控制这台设备时应用按键映射")
            }.padding(.horizontal, 10).padding(.vertical, 12)
            Divider()
        }.background(WeftStyle.accent.opacity(0.025))
    }

    private func workspace(width: CGFloat) -> some View {
        let available = max(0, width - 74)
        let diagramWidth = min(246, max(204, available * 0.26))
        let listWidth = min(246, max(150, available * 0.255))
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("五键鼠标", subtitle: "点击编号选择按键")
                MouseButtonDiagram(selection: $selectedButton)
            }.frame(width: diagramWidth)
            Rectangle().fill(WeftStyle.border).frame(width: 1, height: 410)
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("选择按键", subtitle: "五个按键独立设置")
                VStack(spacing: 0) {
                    ForEach(MouseMappingButton.allCases) { button in
                        if button != .left { Divider().padding(.horizontal, 10) }
                        buttonRow(button)
                    }
                }
            }.frame(width: listWidth)
            Rectangle().fill(WeftStyle.border).frame(width: 1, height: 410)
            functionSelector.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func buttonRow(_ button: MouseMappingButton) -> some View {
        let selected = selectedButton == button
        let action = selectedDevice?.mouseMapping[button] ?? .original
        return Button { selectedButton = button } label: {
            HStack(spacing: 10) {
                MouseButtonNumber(button: button, selected: selected)
                VStack(alignment: .leading, spacing: 4) {
                    Text(button.title).font(.system(size: 13, weight: .medium))
                    Text(action.title(for: button)).font(.system(size: 11))
                        .foregroundStyle(selected ? WeftStyle.accentText : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeftStyle.accentText)
                }
            }
            .padding(.horizontal, 10).frame(height: 62)
            .background(selected ? WeftStyle.wash : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? WeftStyle.accent.opacity(0.65) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityLabel("选择\(button.title)，当前功能：\(action.title(for: button))")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var functionSelector: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("\(selectedButton.title)的功能", subtitle: "选择此按键要执行的操作")
            LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 10), GridItem(.flexible(minimum: 0), spacing: 10)], spacing: 10) {
                ForEach([MouseMappingAction.original] + MouseMappingAction.deviceFunctions) { option in
                    functionOption(option)
                }
            }.disabled(selectedDevice == nil)
        }
    }

    private func functionOption(_ option: MouseMappingAction) -> some View {
        let button = selectedButton
        let selected = (selectedDevice?.mouseMapping[button] ?? .original) == option
        let original = option == .original
        let icon = original ? "computermouse" : option.icon(for: button)
        return Button {
            guard let id = selectedDevice?.id else { return }
            store.update(id) { $0.mouseMapping[button] = option }
        } label: {
            GeometryReader { geometry in
                Group {
                    if geometry.size.width < 145 {
                        VStack(spacing: 8) {
                            Image(systemName: icon).font(.system(size: 24))
                            optionTitle(option, button: button, alignment: .center)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: icon).font(.system(size: 25)).frame(width: 30)
                            optionTitle(option, button: button, alignment: .leading)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.padding(.horizontal, 13)
                    .foregroundStyle(selected ? WeftStyle.accentText : Color.primary)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                                .foregroundStyle(WeftStyle.accent).padding(8)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: 104)
        }.buttonStyle(MouseMappingTileStyle(selected: selected))
            .accessibilityLabel("将\(button.title)设为\(option.title(for: button))\(original ? "，默认按键" : "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionTitle(_ option: MouseMappingAction, button: MouseMappingButton, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(option.title(for: button)).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if option == .original {
                Text("默认按键").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.045), in: Capsule())
            }
        }
    }
}

private struct MouseMappingTileStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? WeftStyle.selection : LinearGradient(colors: [Color.primary.opacity(configuration.isPressed ? 0.05 : 0.015)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? WeftStyle.accent : WeftStyle.border, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}
