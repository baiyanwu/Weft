import XCTest
import CoreGraphics
@testable import WeftCore

final class PointerPathTests: XCTestCase {
    private let bounds = CGRect(x: -1000, y: 100, width: 1001, height: 801)
    private func seam(_ side: Direction, widthMM: Double = 200, offset: Double = 50) -> ScreenSeam {
        ScreenSeam(macSize: CGSize(width: 300, height: 200),
            remote: RemoteScreenGeometry(width: 2401, height: 1601, rotation: 1, widthMM: widthMM, heightMM: 160),
            attachment: EdgeAttachment(direction: side, offset: offset))
    }

    func testPhysicalScaleAndFractionalMovementArePreserved() {
        var path = PointerPath(seam: seam(.below), macBounds: bounds, fraction: 0.5)
        XCTAssertNil(path.move(dx: 4, dy: 8, speed: 1, allowReturn: true))
        XCTAssertEqual(path.position.x, 1214.4, accuracy: 0.000001)
        XCTAssertEqual(path.position.y, 20, accuracy: 0.000001)
        for _ in 0..<10 { _ = path.move(dx: 0.01, dy: 0.01, speed: 1, allowReturn: true) }
        XCTAssertEqual(path.position.x, 1214.76, accuracy: 0.000001)
        XCTAssertEqual(path.position.y, 20.25, accuracy: 0.000001)
    }

    func testAllSidesCarryEntryAndReturnRemainderWithoutADeadZone() throws {
        let inward: [(Direction, CGVector)] = [
            (.below, CGVector(dx: 0, dy: 1)), (.above, CGVector(dx: 0, dy: -1)),
            (.left, CGVector(dx: -1, dy: 0)), (.right, CGVector(dx: 1, dy: 0))]
        for (side, vector) in inward {
            let contact = seam(side)
            var path = PointerPath(seam: contact, macBounds: bounds, fraction: 0.5,
                remainder: CGVector(dx: vector.dx * 5, dy: vector.dy * 5))
            let landing = try XCTUnwrap(path.move(dx: -vector.dx * 8, dy: -vector.dy * 8, speed: 1, allowReturn: true))
            let edge = contact.macPoint(remoteFraction: 0.5, bounds: bounds, inset: 0)
            XCTAssertEqual(landing.x, edge.x - vector.dx * 3, accuracy: 0.000001)
            XCTAssertEqual(landing.y, edge.y - vector.dy * 3, accuracy: 0.000001)
        }
    }

    func testReachingBoundaryDoesNotReturnUntilMovementActuallyCrosses() {
        var path = PointerPath(seam: seam(.below), macBounds: bounds, fraction: 0.5)
        XCTAssertNil(path.move(dx: 0, dy: 20, speed: 1, allowReturn: true))
        XCTAssertNil(path.move(dx: 0, dy: -20, speed: 1, allowReturn: true))
        XCTAssertEqual(path.position.y, 0, accuracy: 0.000001)
        XCTAssertNotNil(path.move(dx: 0, dy: -0.1, speed: 1, allowReturn: true))
    }

    func testHeldDragAndNonContactingEdgeCannotReturn() {
        var drag = PointerPath(seam: seam(.below), macBounds: bounds, fraction: 0.5)
        XCTAssertNil(drag.move(dx: 0, dy: -20, speed: 1, allowReturn: false))
        XCTAssertNotNil(drag.move(dx: 0, dy: -1, speed: 1, allowReturn: true))
        var outside = PointerPath(seam: seam(.below, widthMM: 400, offset: -50), macBounds: bounds, fraction: 0.05)
        XCTAssertNil(outside.move(dx: 0, dy: -20, speed: 1, allowReturn: true))
        XCTAssertEqual(outside.position.y, 0)
    }

    func testEntryConsumesOnlyDistanceToSeamOnOffsetDisplay() {
        let remaining = PointerPath.entryRemainder(direction: .below, previous: CGPoint(x: -500, y: 896),
            bounds: bounds, dx: 10, dy: 10)
        XCTAssertEqual(remaining.dx, 6, accuracy: 0.000001)
        XCTAssertEqual(remaining.dy, 6, accuracy: 0.000001)
        let short = PointerPath.entryRemainder(direction: .right, previous: CGPoint(x: -5, y: 400),
            bounds: bounds, dx: 2, dy: 1)
        XCTAssertEqual(short, .zero)
    }

    func testProtocolCarriesAbsolutePositionAndVisitSequence() {
        let frame = PointerFrame(epoch: 7, sequence: 42, position: CGPoint(x: 123.6, y: 456.2),
            buttons: 3, wheel: -1, pan: 2)
        XCTAssertEqual(frame.command, "pointer 7 42 124 456 3 -1 2")
    }
}
