import XCTest
import WeftCore
@testable import Weft

final class MouseMappingPersistenceTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    override func setUp() {
        super.setUp()
        suite = "io.baiyanwu.weft.mapping-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil; suite = nil
        super.tearDown()
    }
    private func store() throws -> DeviceStore {
        let profiles = [DeviceProfile(id: "phone", name: "Phone", model: "phone", kind: .phone), DeviceProfile(id: "tablet", name: "Tablet", model: "tablet", kind: .tablet)]
        defaults.set(try JSONEncoder().encode(profiles), forKey: "deviceProfiles.v2")
        let store = DeviceStore(defaults: defaults)
        store.paused = true
        return store
    }
    func testPerDeviceAssignmentsAndEnableStateSurviveReload() throws {
        let store = try store()
        store.update("phone") { $0.mouseMapping[.back] = .home; $0.mouseMapping.enabled = true }
        store.update("tablet") { $0.mouseMapping[.middle] = .recents }
        let reloaded = DeviceStore(defaults: defaults)
        let phone = try XCTUnwrap(reloaded.profile("phone"))
        let tablet = try XCTUnwrap(reloaded.profile("tablet"))
        XCTAssertTrue(phone.mouseMapping.enabled)
        XCTAssertEqual(phone.mouseMapping[.back], .home)
        XCTAssertEqual(phone.mouseMapping[.middle], .original)
        XCTAssertFalse(tablet.mouseMapping.enabled)
        XCTAssertEqual(tablet.mouseMapping[.middle], .recents)
        XCTAssertEqual(tablet.mouseMapping[.back], .original)
    }
    func testDisableAndRestoreOriginalPreserveOtherAssignments() throws {
        let store = try store()
        store.update("phone") { $0.mouseMapping[.left] = .home; $0.mouseMapping[.back] = .back; $0.mouseMapping.enabled = true }
        store.update("phone") { $0.mouseMapping.enabled = false; $0.mouseMapping[.left] = .original }
        let mapping = try XCTUnwrap(DeviceStore(defaults: defaults).profile("phone")).mouseMapping
        XCTAssertFalse(mapping.enabled)
        XCTAssertEqual(mapping[.left], .original)
        XCTAssertEqual(mapping[.back], .back)
    }
    func testDeletingAndReaddingDeviceDoesNotResurrectMappings() throws {
        let store = try store()
        store.update("phone") { $0.mouseMapping.enabled = true; $0.mouseMapping[.forward] = .volumeUp }
        store.remove("phone")
        store.add(DeviceEndpoint(serial: "phone", hardwareID: "phone", model: "phone", kind: .phone, usb: true, authorization: "device"))
        let readded = try XCTUnwrap(store.profile("phone"))
        XCTAssertFalse(readded.mouseMapping.enabled)
        XCTAssertEqual(readded.mouseMapping[.forward], .original)
    }
}
