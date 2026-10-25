import XCTest
import CoreGraphics
@testable import WeftCore

final class GeometryTests: XCTestCase {
    let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)

    func testAllDirectionsAndNonzeroDisplayOrigins() {
        let points: [(Direction, CGPoint)] = [
            (.below, CGPoint(x: -720, y: 1099)),
            (.above, CGPoint(x: -720, y: 200)),
            (.left, CGPoint(x: -1440, y: 650)),
            (.right, CGPoint(x: -1, y: 650))
        ]
        for (direction, point) in points {
            XCTAssertTrue(direction.onMacEdge(point, bounds: screen))
            XCTAssertFalse(direction.onMacEdge(CGPoint(x: 100, y: 100), bounds: screen))
            XCTAssertEqual(direction.fraction(point, bounds: screen), 0.5, accuracy: 0.001)
            XCTAssertTrue(screen.contains(direction.macReturn(fraction: 0.5, bounds: screen)))
            XCTAssertFalse(screen.contains(direction.beyondEdge(point, bounds: screen)))
        }
    }

    func testOppositeAndroidEdges() {
        XCTAssertTrue(Direction.below.onAndroidReturnEdge(x: 1500, y: 0, width: 3392, height: 2400))
        XCTAssertTrue(Direction.above.onAndroidReturnEdge(x: 1500, y: 2399, width: 3392, height: 2400))
        XCTAssertTrue(Direction.left.onAndroidReturnEdge(x: 3391, y: 600, width: 3392, height: 2400))
        XCTAssertTrue(Direction.right.onAndroidReturnEdge(x: 0, y: 600, width: 3392, height: 2400))
        XCTAssertFalse(Direction.below.onAndroidReturnEdge(x: 1500, y: 30, width: 3392, height: 2400))
    }

    func testCrossingRequiresEdgeOutwardMovementAndReleasedButtons() {
        XCTAssertFalse(EdgeGate.shouldCross(atEdge: false, outward: 30, buttonsDown: false))
        XCTAssertFalse(EdgeGate.shouldCross(atEdge: true, outward: 0, buttonsDown: false))
        XCTAssertFalse(EdgeGate.shouldCross(atEdge: true, outward: -1, buttonsDown: false))
        XCTAssertFalse(EdgeGate.shouldCross(atEdge: true, outward: 30, buttonsDown: true))
        XCTAssertTrue(EdgeGate.shouldCross(atEdge: true, outward: 0.1, buttonsDown: false))
    }

    func testRotationUsesNewDimensions() {
        let d = Direction.above
        XCTAssertTrue(d.onAndroidReturnEdge(x: 100, y: 3391, width: 2400, height: 3392))
        XCTAssertFalse(d.onAndroidReturnEdge(x: 100, y: 2399, width: 2400, height: 3392))
        XCTAssertEqual(Direction.left.androidFraction(x: 2399, y: 1695.5, width: 2400, height: 3392), 0.5)
    }

    func testEveryDirectionCrossesOnFirstMovementInEitherDirection() {
        let movements: [(Direction, Double, Double)] = [
            (.below, 0, 0.1), (.above, 0, -0.1),
            (.left, -0.1, 0), (.right, 0.1, 0)
        ]
        for (direction, dx, dy) in movements {
            XCTAssertTrue(EdgeGate.shouldCross(atEdge: true,
                outward: direction.outward(dx: dx, dy: dy), buttonsDown: false))
            XCTAssertTrue(EdgeGate.shouldCross(atEdge: true,
                outward: -direction.outward(dx: -dx, dy: -dy), buttonsDown: false))
            // Returning does not block the next entry or require another accumulated push.
            XCTAssertTrue(EdgeGate.shouldCross(atEdge: true,
                outward: direction.outward(dx: dx, dy: dy), buttonsDown: false))
        }
    }
}
