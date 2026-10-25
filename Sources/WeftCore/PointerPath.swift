import Foundation
import CoreGraphics

/// One continuous position. Android feedback never changes the commanded trajectory.
public struct PointerPath {
    public let seam: ScreenSeam
    public let macBounds: CGRect
    public private(set) var position: CGPoint

    public var scaleX: Double { Double(seam.remote.width - 1) * seam.macSize.width / (seam.remote.widthMM * max(1, macBounds.width - 1)) }
    public var scaleY: Double { Double(seam.remote.height - 1) * seam.macSize.height / (seam.remote.heightMM * max(1, macBounds.height - 1)) }
    public var fraction: Double {
        seam.direction.androidFraction(x: position.x, y: position.y,
            width: Double(seam.remote.width), height: Double(seam.remote.height))
    }

    public init(seam: ScreenSeam, macBounds: CGRect, fraction: Double, remainder: CGVector = .zero) {
        self.seam = seam; self.macBounds = macBounds
        let f = min(1, max(0, fraction))
        switch seam.direction {
        case .below: position = CGPoint(x: f * Double(seam.remote.width - 1), y: 0)
        case .above: position = CGPoint(x: f * Double(seam.remote.width - 1), y: Double(seam.remote.height - 1))
        case .left: position = CGPoint(x: Double(seam.remote.width - 1), y: f * Double(seam.remote.height - 1))
        case .right: position = CGPoint(x: 0, y: f * Double(seam.remote.height - 1))
        }
        position = clamped(CGPoint(x: position.x + remainder.dx * scaleX, y: position.y + remainder.dy * scaleY))
    }

    /// Returns the Mac landing point, including the unconsumed part of this movement.
    public mutating func move(dx: Double, dy: Double, speed: Double, allowReturn: Bool) -> CGPoint? {
        let delta = CGVector(dx: dx * speed, dy: dy * speed)
        let next = CGPoint(x: position.x + delta.dx * scaleX, y: position.y + delta.dy * scaleY)
        let distance: Double, nextDistance: Double
        switch seam.direction {
        case .below: distance = position.y; nextDistance = next.y
        case .above: distance = Double(seam.remote.height - 1) - position.y; nextDistance = Double(seam.remote.height - 1) - next.y
        case .left: distance = Double(seam.remote.width - 1) - position.x; nextDistance = Double(seam.remote.width - 1) - next.x
        case .right: distance = position.x; nextDistance = next.x
        }
        if allowReturn && nextDistance < 0 && nextDistance < distance {
            let t = max(0, min(1, distance / (distance - nextDistance)))
            let intersection = CGPoint(x: position.x + (next.x - position.x) * t,
                                       y: position.y + (next.y - position.y) * t)
            let f = seam.direction.androidFraction(x: intersection.x, y: intersection.y,
                width: Double(seam.remote.width), height: Double(seam.remote.height))
            if seam.remoteSegment.contains(f) {
                let edge = seam.macPoint(remoteFraction: f, bounds: macBounds, inset: 0)
                position = clamped(intersection)
                return CGPoint(x: min(macBounds.maxX - 1, max(macBounds.minX, edge.x + delta.dx * (1 - t))),
                               y: min(macBounds.maxY - 1, max(macBounds.minY, edge.y + delta.dy * (1 - t))))
            }
        }
        position = clamped(next)
        return nil
    }

    /// Consume only the distance to the seam; carry the rest into Android.
    public static func entryRemainder(direction: Direction, previous: CGPoint, bounds: CGRect,
                                      dx: Double, dy: Double) -> CGVector {
        let outward = direction.outward(dx: dx, dy: dy)
        guard outward > 0 else { return .zero }
        let distance: Double
        switch direction {
        case .below: distance = bounds.maxY - 1 - previous.y
        case .above: distance = previous.y - bounds.minY
        case .left: distance = previous.x - bounds.minX
        case .right: distance = bounds.maxX - 1 - previous.x
        }
        let remaining = max(0, min(1, 1 - max(0, distance) / outward))
        return CGVector(dx: dx * remaining, dy: dy * remaining)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(Double(seam.remote.width - 1), max(0, point.x)),
                y: min(Double(seam.remote.height - 1), max(0, point.y)))
    }
}

public struct PointerFrame {
    public let epoch: Int
    public let sequence: Int
    public let x: Int, y: Int, buttons: Int, wheel: Int, pan: Int

    public init(epoch: Int, sequence: Int, position: CGPoint, buttons: Int, wheel: Int, pan: Int) {
        self.epoch = epoch; self.sequence = sequence
        x = Int(position.x.rounded()); y = Int(position.y.rounded())
        self.buttons = buttons; self.wheel = wheel; self.pan = pan
    }
    public var command: String { "pointer \(epoch) \(sequence) \(x) \(y) \(buttons) \(wheel) \(pan)" }
}
