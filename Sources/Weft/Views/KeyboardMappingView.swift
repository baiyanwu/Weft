import SwiftUI
import WeftCore

struct KeyboardMappingView: View {
    @ObservedObject var store: DeviceStore
    @State private var selectedDeviceID: String?
    @State private var showingDevices = false
    @State private var adding = false
    @State private var draftShortcut: KeyboardKeyCombination?
    @State private var draftTarget: KeyboardMappingTarget?
    @State private var feedback = ""

    private var device: DeviceProfile? {
        store.profiles.first { $0.id == selectedDeviceID } ?? store.selected ?? store.profiles.first
    }
    private var rules: [KeyboardMappingRule] { device?.keyboardMapping.rules ?? [] }
    private var canAdd: Bool {
        guard let draftShortcut, draftTarget != nil else { return false }
        return !draftShortcut.isReserved && !rules.contains { $0.shortcut.matches(draftShortcut) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "键盘映射", subtitle: "共享键盘，并为常用按键设置映射", badge: "控制设备时生效")
            deviceSelector
            sharingSetting
            mappingCard
            returnHint
        }
        .onChange(of: device?.id) { _ in cancelDraft(); feedback = "" }
    }

    private var deviceSelector: some View {
        HStack(spacing: 12) {
            DeviceGlyph(kind: device?.kind ?? .tablet, size: 23)
            Text("应用设备").font(.system(size: 13, weight: .medium)).fixedSize()
            Button { showingDevices.toggle() } label: {
                SelectionField(title: device?.name ?? "尚未添加设备", expanded: showingDevices)
            }
            .buttonStyle(.plain).frame(width: 175).disabled(store.profiles.isEmpty)
            .accessibilityLabel("应用设备：\(device?.name ?? "尚未添加设备")")
            .popover(isPresented: $showingDevices, arrowEdge: .bottom) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.profiles) { profile in
                            SelectionOptionRow(title: profile.name, subtitle: store.status(profile.id).label,
                                icon: profile.kind == .tablet ? "ipad" : "iphone", selected: device?.id == profile.id) {
                                selectedDeviceID = profile.id; showingDevices = false
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(width: 290, height: min(CGFloat(store.profiles.count) * 64, 300))
                .padding(10).tint(WeftStyle.accent)
            }
            if let device {
                StatusDot(phase: store.status(device.id).phase)
                Text(store.status(device.id).label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("每台设备独立配置").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.vertical, 8)
    }

    private var sharingSetting: some View {
        VStack(alignment: .leading, spacing: 9) {
            PreferenceRow(title: "共享键盘", subtitle: "控制此设备时，键盘随鼠标一起切换") {
                Toggle("共享键盘", isOn: Binding(get: { device?.keyboardMapping.enabled ?? false }, set: { enabled in
                    update { $0.enabled = enabled }
                }))
                .labelsHidden().toggleStyle(.switch).disabled(device == nil)
            }
            if let device, device.keyboardMapping.enabled {
                let status = store.keyboardStatus(device.id)
                HStack(spacing: 10) {
                    Text(status.label).font(.caption)
                        .foregroundStyle(status.phase == .failed ? WeftStyle.warningText : WeftStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if status.phase == .failed {
                        Button("重试键盘") { store.retryKeyboard(device.id) }
                            .buttonStyle(WeftButtonStyle(height: 27, fontSize: 11))
                    }
                }
            }
        }
        .padding(16)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WeftStyle.border, lineWidth: 1))
    }

    private var mappingCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("按键映射").font(.system(size: 16, weight: .semibold))
                    Text("未配置的按键按原样发送").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { adding = true; feedback = "" } label: { Label("添加映射", systemImage: "plus") }
                    .buttonStyle(WeftButtonStyle(prominent: true))
                    .disabled(device == nil || adding)
            }.padding(16)
            tableHeader
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rules) { rule in
                            ruleRow(rule)
                            Divider()
                        }
                        if adding { draftRow.id("keyboardMappingDraft") }
                        if rules.isEmpty && !adding {
                            Text(device == nil ? "添加设备后，即可配置键盘映射。" : "暂无映射，点击“添加映射”创建规则。")
                                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .onChange(of: adding) { value in
                    if value {
                        DispatchQueue.main.async { withAnimation { proxy.scrollTo("keyboardMappingDraft", anchor: .bottom) } }
                    }
                }
            }
            .frame(height: min(270, max(72, CGFloat(rules.count + (adding ? 1 : 0)) * 54)))
            HStack(spacing: 10) {
                Text(feedback.isEmpty ? "点击按键录入，点击操作修改" : feedback)
                    .font(.caption).foregroundStyle(feedback.isEmpty ? WeftStyle.secondaryText : WeftStyle.warningText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 5)
                Button("恢复默认") {
                    update { $0.rules = KeyboardMapping.defaultRules }; cancelDraft(); feedback = ""
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(WeftStyle.accentText).disabled(device == nil)
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WeftStyle.border, lineWidth: 1))
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Mac 按键").frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 16, height: 1)
            Text("Android 操作").frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 80, height: 1)
        }
        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).frame(height: 34)
        .background(Color.primary.opacity(0.025))
    }

    private func ruleRow(_ rule: KeyboardMappingRule) -> some View {
        HStack(spacing: 12) {
            KeyboardShortcutField(shortcut: Binding(get: { rule.shortcut }, set: { shortcut in
                guard let shortcut, validate(shortcut, excluding: rule.id) else { return }
                updateRule(rule.id) { $0.shortcut = shortcut }
            })).frame(maxWidth: .infinity)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).frame(width: 16)
            KeyboardActionPicker(selection: Binding(get: { rule.target }, set: { target in
                guard let target else { return }; updateRule(rule.id) { $0.target = target }
            })).frame(maxWidth: .infinity)
            Button {
                update { $0.rules.removeAll { $0.id == rule.id } }; feedback = ""
            } label: {
                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 30, height: 33)
            }
            .buttonStyle(.plain).frame(width: 80, alignment: .trailing)
            .help("删除这条映射").accessibilityLabel("删除 \(rule.shortcut.displayTitle) 的映射")
        }.padding(.horizontal, 16).frame(height: 53)
    }

    private var draftRow: some View {
        HStack(spacing: 12) {
            KeyboardShortcutField(shortcut: Binding(get: { draftShortcut }, set: { shortcut in
                guard let shortcut, validate(shortcut) else { return }; draftShortcut = shortcut
            })).frame(maxWidth: .infinity)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).frame(width: 16)
            KeyboardActionPicker(selection: $draftTarget).frame(maxWidth: .infinity)
            HStack(spacing: 3) {
                Button("添加", action: addRule).buttonStyle(WeftButtonStyle(prominent: true, height: 29, fontSize: 12))
                    .disabled(!canAdd)
                Button(action: cancelDraft) {
                    Image(systemName: "xmark").font(.system(size: 11)).frame(width: 22, height: 30)
                }.buttonStyle(.plain).help("取消添加").accessibilityLabel("取消添加映射")
            }.frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16).frame(height: 54).background(WeftStyle.accent.opacity(0.065))
    }

    private var returnHint: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 22)).foregroundStyle(WeftStyle.accentText)
            Text("返回 Mac").font(.system(size: 13, weight: .medium))
            KeyCap(title: "⌃"); KeyCap(title: "⌥"); KeyCap(title: "M")
            Text("此快捷键始终保留").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(13).background(WeftStyle.wash, in: RoundedRectangle(cornerRadius: 11))
    }

    private func update(_ body: (inout KeyboardMapping) -> Void) {
        guard let id = device?.id else { return }; store.updateKeyboardMapping(id, body)
    }
    private func updateRule(_ id: UUID, _ body: (inout KeyboardMappingRule) -> Void) {
        update { mapping in
            guard let index = mapping.rules.firstIndex(where: { $0.id == id }) else { return }
            body(&mapping.rules[index])
        }
        feedback = ""
    }
    private func validate(_ shortcut: KeyboardKeyCombination, excluding id: UUID? = nil) -> Bool {
        if shortcut.isReserved { feedback = "⌃ ⌥ M 用于返回 Mac，请选择其他按键。"; return false }
        if KeyboardInputMapper.hidUsage(for: shortcut.keyCode) == nil {
            feedback = "此按键暂不支持，请选择普通按键或组合键。"; return false
        }
        if rules.contains(where: { $0.id != id && $0.shortcut.matches(shortcut) }) {
            feedback = "此快捷键已有映射，请修改已有规则或选择其他按键。"; return false
        }
        feedback = ""; return true
    }
    private func addRule() {
        guard canAdd, let draftShortcut, let draftTarget else { return }
        update { $0.rules.append(KeyboardMappingRule(shortcut: draftShortcut, target: draftTarget)) }
        cancelDraft(); feedback = ""
    }
    private func cancelDraft() { adding = false; draftShortcut = nil; draftTarget = nil }
}
