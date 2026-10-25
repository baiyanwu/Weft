import Foundation
import CoreGraphics

public enum Direction: String, CaseIterable, Codable {
    case below, above, left, right

    public var label: String {
        switch self {
        case .below: return "下方 ↓"
        case .above: return "上方 ↑"
        case .left: return "左侧 ←"
        case .right: return "右侧 →"
        }
    }

    // All rectangles and points use Quartz coordinates: origin at the top left.
    public func onMacEdge(_ p: CGPoint, bounds b: CGRect, tolerance: Double = 2) -> Bool {
        guard p.x >= b.minX - 1, p.x <= b.maxX + 1,
              p.y >= b.minY - 1, p.y <= b.maxY + 1 else { return false }
        switch self {
        case .below: return p.y >= b.maxY - tolerance
        case .above: return p.y <= b.minY + tolerance
        case .left: return p.x <= b.minX + tolerance
        case .right: return p.x >= b.maxX - tolerance
        }
    }

    public func outward(dx: Double, dy: Double) -> Double {
        switch self {
        case .below: return dy
        case .above: return -dy
        case .left: return -dx
        case .right: return dx
        }
    }

    public func fraction(_ p: CGPoint, bounds b: CGRect) -> Double {
        let value: Double
        switch self {
        case .below, .above: value = (p.x - b.minX) / max(1, b.width - 1)
        case .left, .right: value = (p.y - b.minY) / max(1, b.height - 1)
        }
        return min(1, max(0, value))
    }

    public func macReturn(fraction: Double, bounds b: CGRect, inset: Double = 22) -> CGPoint {
        let t = min(1, max(0, fraction))
        let x = min(b.maxX - inset, max(b.minX + inset, b.minX + t * (b.width - 1)))
        let y = min(b.maxY - inset, max(b.minY + inset, b.minY + t * (b.height - 1)))
        switch self {
        case .below: return CGPoint(x: x, y: b.maxY - inset)
        case .above: return CGPoint(x: x, y: b.minY + inset)
        case .left: return CGPoint(x: b.minX + inset, y: y)
        case .right: return CGPoint(x: b.maxX - inset, y: y)
        }
    }

    public func beyondEdge(_ p: CGPoint, bounds b: CGRect) -> CGPoint {
        switch self {
        case .below: return CGPoint(x: p.x, y: b.maxY + 3)
        case .above: return CGPoint(x: p.x, y: b.minY - 3)
        case .left: return CGPoint(x: b.minX - 3, y: p.y)
        case .right: return CGPoint(x: b.maxX + 3, y: p.y)
        }
    }

    public func onAndroidReturnEdge(x: Double, y: Double, width: Double, height: Double, tolerance: Double = 3) -> Bool {
        switch self {
        case .below: return y <= tolerance
        case .above: return y >= height - 1 - tolerance
        case .left: return x >= width - 1 - tolerance
        case .right: return x <= tolerance
        }
    }

    public func androidFraction(x: Double, y: Double, width: Double, height: Double) -> Double {
        switch self {
        case .below, .above: return min(1, max(0, x / max(1, width - 1)))
        case .left, .right: return min(1, max(0, y / max(1, height - 1)))
        }
    }
}

public enum EdgeGate {
    public static func shouldCross(atEdge: Bool, outward: Double, buttonsDown: Bool) -> Bool {
        atEdge && outward > 0 && !buttonsDown
    }
}
