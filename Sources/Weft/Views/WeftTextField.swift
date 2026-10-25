import SwiftUI

struct WeftTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(title, text: $text, prompt: Text(placeholder).foregroundColor(WeftStyle.mutedText))
                    .focused($focused)
            } else {
                TextField(title, text: $text, prompt: Text(placeholder).foregroundColor(WeftStyle.mutedText))
                    .focused($focused)
            }
        }.textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Color.primary)
            .padding(.horizontal, 11).frame(height: 34)
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? WeftStyle.accent : WeftStyle.border, lineWidth: 1))
            .shadow(color: focused ? WeftStyle.accent.opacity(0.14) : .clear, radius: 2)
            .accessibilityLabel(title)
    }
}
