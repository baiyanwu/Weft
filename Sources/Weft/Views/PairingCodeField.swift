import SwiftUI

struct PairingCodeField: View {
    @Binding var digits: [String]
    @State private var focusedDigit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("配对码").font(.system(size: 13, weight: .semibold))
                Text("仅限 6 位数字").font(.system(size: 12)).foregroundStyle(WeftStyle.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(0..<6) { index in
                    NumericSegmentField(title: "配对码第 \(index + 1) 位，共 6 位", text: $digits[index],
                        focused: focusBinding(index), maximumDigits: 1, maximumValue: 9,
                        fontSize: 16, onAdvance: { focusedDigit = min(index + 1, 5) },
                        onBackspace: index > 0 ? {
                            digits[index - 1] = ""
                            focusedDigit = index - 1
                        } : nil, onPaste: { paste($0, at: index) })
                        .frame(width: 36, height: 36)
                        .modifier(NumericSlotStyle(focused: focusedDigit == index))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { focusedDigit == index }, set: { focused in
            if focused { focusedDigit = index }
            else if focusedDigit == index { focusedDigit = nil }
        })
    }

    private func paste(_ text: String, at index: Int) -> Bool {
        let numbers = text.filter { $0.isASCII && $0.isNumber }
        guard numbers.count > 1 else { return false }
        let start = numbers.count >= 6 ? 0 : index
        let inserted = Array(numbers.prefix(6 - start))
        for offset in inserted.indices { digits[start + offset] = String(inserted[offset]) }
        focusedDigit = min(start + inserted.count, 5)
        return true
    }
}
