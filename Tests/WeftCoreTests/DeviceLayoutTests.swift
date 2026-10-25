import XCTest
@testable import WeftCore

final class DeviceLayoutTests: XCTestCase {
    func profile(_ id: String, _ position: Double, display: UInt32 = 0, side: Direction = .below) -> DeviceProfile {
        DeviceProfile(id: id, name: id, model: id, kind: .phone, direction: side, displayID: display, position: position)
    }
    func testIndependentPreferencesPersist() throws {
        var a = profile("a", 0.2); a.speed = 0.7; a.autoConnect = false
        let b = profile("b", 0.8)
        let restored = try JSONDecoder().decode([DeviceProfile].self, from: JSONEncoder().encode([a, b]))
        XCTAssertEqual(restored, [a, b]); XCTAssertEqual(restored[1].speed, 1); XCTAssertTrue(restored[1].autoConnect)
    }
    func testStaleReplyCannotAcquireNewDeviceOrNewVisit() {
        let lease = ControlLease(deviceID: "phone", epoch: 3)
        XCTAssertFalse(lease.accepts(deviceID: "pad", epoch: 3))
        XCTAssertFalse(lease.accepts(deviceID: "phone", epoch: 2))
        XCTAssertTrue(lease.accepts(deviceID: "phone", epoch: 3))
    }
    func testPairingInputRejectsFlagsAndInvalidPorts() {
        XCTAssertTrue(PairingValidation.endpoint("192.168.1.2:37123"))
        XCTAssertTrue(PairingValidation.endpoint("[::1]:37123"))
        XCTAssertFalse(PairingValidation.endpoint("--help"))
        XCTAssertFalse(PairingValidation.endpoint("host:99999"))
        XCTAssertFalse(PairingValidation.endpoint("host:0"))
        XCTAssertFalse(PairingValidation.endpoint("host\nother:123"))
        XCTAssertTrue(PairingValidation.code("012345"))
        XCTAssertFalse(PairingValidation.code("12345x"))
    }
}
