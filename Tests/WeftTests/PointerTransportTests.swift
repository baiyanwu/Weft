import XCTest
import CoreGraphics
import WeftCore
@testable import Weft

final class PointerTransportTests: XCTestCase {
    func testCongestionCoalescesMovementWithoutCrossingButtonScrollOrVisitBarriers() {
        let started = expectation(description: "writer blocked")
        let finished = expectation(description: "writer drained")
        let gate = DispatchSemaphore(value: 0)
        var lines: [String] = []
        let connection = AgentConnection(writer: { line in
            if line == "blocked" { started.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            else { lines.append(line) }
            if line == "done" { finished.fulfill() }
        })
        func frame(_ seq: Int, _ buttons: Int = 0, _ wheel: Int = 0, epoch: Int = 1) -> PointerFrame {
            PointerFrame(epoch: epoch, sequence: seq, position: CGPoint(x: seq, y: 10), buttons: buttons, wheel: wheel, pan: 0)
        }
        connection.send("blocked")
        wait(for: [started], timeout: 2)
        connection.sendPointer(frame(1))
        connection.sendPointer(frame(2))
        connection.sendPointer(frame(3))
        connection.sendPointer(frame(4, 1))
        connection.sendPointer(frame(5, 1))
        connection.sendPointer(frame(6, 1))
        connection.sendPointer(frame(7, 0))
        connection.sendPointer(frame(8, 0, 1))
        connection.sendPointer(frame(9))
        connection.send("release 1")
        connection.send("map-buttons 2 1 original original original back original")
        connection.send("enter-abs 2 0 0 10 100 100 0")
        connection.sendPointer(frame(1, epoch: 2))
        connection.sendPointer(frame(2, epoch: 2))
        connection.sendPointer(frame(3, epoch: 2))
        connection.send("done")
        gate.signal()
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(lines, [frame(1).command, frame(3).command, frame(4, 1).command,
            frame(6, 1).command, frame(7).command, frame(8, 0, 1).command, frame(9).command,
            "release 1", "map-buttons 2 1 original original original back original", "enter-abs 2 0 0 10 100 100 0", frame(1, epoch: 2).command,
            frame(3, epoch: 2).command, "done"])
    }
}
