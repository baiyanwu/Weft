import SwiftUI

struct WeftCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(configuration.isOn ? WeftStyle.accent.opacity(0.22) : Color.primary.opacity(0.02))
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(configuration.isOn ? WeftStyle.accent : WeftStyle.mutedText.opacity(0.7), lineWidth: 1.2)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(WeftStyle.accentText)
                    }
                }.frame(width: 18, height: 18)
                configuration.label
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) {
                    configuration.label
                }.toggleStyle(.checkbox)
            }
    }
}
