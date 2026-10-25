import XCTest
import CoreGraphics
import WeftCore
@testable import Weft

final class MacCursorCaptureTests: XCTestCase {
    final class Desktop {
        var visible = true
        var connected = true
        var hideCount = 0
        var visibleMoves: [CGPoint] = []
        var position = CGPoint(x: 500, y: 400)
        var failure: String?
        var operations: MacCursorCapture.Operations {
            .init(prepare: { self.failure == "prepare" ? .notImplemented : .success },
                  hide: {
                      guard self.failure != "hide" else { return .failure }
                      self.hideCount += 1; self.visible = false; return .success
                  }, associate: { connected in
                      if !connected && self.failure == "associate" { return .failure }
                      self.connected = connected; return .success
                  }, warp: { point in
                      guard self.failure != "warp" else { return .failure }
                      if self.visible { self.visibleMoves.append(point) }
                      self.position = point; return .success
                  }, show: {
                      self.hideCount -= 1; self.visible = true; return .success
                  })
        }
    }

    func testFourEdgesAndSegmentedSecondaryDisplayNeverWarpWhileVisible() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let segment = EdgeSegment(lower: 0.5, upper: 1)
        for direction in Direction.allCases {
            let desktop = Desktop(), fraction = segment.toMac(0.25)
            let capture = MacCursorCapture(operations: desktop.operations)
            let parked = direction.macReturn(fraction: fraction, bounds: screen, inset: 1)
            XCTAssertEqual(capture.capture(at: parked), .success)
            XCTAssertTrue(direction.onMacEdge(desktop.position, bounds: screen))
            XCTAssertFalse(desktop.visible)
            XCTAssertFalse(desktop.connected)
            let returned = direction.macReturn(fraction: fraction, bounds: screen)
            XCTAssertEqual(capture.restore(at: returned), .success)
            XCTAssertEqual(desktop.position, returned)
            XCTAssertTrue(desktop.visible)
            XCTAssertTrue(desktop.connected)
            XCTAssertTrue(desktop.visibleMoves.isEmpty)
            XCTAssertEqual(desktop.hideCount, 0)
        }
    }

    func testFailedEntryRestoresLocalPointerWithoutLeakingHideCount() {
        for failure in ["prepare", "hide", "associate", "warp"] {
            let desktop = Desktop(); desktop.failure = failure
            let capture = MacCursorCapture(operations: desktop.operations)
            XCTAssertNotEqual(capture.capture(at: CGPoint(x: 0, y: 400)), .success)
            XCTAssertFalse(capture.isCaptured, failure)
            XCTAssertTrue(desktop.visible, failure)
            XCTAssertTrue(desktop.connected, failure)
            XCTAssertEqual(desktop.hideCount, 0, failure)
        }
    }

    func testDuplicateEntryAndReleaseKeepHideCountBalanced() {
        let desktop = Desktop(), point = CGPoint(x: 0, y: 400)
        let capture = MacCursorCapture(operations: desktop.operations)
        for _ in 0..<10 {
            XCTAssertEqual(capture.capture(at: point), .success)
            XCTAssertEqual(capture.capture(at: point), .invalidOperation)
            XCTAssertEqual(desktop.hideCount, 1)
            capture.restore(); capture.restore()
            XCTAssertEqual(desktop.hideCount, 0)
        }
    }
}
