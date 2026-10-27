import SwiftUI
import WeftCore

struct MouseButtonDiagram: View {
    @Binding var selection: MouseMappingButton

    var body: some View {
        VStack(spacing: 9) {
            topView.frame(width: 204, height: 228)
            VStack(alignment: .leading, spacing: 3) {
                Text("侧视图").font(.system(size: 10)).foregroundStyle(.secondary)
                sideView.frame(height: 49)
            }
            Text("滚轮按下为中键").font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var topView: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                MouseTopOutline().fill(WeftStyle.tile)
                MouseTopOutline().fill(WeftStyle.wash)
                MouseTopOutline().stroke(WeftStyle.accent.opacity(0.42), lineWidth: 1.2)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.51, y: size.height * 0.02))
                    path.addLine(to: CGPoint(x: size.width * 0.51, y: size.height * 0.49))
                    path.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.37))
                    path.addQuadCurve(to: CGPoint(x: size.width * 0.89, y: size.height * 0.37),
                                      control: CGPoint(x: size.width * 0.51, y: size.height * 0.44))
                }.stroke(WeftStyle.accent.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: 9)
                    .fill(WeftStyle.accent.opacity(selection == .middle ? 0.38 : 0.16))
                    .frame(width: 23, height: 57)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(WeftStyle.accent.opacity(0.65), lineWidth: 1))
                    .position(x: size.width * 0.51, y: size.height * 0.23)
                ForEach([MouseMappingButton.left, .right, .middle]) { button in
                    numberButton(button)
                        .position(x: size.width * (button == .left ? 0.33 : button == .right ? 0.70 : 0.51),
                                  y: size.height * (button == .middle ? 0.25 : 0.29))
                }
                ForEach([MouseMappingButton.back, .forward]) { button in
                    Button { selection = button } label: {
                        Capsule().fill(WeftStyle.accent.opacity(selection == button ? 0.85 : 0.17))
                            .overlay(Capsule().stroke(WeftStyle.accent.opacity(0.45), lineWidth: 1))
                            .frame(width: 9, height: 27)
                    }.buttonStyle(.plain)
                        .position(x: size.width * 0.14, y: size.height * (button == .forward ? 0.47 : 0.61))
                        .accessibilityLabel("选择\(button.title)")
                }
                Image(systemName: "computermouse").font(.system(size: 16))
                    .foregroundStyle(WeftStyle.accent.opacity(0.23))
                    .position(x: size.width * 0.52, y: size.height * 0.80)
            }
        }
    }

    private var sideView: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                MouseSideOutline().fill(WeftStyle.tile)
                MouseSideOutline().fill(WeftStyle.wash)
                MouseSideOutline().stroke(WeftStyle.accent.opacity(0.48), lineWidth: 1)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.04, y: size.height * 0.81))
                    path.addQuadCurve(to: CGPoint(x: size.width * 0.96, y: size.height * 0.81),
                                      control: CGPoint(x: size.width * 0.50, y: size.height * 0.68))
                }.stroke(WeftStyle.accent.opacity(0.28), lineWidth: 1)
                ForEach([MouseMappingButton.back, .forward]) { button in
                    numberButton(button)
                        .position(x: size.width * (button == .back ? 0.45 : 0.63), y: size.height * 0.56)
                }
            }
        }
    }

    private func numberButton(_ button: MouseMappingButton) -> some View {
        Button { selection = button } label: {
            MouseButtonNumber(button: button, selected: selection == button)
        }.buttonStyle(.plain)
            .help("\(button.title) · \(button.subtitle)")
            .accessibilityLabel("选择\(button.title)")
            .accessibilityAddTraits(selection == button ? .isSelected : [])
    }
}

struct MouseButtonNumber: View {
    let button: MouseMappingButton
    let selected: Bool

    var body: some View {
        Text("\(button.rawValue)").font(.system(size: 12, weight: .semibold))
            .frame(width: 27, height: 27)
            .foregroundStyle(selected ? Color(nsColor: .textBackgroundColor) : Color.primary)
            .background(selected ? WeftStyle.accent : Color.primary.opacity(0.035), in: Circle())
            .overlay(Circle().stroke(selected ? .clear : WeftStyle.border, lineWidth: 1))
    }
}

private struct MouseTopOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        path.move(to: point(0.51, 0.02))
        path.addCurve(to: point(0.90, 0.35), control1: point(0.77, 0.02), control2: point(0.87, 0.12))
        path.addLine(to: point(0.96, 0.69))
        path.addCurve(to: point(0.51, 0.98), control1: point(1.00, 0.89), control2: point(0.78, 0.98))
        path.addCurve(to: point(0.09, 0.68), control1: point(0.24, 0.98), control2: point(0.04, 0.88))
        path.addLine(to: point(0.15, 0.35))
        path.addCurve(to: point(0.51, 0.02), control1: point(0.18, 0.12), control2: point(0.28, 0.02))
        path.closeSubpath()
        return path
    }
}

private struct MouseSideOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        path.move(to: point(0.04, 0.82))
        path.addCurve(to: point(0.48, 0.10), control1: point(0.15, 0.29), control2: point(0.29, 0.04))
        path.addCurve(to: point(0.96, 0.80), control1: point(0.67, 0.15), control2: point(0.86, 0.59))
        path.addLine(to: point(0.91, 0.93))
        path.addLine(to: point(0.09, 0.93))
        path.closeSubpath()
        return path
    }
}
