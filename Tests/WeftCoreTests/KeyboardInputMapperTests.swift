import XCTest
@testable import WeftCore

final class KeyboardInputMapperTests: XCTestCase {
    func testCommandCopyPasteDoesNotLeakAndroidMetaBetweenChords() {
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping())
        _ = mapper.begin(modifiers: 0, capsLock: false)
        XCTAssertEqual(mapper.modifiersChanged(0x08, capsLock: false).last?.modifiers, 0)
        let copy = mapper.keyDown(8, repeat: false).last
        XCTAssertEqual(copy?.modifiers, 1); XCTAssertEqual(copy?.usages, [0x06])
        XCTAssertEqual(mapper.keyUp(8).last?.modifiers, 0)
        let paste = mapper.keyDown(9, repeat: false).last
        XCTAssertEqual(paste?.modifiers, 1); XCTAssertEqual(paste?.usages, [0x19])
        _ = mapper.keyUp(9)
        XCTAssertEqual(mapper.modifiersChanged(0, capsLock: false).last?.modifiers, 0)
    }

    func testUnmappedChordRestoresOriginalModifierAfterMappedChord() {
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping())
        _ = mapper.begin(modifiers: 8, capsLock: false)
        _ = mapper.keyDown(8, repeat: false); _ = mapper.keyUp(8)
        let raw = mapper.keyDown(7, repeat: false).last
        XCTAssertEqual(raw?.modifiers, 8); XCTAssertEqual(raw?.usages, [0x1b])
    }

    func testOverlappingMappingsToSameKeyReleaseOnlyAfterBothSources() {
        let target = KeyboardMappingTarget(action: .key,
            shortcut: KeyboardKeyCombination(keyCode: 11, keyLabel: "B"))
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping(rules: [
            KeyboardMappingRule(shortcut: KeyboardKeyCombination(keyCode: 0, keyLabel: "A"), target: target),
            KeyboardMappingRule(shortcut: KeyboardKeyCombination(keyCode: 8, keyLabel: "C"), target: target)
        ]))
        _ = mapper.begin(modifiers: 0, capsLock: false)
        _ = mapper.keyDown(0, repeat: false); _ = mapper.keyDown(8, repeat: false)
        XCTAssertEqual(mapper.keyUp(0).last?.usages, [0x05])
        XCTAssertEqual(mapper.keyUp(8).last?.usages, [])
    }

    func testModifierOnlyChordIsDeliveredBeforeItsFirstRelease() {
        let source = KeyboardKeyCombination(keyCode: 0, modifiers: [.control, .shift], keyLabel: "A")
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping(rules: [
            KeyboardMappingRule(shortcut: source, target: KeyboardMappingTarget(action: .home))
        ]))
        _ = mapper.begin(modifiers: 0, capsLock: false)
        _ = mapper.modifiersChanged(1, capsLock: false)
        _ = mapper.modifiersChanged(3, capsLock: false)
        let releaseShift = mapper.modifiersChanged(1, capsLock: false)
        XCTAssertEqual(releaseShift.map(\.modifiers), [3, 1])
        XCTAssertEqual(mapper.modifiersChanged(0, capsLock: false).last?.modifiers, 0)
    }

    func testDisabledChordConsumesItsSourceAndModifiers() {
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping(rules: [
            KeyboardMappingRule(shortcut: KeyboardKeyCombination(keyCode: 8, modifiers: .command, keyLabel: "C"),
                target: KeyboardMappingTarget(action: .disabled))
        ]))
        _ = mapper.begin(modifiers: 8, capsLock: false)
        let frame = mapper.keyDown(8, repeat: false).last
        XCTAssertEqual(frame?.modifiers, 0); XCTAssertEqual(frame?.usages, [])
        XCTAssertNil(frame?.action)
    }

    func testVolumeRepeatsButHomeAndOrdinaryKeysDoNotDuplicatePresses() {
        let rules = [(UInt16(0), KeyboardMappingAction.volumeUp), (UInt16(8), .home)].map { code, action in
            KeyboardMappingRule(shortcut: KeyboardKeyCombination(keyCode: code, keyLabel: "Key"),
                target: KeyboardMappingTarget(action: action))
        }
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping(rules: rules))
        _ = mapper.begin(modifiers: 0, capsLock: false)
        _ = mapper.keyDown(0, repeat: false)
        XCTAssertEqual(mapper.keyDown(0, repeat: true).last?.action, .volumeUp)
        _ = mapper.keyUp(0); _ = mapper.keyDown(8, repeat: false)
        XCTAssertTrue(mapper.keyDown(8, repeat: true).isEmpty)
        _ = mapper.keyUp(8); _ = mapper.keyDown(9, repeat: false)
        XCTAssertTrue(mapper.keyDown(9, repeat: true).isEmpty)
    }

    func testReleaseClearsHeldKeysAndMappedModifiers() {
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping())
        _ = mapper.begin(modifiers: 8, capsLock: true)
        _ = mapper.keyDown(8, repeat: false)
        let frame = mapper.release()
        XCTAssertEqual(frame.modifiers, 0); XCTAssertTrue(frame.usages.isEmpty)
        XCTAssertTrue(frame.capsLock); XCTAssertTrue(mapper.heldKeyCodes.isEmpty)
        XCTAssertEqual(frame.command(epoch: 7, sequence: 9), "keyboard 7 9 0 1 none -")
    }

    func testRawEscapeAndRightAltRemainAvailableToAndroid() {
        var mapper = KeyboardInputMapper(mapping: KeyboardMapping(rules: []))
        _ = mapper.begin(modifiers: 0x40, capsLock: false)
        let frame = mapper.keyDown(53, repeat: false).last
        XCTAssertEqual(frame?.modifiers, 0x40); XCTAssertEqual(frame?.usages, [0x29])
    }
}
