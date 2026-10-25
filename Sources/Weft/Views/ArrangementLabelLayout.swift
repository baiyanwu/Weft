import CoreGraphics
import WeftCore

/// Labels use canvas space without changing the physical screen rectangles.
enum ArrangementLabelLayout {
    struct Item {
        let id: String
        let screen: CGRect
        let labelSize: CGSize
        let outside: Bool
        let preferredSide: Direction
    }

    static func place(_ items: [Item], in size: CGSize) -> [String: CGRect] {
        var placed: [String: CGRect] = [:]
        let screenRects = items.map { $0.screen.insetBy(dx: -5, dy: -5) }
        for item in items where item.outside {
            let label = CGSize(width: min(item.labelSize.width, max(1, size.width - 16)),
                               height: min(item.labelSize.height, max(1, size.height - 16)))
            let sides = [item.preferredSide] + Direction.allCases.filter { $0 != item.preferredSide }
            var candidates: [(CGRect, Double)] = []
            for (rank, side) in sides.enumerated() {
                for shift in [0.0, -36, 36, -72, 72, -108, 108] {
                    let origin: CGPoint
                    switch side {
                    case .above: origin = CGPoint(x: item.screen.midX - label.width / 2 + shift, y: item.screen.minY - label.height - 12)
                    case .below: origin = CGPoint(x: item.screen.midX - label.width / 2 + shift, y: item.screen.maxY + 12)
                    case .left: origin = CGPoint(x: item.screen.minX - label.width - 12, y: item.screen.midY - label.height / 2 + shift)
                    case .right: origin = CGPoint(x: item.screen.maxX + 12, y: item.screen.midY - label.height / 2 + shift)
                    }
                    let rect = CGRect(x: min(size.width - label.width - 8, max(8, origin.x)),
                                      y: min(size.height - label.height - 8, max(8, origin.y)),
                                      width: label.width, height: label.height)
                    let overlap = (screenRects + placed.values.map { $0.insetBy(dx: -5, dy: -5) }).reduce(0.0) { sum, obstacle in
                        let intersection = rect.intersection(obstacle)
                        return sum + (intersection.isNull ? 0 : intersection.width * intersection.height)
                    }
                    let distance = hypot(rect.midX - item.screen.midX, rect.midY - item.screen.midY)
                    candidates.append((rect, overlap * 1000 + distance + Double(rank) * 12 + abs(shift) * 0.1))
                }
            }
            placed[item.id] = candidates.min { $0.1 < $1.1 }?.0
        }
        return placed
    }

    static func anchor(on rect: CGRect, toward point: CGPoint) -> CGPoint {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        let ratio = max(abs(dx) / max(1, rect.width / 2), abs(dy) / max(1, rect.height / 2))
        guard ratio > 0 else { return CGPoint(x: rect.midX, y: rect.midY) }
        return CGPoint(x: rect.midX + dx / ratio, y: rect.midY + dy / ratio)
    }
}
