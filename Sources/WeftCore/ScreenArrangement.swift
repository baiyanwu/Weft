import Foundation
import CoreGraphics

/// Native pointer coordinates and the oriented screen size in a common millimetre space.
public struct RemoteScreenGeometry: Codable, Equatable {
    public var width: Int
    public var height: Int
    public var rotation: Int
    public var widthMM: Double
    public var heightMM: Double
    public var estimated: Bool

    public init(width: Int, height: Int, rotation: Int, widthMM: Double, heightMM: Double, estimated: Bool = false) {
        self.width = width; self.height = height; self.rotation = rotation
        self.widthMM = widthMM; self.heightMM = heightMM; self.estimated = estimated
    }
    public var isValid: Bool {
        (2...65536).contains(width) && (2...65536).contains(height) && (0...3).contains(rotation) &&
        widthMM.isFinite && heightMM.isFinite && widthMM > 0 && heightMM > 0
    }
    public var size: CGSize { CGSize(width: widthMM, height: heightMM) }
}

public struct EdgeAttachment: Equatable {
    public let direction: Direction
    /// Left offset for a horizontal seam; top offset for a vertical seam, in millimetres.
    public let offset: Double
    public init(direction: Direction, offset: Double) { self.direction = direction; self.offset = offset }
}

/// The same rectangle and overlap drive both the arrangement view and mouse routing.
public struct ScreenSeam: Equatable {
    public let attachment: EdgeAttachment
    public let macSize: CGSize
    public let remote: RemoteScreenGeometry
    public var direction: Direction { attachment.direction }
    public var horizontal: Bool { direction == .above || direction == .below }
    public var macLength: Double { horizontal ? macSize.width : macSize.height }
    public var remoteLength: Double { horizontal ? remote.widthMM : remote.heightMM }
    public var remotePixelLength: Int { horizontal ? remote.width : remote.height }
    public var lower: Double { max(0, attachment.offset) }
    public var upper: Double { min(macLength, attachment.offset + remoteLength) }
    public var hasContact: Bool { upper > lower }
    public var macSegment: EdgeSegment { EdgeSegment(lower: lower / macLength, upper: upper / macLength) }
    public var remoteSegment: EdgeSegment {
        EdgeSegment(lower: (lower - attachment.offset) / remoteLength, upper: (upper - attachment.offset) / remoteLength)
    }
    public var remoteFrame: CGRect {
        switch direction {
        case .above: return CGRect(x: attachment.offset, y: -remote.heightMM, width: remote.widthMM, height: remote.heightMM)
        case .below: return CGRect(x: attachment.offset, y: macSize.height, width: remote.widthMM, height: remote.heightMM)
        case .left: return CGRect(x: -remote.widthMM, y: attachment.offset, width: remote.widthMM, height: remote.heightMM)
        case .right: return CGRect(x: macSize.width, y: attachment.offset, width: remote.widthMM, height: remote.heightMM)
        }
    }
    public init(macSize: CGSize, remote: RemoteScreenGeometry, attachment: EdgeAttachment) {
        self.macSize = macSize; self.remote = remote; self.attachment = attachment
    }
    public func toRemote(_ macFraction: Double) -> Double {
        (macFraction * macLength - attachment.offset) / remoteLength
    }
    public func toMac(_ remoteFraction: Double) -> Double {
        (attachment.offset + remoteFraction * remoteLength) / macLength
    }
    public var defaultEntryFraction: Double { toRemote((lower + upper) / (2 * macLength)) }

    /// Only the normal axis is inset, so corner proximity never moves the along-edge coordinate.
    public func macPoint(remoteFraction: Double, bounds: CGRect, inset: Double) -> CGPoint {
        let f = min(1, max(0, toMac(remoteFraction)))
        let x = bounds.minX + f * max(0, bounds.width - 1)
        let y = bounds.minY + f * max(0, bounds.height - 1)
        switch direction {
        case .below: return CGPoint(x: x, y: bounds.maxY - 1 - inset)
        case .above: return CGPoint(x: x, y: bounds.minY + inset)
        case .left: return CGPoint(x: bounds.minX + inset, y: y)
        case .right: return CGPoint(x: bounds.maxX - 1 - inset, y: y)
        }
    }
}

public enum ScreenArrangement {
    public static func attachment(direction: Direction, offset: Double?, macSize: CGSize, remoteSize: CGSize) -> EdgeAttachment {
        let horizontal = direction == .above || direction == .below
        let macLength = horizontal ? macSize.width : macSize.height
        let remoteLength = horizontal ? remoteSize.width : remoteSize.height
        // Keep a visible positive contact when orientation or monitor size changes.
        let contact = min(1, min(macLength, remoteLength))
        let value = offset.flatMap { $0.isFinite ? $0 : nil } ?? (macLength - remoteLength) / 2
        return EdgeAttachment(direction: direction, offset: min(macLength - contact, max(contact - remoteLength, value)))
    }

    public static func snap(origin: CGPoint, macSize: CGSize, remote: RemoteScreenGeometry,
                            occupied: [CGRect] = [], alignmentTolerance: Double = 3) -> EdgeAttachment? {
        var best: (EdgeAttachment, Double)?
        for side in Direction.allCases {
            let horizontal = side == .above || side == .below
            let macLength = horizontal ? macSize.width : macSize.height
            let remoteLength = horizontal ? remote.widthMM : remote.heightMM
            var offset = horizontal ? origin.x : origin.y
            let guides = [0, macLength - remoteLength, (macLength - remoteLength) / 2]
            if let guide = guides.min(by: { abs($0 - offset) < abs($1 - offset) }), abs(guide - offset) <= alignmentTolerance {
                offset = guide
            }
            var offsets = [offset]
            for rect in occupied {
                offsets += horizontal ? [rect.minX - remoteLength, rect.maxX] : [rect.minY - remoteLength, rect.maxY]
            }
            for value in offsets {
                let candidate = attachment(direction: side, offset: value, macSize: macSize, remoteSize: remote.size)
                let rect = ScreenSeam(macSize: macSize, remote: remote, attachment: candidate).remoteFrame
                guard !occupied.contains(where: {
                    let overlap = rect.intersection($0)
                    return !overlap.isNull && overlap.width > 0.001 && overlap.height > 0.001
                }) else { continue }
                let distance = pow(rect.minX - origin.x, 2) + pow(rect.minY - origin.y, 2)
                if best == nil || distance < best!.1 { best = (candidate, distance) }
            }
        }
        return best?.0
    }
}
