import SwiftUI
import AppKit
import WeftCore

enum WeftStyle {
    static let accent = adaptive(light: (0.24, 0.66, 0.53), dark: (0.48, 0.81, 0.67))
    static let accentText = adaptive(light: (0.13, 0.43, 0.35), dark: (0.64, 0.89, 0.77))
    static let secondaryText = adaptive(light: (0.33, 0.37, 0.40), dark: (0.74, 0.78, 0.76))
    static let mutedText = adaptive(light: (0.41, 0.45, 0.48), dark: (0.64, 0.69, 0.67))
    static let warningText = adaptive(light: (0.61, 0.35, 0.12), dark: (0.98, 0.73, 0.43))
    static let border = Color.primary.opacity(0.10)
    static let canvas = adaptive(light: (0.95, 0.985, 0.97), dark: (0.13, 0.17, 0.15))
    static let tile = adaptive(light: (0.985, 0.995, 0.99), dark: (0.18, 0.22, 0.20))
    static let selection = LinearGradient(colors: [accent.opacity(0.12), accent.opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let wash = LinearGradient(colors: [accent.opacity(0.05), accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let logo: NSImage = Bundle.main.url(forResource: "logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "computermouse", accessibilityDescription: "weft")!

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

struct BrandMark: View {
    var size: CGFloat = 46
    var body: some View { Image(nsImage: WeftStyle.logo).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size) }
}
struct StatusDot: View {
    var phase: ConnectionPhase
    var body: some View {
        Circle().fill(phase == .ready ? Color.green : phase == .connecting ? .orange : .secondary.opacity(0.5))
            .frame(width: 8, height: 8).accessibilityLabel(phase == .ready ? "已连接" : "未连接")
    }
}
struct DeviceGlyph: View {
    let kind: DeviceKind
    var size: CGFloat = 25
    var body: some View { Image(systemName: kind == .tablet ? "ipad" : "iphone").font(.system(size: size, weight: .regular)).frame(width: size + 8) }
}
struct Surface<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16)
            .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .background(highlighted ? WeftStyle.wash : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? WeftStyle.accent.opacity(0.18) : WeftStyle.border, lineWidth: 1))
    }
}

struct WeftButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat? = nil
    var fontSize: CGFloat = 13
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, height == nil ? 8 : 0)
            .frame(height: height)
            .foregroundStyle(enabled ? Color.primary : WeftStyle.mutedText)
            .background(prominent ? WeftStyle.accent.opacity(!enabled ? 0.08 : configuration.isPressed ? 0.30 : 0.19) : Color.primary.opacity(configuration.isPressed ? 0.07 : 0.015), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(prominent ? .clear : WeftStyle.border, lineWidth: 1))
    }
}
struct PreferenceRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            content
        }.frame(minHeight: 32)
    }
}
