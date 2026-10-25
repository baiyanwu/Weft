import AppKit
import SwiftUI

// Match CoinMonitor's native popover backdrop, keeping foreground text opaque.
struct MenuPanelBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            MenuPanelVisualEffect().overlay(WeftStyle.canvas.opacity(0.15))
        }
    }
}

private struct MenuPanelVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> MenuPanelVisualEffectView { MenuPanelVisualEffectView(frame: .zero) }
    func updateNSView(_ view: MenuPanelVisualEffectView, context: Context) { view.configure() }
}

private final class MenuPanelVisualEffectView: NSVisualEffectView {
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); configure() }
    required init?(coder: NSCoder) { super.init(coder: coder); configure() }
    func configure() {
        material = .popover; blendingMode = .behindWindow; state = .active; isEmphasized = false
        window?.isOpaque = false; window?.backgroundColor = .clear
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
