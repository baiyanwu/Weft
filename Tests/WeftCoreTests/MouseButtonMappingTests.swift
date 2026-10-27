import XCTest
import WeftCore

final class MouseButtonMappingTests: XCTestCase {
    func testPhysicalButtonOrderAndProtocolPayload() {
        XCTAssertEqual(MouseMappingButton.allCases.map(\.mask), [1, 2, 4, 8, 16])
        var mapping = MouseButtonMapping(enabled: true)
        for (button, action) in zip(MouseMappingButton.allCases, [MouseMappingAction.back, .home, .recents, .volumeUp, .volumeDown]) { mapping[button] = action }
        XCTAssertEqual(mapping.command(epoch: 7), "map-buttons 7 1 back home recents volumeUp volumeDown")
        XCTAssertLessThan(mapping.command(epoch: Int.max).utf8.count, 256)
    }
    func testAllAssignmentsRoundTripAndDisablingPreservesThem() throws {
        var mapping = MouseButtonMapping(enabled: true)
        for button in MouseMappingButton.allCases { mapping[button] = .home }
        XCTAssertEqual(try JSONDecoder().decode(MouseButtonMapping.self, from: JSONEncoder().encode(mapping)), mapping)
        mapping.enabled = false
        let restored = try JSONDecoder().decode(MouseButtonMapping.self, from: JSONEncoder().encode(mapping))
        XCTAssertFalse(restored.enabled)
        XCTAssertEqual(restored[.forward], .home)
        XCTAssertTrue(restored.command(epoch: 1).hasPrefix("map-buttons 1 0 "))
    }
    func testChoosingOriginalOnlyResetsOneButton() throws {
        var mapping = MouseButtonMapping(enabled: true)
        mapping[.left] = .home; mapping[.back] = .back; mapping[.left] = .original
        XCTAssertEqual(mapping[.left], .original)
        XCTAssertEqual(mapping[.back], .back)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(mapping)) as? [String: Any])
        XCTAssertNil((json["assignments"] as? [String: String])?["1"])
    }
    func testLegacyDeviceProfileDefaultsToDisabledOriginalButtons() throws {
        let device = DeviceProfile(id: "legacy", name: "Phone", model: "phone", kind: .phone)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) as? [String: Any])
        json.removeValue(forKey: "mouseMapping")
        let restored = try JSONDecoder().decode(DeviceProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, device)
        XCTAssertFalse(restored.mouseMapping.enabled)
        for button in MouseMappingButton.allCases { XCTAssertEqual(restored.mouseMapping[button], .original) }
    }
    func testUnknownAssignmentsFallBackWithoutDroppingKnownMappings() throws {
        let data = Data(#"{"enabled":true,"assignments":{"1":"future-action","4":"back","6":"home"}}"#.utf8)
        let mapping = try JSONDecoder().decode(MouseButtonMapping.self, from: data)
        XCTAssertTrue(mapping.enabled)
        XCTAssertEqual(mapping[.left], .original)
        XCTAssertEqual(mapping[.back], .back)
        XCTAssertEqual(mapping[.forward], .original)
    }
    func testMalformedMappingDoesNotDiscardTheDevice() throws {
        let device = DeviceProfile(id: "kept", name: "Phone", model: "phone", kind: .phone)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) as? [String: Any])
        json["mouseMapping"] = ["invalid"]
        let restored = try JSONDecoder().decode(DeviceProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.id, "kept")
        XCTAssertFalse(restored.mouseMapping.enabled)
    }
}
