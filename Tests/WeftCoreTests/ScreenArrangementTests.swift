import XCTest
import CoreGraphics
@testable import WeftCore

final class ScreenArrangementTests: XCTestCase {
    private let mac = CGSize(width: 300, height: 200)
    private let pad = RemoteScreenGeometry(width: 2400, height: 1600, rotation: 1, widthMM: 200, heightMM: 120)

    func testSmallerPadUsesOnlyPhysicalContactAndDoesNotStretchTheEdge() {
        let seam = ScreenSeam(macSize: mac, remote: pad, attachment: EdgeAttachment(direction: .below, offset: 50))
        XCTAssertEqual(seam.remoteFrame, CGRect(x: 50, y: 200, width: 200, height: 120))
        XCTAssertFalse(seam.macSegment.contains(0.1))
        XCTAssertFalse(seam.macSegment.contains(0.9))
        XCTAssertTrue(seam.macSegment.contains(0.25))
        // 75 mm on Mac is 25 mm from the pad's left edge, not 25% of the pad.
        XCTAssertEqual(seam.toRemote(0.25), 0.125, accuracy: 0.000001)
        XCTAssertEqual(seam.toMac(0.125), 0.25, accuracy: 0.000001)
    }

    func testLargerOffsetPadCannotReturnFromItsNonContactingEdge() {
        let larger = RemoteScreenGeometry(width: 4000, height: 2400, rotation: 1, widthMM: 400, heightMM: 240)
        let seam = ScreenSeam(macSize: mac, remote: larger, attachment: EdgeAttachment(direction: .above, offset: -50))
        XCTAssertEqual(seam.macSegment, EdgeSegment())
        XCTAssertEqual(seam.remoteSegment.lower, 0.125, accuracy: 0.000001)
        XCTAssertEqual(seam.remoteSegment.upper, 0.875, accuracy: 0.000001)
        XCTAssertFalse(seam.remoteSegment.contains(0.1))
        XCTAssertFalse(seam.remoteSegment.contains(0.9))
        XCTAssertEqual(seam.toRemote(0), 0.125, accuracy: 0.000001)
        XCTAssertEqual(seam.toRemote(1), 0.875, accuracy: 0.000001)
    }

    func testAllFourSidesPreserveTheAlongEdgePositionAcrossDifferentPixelScales() {
        let bounds = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        for side in Direction.allCases {
            let seam = ScreenSeam(macSize: mac, remote: pad, attachment: EdgeAttachment(direction: side, offset: 30))
            for fraction in [0.25, 0.5, 0.7] where seam.macSegment.contains(fraction) {
                let remote = seam.toRemote(fraction)
                let pixel = (remote * Double(seam.remotePixelLength - 1)).rounded()
                let restored = seam.toMac(pixel / Double(seam.remotePixelLength - 1))
                XCTAssertEqual(restored, fraction, accuracy: 0.0005)
                let point = seam.macPoint(remoteFraction: remote, bounds: bounds, inset: 1)
                XCTAssertEqual(side.fraction(point, bounds: bounds), fraction, accuracy: 0.000001)
                XCTAssertTrue(side.onMacEdge(point, bounds: bounds))
            }
        }
    }

    func testReturnNearCornerDoesNotAddAlongEdgePadding() {
        let seam = ScreenSeam(macSize: mac, remote: pad, attachment: EdgeAttachment(direction: .below, offset: 0))
        let bounds = CGRect(x: 100, y: -200, width: 1000, height: 800)
        let point = seam.macPoint(remoteFraction: seam.toRemote(0.001), bounds: bounds, inset: 1)
        XCTAssertEqual(point.x, 100.999, accuracy: 0.000001)
        XCTAssertEqual(point.y, 598, accuracy: 0.000001)
    }

    func testDragSnapsToEachEdgeAndKeepsAlongEdgeOffset() throws {
        let origins: [(Direction, CGPoint)] = [(.above, CGPoint(x: 40, y: -120)),
            (.below, CGPoint(x: 40, y: 200)), (.left, CGPoint(x: -200, y: 40)), (.right, CGPoint(x: 300, y: 40))]
        for (side, origin) in origins {
            let attachment = try XCTUnwrap(ScreenArrangement.snap(origin: origin, macSize: mac, remote: pad, alignmentTolerance: 0))
            XCTAssertEqual(attachment.direction, side)
            XCTAssertEqual(attachment.offset, 40, accuracy: 0.000001)
        }
    }

    func testPointContactIsNotAPortalAndSnappedDevicesDoNotOverlap() throws {
        let corner = ScreenSeam(macSize: mac, remote: pad, attachment: EdgeAttachment(direction: .below, offset: 300))
        XCTAssertFalse(corner.hasContact)
        let occupied = CGRect(x: 40, y: 200, width: 200, height: 120)
        let attachment = try XCTUnwrap(ScreenArrangement.snap(origin: occupied.origin, macSize: mac, remote: pad, occupied: [occupied]))
        let seam = ScreenSeam(macSize: mac, remote: pad, attachment: attachment)
        let overlap = seam.remoteFrame.intersection(occupied)
        XCTAssertTrue(seam.hasContact)
        XCTAssertTrue(overlap.isNull || overlap.width == 0 || overlap.height == 0)
    }

    func testGeometryAndNegativeOffsetPersistAndLegacyProfilesStillDecode() throws {
        var device = DeviceProfile(id: "pad", name: "pad", model: "tablet", kind: .tablet)
        device.screenGeometry = pad; device.edgeOffsetMM = -40
        let data = try JSONEncoder().encode(device)
        XCTAssertEqual(try JSONDecoder().decode(DeviceProfile.self, from: data), device)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "screenGeometry"); legacy.removeValue(forKey: "edgeOffsetMM")
        let restored = try JSONDecoder().decode(DeviceProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.screenGeometry); XCTAssertNil(restored.edgeOffsetMM)
        XCTAssertEqual(restored.direction, device.direction)
    }
}
