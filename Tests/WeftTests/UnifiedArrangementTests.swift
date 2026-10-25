import AppKit
import XCTest
import WeftCore
@testable import Weft

final class UnifiedArrangementTests: XCTestCase {
    private func store() -> DeviceStore {
        let store = DeviceStore(preview: true)
        store.screens = [MacScreen(id: CGMainDisplayID(), name: "Mac", bounds: CGRect(x: 0, y: 0, width: 1500, height: 1000),
            sizeMM: CGSize(width: 300, height: 200))]
        store.profiles = [DeviceProfile(id: "phone", name: "Phone", model: "phone", kind: .phone, direction: .right),
            DeviceProfile(id: "pad", name: "Pad", model: "pad", kind: .tablet)]
        store.statuses = ["phone": DeviceStatus(phase: .ready), "pad": DeviceStatus(phase: .ready)]
        return store
    }

    func testBothDeviceTypesReceiveGeometryAndUseTheSamePortalMapping() {
        let store = store()
        let geometry: [String: Any] = ["width": 2400, "height": 1600, "rotation": 1,
            "layoutWidthMM": 200, "layoutHeightMM": 120, "estimatedSize": false]
        for id in ["phone", "pad"] { store.receiveScreenGeometry(id, geometry) }
        XCTAssertEqual(Set(store.placements.map(\.deviceID)), Set(["phone", "pad"]))
        XCTAssertEqual(Set(store.mouse.portals.map(\.deviceID)), Set(["phone", "pad"]))
        for portal in store.mouse.portals {
            let fraction = portal.seam.defaultEntryFraction
            XCTAssertTrue(portal.seam.remoteSegment.contains(fraction))
            XCTAssertEqual(portal.seam.toRemote(portal.seam.toMac(fraction)), fraction, accuracy: 0.000001)
        }
    }

    func testChangingOnlyTheDeviceTypeCannotChangePlacementOrEntryCoordinates() {
        let store = store()
        for index in store.profiles.indices {
            store.profiles[index].screenGeometry = RemoteScreenGeometry(width: 2400, height: 1600, rotation: 1,
                widthMM: 200, heightMM: 120)
        }
        store.refreshPortals()
        let placements = store.placements
        let seams = store.mouse.portals.map(\.seam)
        for index in store.profiles.indices {
            store.profiles[index].kind = store.profiles[index].kind == .phone ? .tablet : .phone
        }
        store.refreshPortals()
        XCTAssertEqual(store.placements, placements)
        XCTAssertEqual(store.mouse.portals.map(\.seam), seams)
    }
}
