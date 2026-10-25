import SwiftUI

struct WirelessAddressField: View {
    let title: String
    let source: String
    let portPlaceholder: String
    @Binding var address: WirelessAddressInput
    @State private var focusedSegment: Int?
    private let placeholders = ["192", "168", "1", "8"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(source).font(.system(size: 12)).foregroundStyle(WeftStyle.secondaryText)
            }
            HStack(spacing: 10) {
                addressContainer("IP 地址") {
                    HStack(spacing: 6) {
                        ForEach(0..<4) { index in
                            if index > 0 {
                                Text("·").font(.system(size: 14, weight: .medium)).foregroundStyle(WeftStyle.secondaryText)
                            }
                            NumericSegmentField(title: "\(title)，IP 地址第 \(index + 1) 段", text: $address.octets[index],
                                focused: focusBinding(index), maximumDigits: 3, maximumValue: 255,
                                placeholder: placeholders[index], advancesOnSeparator: true,
                                onAdvance: { focusedSegment = index + 1 },
                                onBackspace: index > 0 ? { backspace(before: index) } : nil,
                                onPaste: pasteAddress)
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .modifier(NumericSlotStyle(focused: focusedSegment == index))
                        }
                    }
                }
                addressContainer("端口") {
                    NumericSegmentField(title: "\(title)，端口", text: $address.port,
                        focused: focusBinding(4), maximumDigits: 5, maximumValue: 65535,
                        placeholder: portPlaceholder, onBackspace: { backspace(before: 4) }, onPaste: pasteAddress)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .modifier(NumericSlotStyle(focused: focusedSegment == 4))
                }.frame(width: 128)
            }
        }
    }

    private func addressContainer<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.system(size: 11)).foregroundStyle(WeftStyle.secondaryText)
            content()
        }.padding(.horizontal, 9).padding(.vertical, 6)
            .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(WeftStyle.border, lineWidth: 1))
    }

    private func focusBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { focusedSegment == index }, set: { focused in
            if focused { focusedSegment = index }
            else if focusedSegment == index { focusedSegment = nil }
        })
    }

    private func backspace(before index: Int) {
        let previous = index - 1
        if !address.octets[previous].isEmpty { address.octets[previous].removeLast() }
        focusedSegment = previous
    }

    private func pasteAddress(_ text: String) -> Bool {
        // A whole address can be pasted into any slot; incomplete dot-separated input is not flattened into an octet.
        guard text.contains(".") || text.contains(":") else { return false }
        var replacement = address
        if replacement.paste(text) {
            address = replacement
            focusedSegment = 4
            return true
        }
        return text.filter { $0 == "." || $0 == ":" }.count > 1 || (!text.hasSuffix(".") && !text.hasSuffix(":"))
    }
}

struct NumericSlotStyle: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? WeftStyle.accent : WeftStyle.border,
                lineWidth: focused ? 1.5 : 1))
    }
}
