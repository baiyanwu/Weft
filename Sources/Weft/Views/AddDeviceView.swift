import AppKit
import SwiftUI
import WeftCore

struct AddDeviceView: View {
    @ObservedObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var wireless = false
    @State private var selectedID: String?
    @State private var showingHelp = false
    @State private var paired = false
    @State private var pairAddress = WirelessAddressInput()
    @State private var pairCode = Array(repeating: "", count: 6)
    @State private var connectAddress = WirelessAddressInput()

    private var discovered: [DeviceEndpoint] {
        var seen = Set<String>()
        return store.endpoints.filter { $0.usb != wireless && seen.insert($0.hardwareID).inserted }
    }
    private var selected: DeviceEndpoint? {
        discovered.first { $0.id == selectedID && $0.usable && store.profile($0.hardwareID) == nil }
    }
    private var discoveryHint: String {
        if !discovered.isEmpty && discovered.allSatisfy({ store.profile($0.hardwareID) != nil }) {
            return "列表中的设备均已添加；接入新设备后可刷新。"
        }
        return wireless ? "连接成功后，在列表中选择设备并添加到 weft" : "连接 USB 并允许调试，然后选择设备添加到 weft"
    }
    private func displayName(_ endpoint: DeviceEndpoint) -> String {
        store.profile(endpoint.hardwareID)?.name ?? (endpoint.model == "OPD2413" ? "一加平板" : endpoint.model == "Seeker" ? "Seeker 手机" : endpoint.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("添加设备").font(.system(size: 27, weight: .bold))
                    Text("选择要与这台 Mac 共享鼠标的 Android 设备").font(.system(size: 14)).foregroundStyle(WeftStyle.secondaryText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                }
                    .buttonStyle(.plain).foregroundStyle(WeftStyle.secondaryText).keyboardShortcut(.cancelAction).accessibilityLabel("关闭添加设备")
            }
            connectionTabs
            if wireless {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        wirelessForm
                        discoveryList
                        discoveryError
                    }.padding(.horizontal, 1)
                }.frame(height: wirelessContentHeight)
            } else {
                discoveryList
                discoveryError
            }
            Divider()
            HStack(spacing: 12) {
                Button { showingHelp.toggle() } label: { Label("未找到设备？", systemImage: "questionmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(WeftStyle.secondaryText)
                    .popover(isPresented: $showingHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("连接提示").font(.headline)
                            Text(wireless ? "确认 Mac 与 Android 在同一网络，开启无线调试。配对与连接使用不同端口；配对成功后，刷新列表并选择设备。" : "使用支持数据传输的 USB 线，开启 Android 的 USB 调试，并在设备上允许这台 Mac。已添加的设备会标注“已添加”。")
                                .font(.callout).foregroundStyle(WeftStyle.secondaryText)
                        }.padding(20).frame(width: 300)
                    }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(WeftButtonStyle())
                Button(wireless || store.paused ? "添加设备" : "添加并连接") {
                    guard let endpoint = selected else { return }
                    store.add(endpoint)
                    dismiss()
                }.buttonStyle(WeftButtonStyle(prominent: true)).disabled(selected == nil)
            }.padding(.top, 2)
        }.padding(27).frame(width: 650).tint(WeftStyle.accent)
            .onAppear { store.discovery.scan() }
    }

    private var connectionTabs: some View {
        HStack(spacing: 4) {
            transportTab("USB 连接", icon: "cable.connector", isWireless: false)
            transportTab("无线连接", icon: "wifi", isWireless: true)
        }.padding(4).background(WeftStyle.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(WeftStyle.border, lineWidth: 1))
    }
    private func transportTab(_ title: String, icon: String, isWireless: Bool) -> some View {
        Button { wireless = isWireless; selectedID = nil } label: {
            Label(title, systemImage: icon).font(.system(size: 14, weight: wireless == isWireless ? .semibold : .regular))
                .frame(maxWidth: .infinity).frame(height: 37).contentShape(Rectangle())
                .background(wireless == isWireless ? WeftStyle.selection : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 8))
                .background(.background.opacity(wireless == isWireless ? 0 : 0.65), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(wireless == isWireless ? .isSelected : [])
    }

    private var discoveryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(wireless ? "2. 选择要添加的设备" : "已发现设备").font(.system(size: 16, weight: .semibold))
                    Text(discoveryHint)
                        .font(.caption).foregroundStyle(WeftStyle.secondaryText)
                }
                Spacer()
                Button { store.discovery.scan() } label: { Label("刷新", systemImage: "arrow.clockwise") }.buttonStyle(WeftButtonStyle())
            }
            ScrollView {
                VStack(spacing: 0) {
                    if discovered.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: wireless ? "wifi" : "cable.connector").font(.system(size: 24)).foregroundStyle(WeftStyle.secondaryText)
                            Text(wireless ? "暂无已发现的无线设备" : "暂无已发现的 USB 设备").fontWeight(.medium)
                            Text(wireless ? (paired ? "先在上方完成连接，再刷新列表。" : "先在上方完成配对与连接，再刷新列表。") : "连接设备并允许 USB 调试后，点击刷新。")
                                .font(.caption).foregroundStyle(WeftStyle.secondaryText)
                        }.frame(maxWidth: .infinity, minHeight: wireless ? 112 : 172)
                    }
                    ForEach(discovered) { endpoint in
                        deviceRow(endpoint)
                        if endpoint.id != discovered.last?.id { Divider().padding(.leading, 16) }
                    }
                }
            }.frame(height: wireless ? 125 : 190)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(WeftStyle.border, lineWidth: 1))
        }
    }
    private func deviceRow(_ endpoint: DeviceEndpoint) -> some View {
        let added = store.profile(endpoint.hardwareID) != nil
        let chosen = selectedID == endpoint.id && !added && endpoint.usable
        let state = added ? "已添加" : endpoint.usable ? "可添加" : endpoint.authorization == "unauthorized" ? "待授权" : "离线"
        let label = HStack(spacing: 16) {
                DeviceGlyph(kind: endpoint.kind, size: 29)
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName(endpoint)).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                    Text("\(endpoint.transport) · \(state)").font(.caption).foregroundStyle(endpoint.authorization == "unauthorized" ? WeftStyle.warningText : WeftStyle.secondaryText)
                    if endpoint.authorization == "unauthorized" { Text("请在设备上允许调试请求").font(.caption).foregroundStyle(WeftStyle.secondaryText) }
                }
                Spacer()
                if added {
                    Text("已添加").font(.caption).foregroundStyle(WeftStyle.secondaryText).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 22)).foregroundStyle(chosen ? WeftStyle.accent : WeftStyle.mutedText)
                }
            }.padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 70).contentShape(Rectangle())
                .background(chosen ? WeftStyle.wash : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? WeftStyle.accent.opacity(0.5) : .clear, lineWidth: 1))
                .foregroundStyle(Color.primary)
        return Group {
            if !added && endpoint.usable {
                Button { selectedID = endpoint.id } label: { label }.buttonStyle(.plain)
            } else {
                // Read-only rows remain legible; badges communicate why they cannot be selected.
                label.accessibilityElement(children: .combine)
            }
        }
    }

    private var wirelessForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. 连接到 Mac").font(.system(size: 16, weight: .semibold))
                Text("在 Android 中开启无线调试，并与 Mac 连接同一网络。")
                    .font(.caption).foregroundStyle(WeftStyle.secondaryText)
            }
            Toggle("此设备已与 Mac 配对", isOn: $paired).toggleStyle(WeftCheckboxStyle())
                .font(.system(size: 14)).foregroundStyle(Color.primary).disabled(store.pairingBusy)
            WirelessAddressField(title: "连接地址", source: "来自无线调试主页面", portPlaceholder: "39871", address: $connectAddress)
                .disabled(store.pairingBusy)
            if !paired {
                WirelessAddressField(title: "配对地址", source: "来自配对码页面", portPlaceholder: "37123", address: $pairAddress)
                    .disabled(store.pairingBusy)
                HStack(alignment: .bottom, spacing: 12) {
                    PairingCodeField(digits: $pairCode).disabled(store.pairingBusy)
                    connectButton(height: 36)
                }
            } else {
                HStack {
                    Spacer()
                    connectButton(height: 32)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                Text(paired ? "设备已配对，只需填写无线调试主页面上的连接地址。" : "配对端口与连接端口通常不同，请分别填写。")
            }.font(.caption).foregroundStyle(WeftStyle.secondaryText)
            if store.pairingBusy || !store.pairingMessage.isEmpty {
                HStack(spacing: 8) {
                    if store.pairingBusy { ProgressView().controlSize(.small) }
                    Text(store.pairingMessage).font(.caption).foregroundStyle(WeftStyle.secondaryText).textSelection(.enabled)
                }
            }
        }.padding(16)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WeftStyle.border, lineWidth: 1))
    }

    private var canConnect: Bool {
        connectAddress.endpoint != nil && (paired || (pairAddress.endpoint != nil && PairingValidation.code(pairCode.joined())))
    }

    private func connectButton(height: CGFloat) -> some View {
        Button {
            guard canConnect, let endpoint = connectAddress.endpoint else { return }
            store.pair(pairAddress: pairAddress.endpoint ?? "", code: pairCode.joined(),
                connectAddress: endpoint, alreadyPaired: paired)
            pairCode = Array(repeating: "", count: 6)
        } label: {
            HStack(spacing: 8) {
                Text(paired ? "连接到 Mac" : "配对并连接").fontWeight(.semibold)
                Image(systemName: "arrow.right").fontWeight(.medium)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(WeftButtonStyle(prominent: true, height: height)).frame(width: 128)
            .disabled(store.pairingBusy || !canConnect)
    }

    private var wirelessContentHeight: CGFloat {
        min(paired ? 470 : 590, max(260, (NSScreen.main?.visibleFrame.height ?? 900) - 270))
    }

    @ViewBuilder private var discoveryError: some View {
        if !store.discoveryError.isEmpty {
            Text(store.discoveryError).font(.caption).foregroundStyle(WeftStyle.warningText).textSelection(.enabled)
        }
    }
}
