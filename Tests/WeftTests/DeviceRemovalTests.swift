import XCTest
import AppKit
import WeftCore
@testable import Weft

final class DeviceRemovalTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "io.baiyanwu.weft.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func profile(_ id: String) -> DeviceProfile {
        var device = DeviceProfile(id: id, name: id, model: id, kind: .phone)
        device.screenGeometry = RemoteScreenGeometry(width: 1080, height: 2400, rotation: 0,
            widthMM: 70, heightMM: 155)
        return device
    }

    private func endpoint(_ id: String, serial: String? = nil, usb: Bool = true) -> DeviceEndpoint {
        DeviceEndpoint(serial: serial ?? id, hardwareID: id, model: id, kind: .phone,
                       usb: usb, authorization: "device")
    }

    private func store(_ profiles: [DeviceProfile]) throws -> DeviceStore {
        defaults.set(try JSONEncoder().encode(profiles), forKey: "deviceProfiles.v2")
        let store = DeviceStore(defaults: defaults)
        store.screens = [MacScreen(id: CGMainDisplayID(), name: "Test display",
            bounds: CGRect(x: 0, y: 0, width: 1500, height: 1000), sizeMM: CGSize(width: 300, height: 200))]
        store.refreshPortals()
        return store
    }

    func testRemovalClearsRuntimeAndSavedStateAndPreservesOtherDevice() throws {
        defaults.set("phone", forKey: "lastControlledDevice")
        let survivor = profile("tablet")
        let store = try store([profile("phone"), survivor])
        let removedSession = DeviceSession(), survivorSession = DeviceSession()
        removedSession.connection.onEvent = { _ in XCTFail("A removed channel must not deliver events") }
        removedSession.connection.onFailure = { _ in XCTFail("A removed channel must not deliver failures") }
        store.sessions = ["phone": removedSession, "tablet": survivorSession]
        store.statuses = ["phone": DeviceStatus(phase: .ready, transport: "USB"),
                          "tablet": DeviceStatus(phase: .ready, transport: "Wi-Fi")]
        store.suspended = ["phone"]
        store.requested = ["phone", "tablet"]
        store.refreshPortals()
        var notified = false
        store.onStateChange = { notified = true }

        store.remove("phone")

        XCTAssertEqual(store.profiles, [survivor])
        XCTAssertEqual(store.selectedID, "tablet")
        XCTAssertNil(store.sessions["phone"])
        XCTAssertTrue(store.sessions["tablet"] === survivorSession)
        XCTAssertNil(removedSession.connection.onEvent)
        XCTAssertNil(removedSession.connection.onFailure)
        XCTAssertNil(store.statuses["phone"])
        XCTAssertEqual(store.status("tablet").phase, .ready)
        XCTAssertEqual(store.connectedCount, 1)
        XCTAssertFalse(store.suspended.contains("phone"))
        XCTAssertEqual(store.requested, ["tablet"])
        XCTAssertEqual(store.placements.map(\.deviceID), ["tablet"])
        XCTAssertFalse(store.mouse.portals.contains { $0.deviceID == "phone" })
        XCTAssertNil(store.lastControlledID)
        XCTAssertNil(defaults.string(forKey: "lastControlledDevice"))
        XCTAssertTrue(notified)
        XCTAssertEqual(DeviceStore(defaults: defaults).profiles, [survivor])
    }

    func testDeletingLastDeviceSurvivesReloadDiscoveryAndLateCallbacks() throws {
        let store = try store([profile("phone")])
        store.sessions["phone"] = DeviceSession()
        store.statuses["phone"] = DeviceStatus(phase: .connecting)

        store.remove("phone")
        store.receive("phone", ["type": "ready", "protocol": 4, "pointerMode": "absolute"])
        store.failed("phone", "late connection failure")

        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertTrue(store.statuses.isEmpty)
        XCTAssertNil(store.selectedID)
        let saved = try XCTUnwrap(defaults.data(forKey: "deviceProfiles.v2"))
        XCTAssertTrue(try JSONDecoder().decode([DeviceProfile].self, from: saved).isEmpty)

        let restored = DeviceStore(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertFalse(restored.firstImport)
        restored.discovered([endpoint("phone"), endpoint("phone", serial: "192.0.2.1:5555", usb: false)])
        restored.reconcile()

        XCTAssertTrue(restored.profiles.isEmpty)
        XCTAssertTrue(restored.sessions.isEmpty)
        XCTAssertTrue(restored.statuses.isEmpty)
        XCTAssertTrue(restored.placements.isEmpty)
        XCTAssertEqual(restored.available.map(\.hardwareID), ["phone"])
    }

    func testDeletingManuallyAddedDeviceEndsFirstImport() {
        let store = DeviceStore(defaults: defaults)
        store.paused = true
        XCTAssertTrue(store.firstImport)
        store.add(endpoint("phone"))

        store.remove("phone")
        store.discovered([endpoint("phone"), endpoint("tablet")])

        XCTAssertFalse(store.firstImport)
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertTrue(store.requested.isEmpty)
        XCTAssertTrue(DeviceStore(defaults: defaults).profiles.isEmpty)
    }

    func testReaddingDeletedDeviceUsesDefaultsAndForgetsLegacySettings() throws {
        var device = profile("phone")
        device.name = "Custom name"; device.direction = .left; device.speed = 1.4
        device.displayID = 42; device.autoConnect = false; device.autoCross = false
        defaults.set("192.0.2.1:5555", forKey: "deviceSerial")
        defaults.set("left", forKey: "direction")
        defaults.set(1.4, forKey: "speed")
        defaults.set(42, forKey: "displayID")
        let store = try store([device, profile("tablet")])
        store.paused = true
        store.endpoints = [endpoint("phone", serial: "192.0.2.1:5555", usb: false)]

        store.remove("phone")

        for key in ["deviceSerial", "direction", "speed", "displayID"] {
            XCTAssertNil(defaults.object(forKey: key), "Stale preference: \(key)")
        }
        store.add(endpoint("phone"))
        let added = try XCTUnwrap(store.profile("phone"))
        XCTAssertEqual(added.name, "phone")
        XCTAssertEqual(added.direction, .below)
        XCTAssertEqual(added.speed, 1)
        XCTAssertEqual(added.displayID, 0)
        XCTAssertTrue(added.autoConnect)
        XCTAssertTrue(added.autoCross)
    }

    func testDeletingAnotherDevicePreservesSelectionHistoryAndCurrentPage() throws {
        defaults.set("phone", forKey: "lastControlledDevice")
        let store = try store([profile("phone"), profile("tablet")])
        store.section = .general

        store.remove("tablet")

        XCTAssertEqual(store.selectedID, "phone")
        XCTAssertEqual(store.lastControlledID, "phone")
        XCTAssertEqual(defaults.string(forKey: "lastControlledDevice"), "phone")
        XCTAssertEqual(store.section, .general)
    }
}
