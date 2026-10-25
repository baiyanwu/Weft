import XCTest
import Combine
import WeftCore
@testable import Weft

final class ADBTests: XCTestCase {
    private func resolver(available: Set<String>) -> ADBResolver {
        ADBResolver(environment: [:], home: "/test-home", bundledPath: "/app/adb",
                    inspect: { available.contains($0) ? "37.0.1" : nil })
    }

    func testExplicitPathWinsOverInstalledAndBundledVersions() throws {
        let resolver = resolver(available: ["/custom/adb", "/test-home/Library/Android/sdk/platform-tools/adb", "/app/adb"])
        let result = try resolver.resolve(customPath: "/custom/adb")
        XCTAssertEqual(result.path, "/custom/adb")
        XCTAssertEqual(result.source, .custom)
    }

    func testBrokenExplicitPathDoesNotFallBack() {
        let resolver = resolver(available: ["/test-home/Library/Android/sdk/platform-tools/adb", "/app/adb"])
        XCTAssertThrowsError(try resolver.resolve(customPath: "/missing/adb")) { error in
            XCTAssertTrue(error.localizedDescription.contains("用户指定"))
        }
    }

    func testInstalledVersionWinsOverBundledVersionWithoutPreference() throws {
        let resolver = resolver(available: ["/test-home/Library/Android/sdk/platform-tools/adb", "/app/adb"])
        XCTAssertEqual(try resolver.resolve(customPath: nil).source, .scanned)
    }

    func testBundledVersionIsUsedWhenNoInstallationIsUsable() throws {
        let result = try resolver(available: ["/app/adb"]).resolve(customPath: nil)
        XCTAssertEqual(result.path, "/app/adb")
        XCTAssertEqual(result.source, .bundled)
    }

    func testSDKEnvironmentVariablesAreScanned() throws {
        var resolver = resolver(available: ["/sdk-root/platform-tools/adb", "/sdk-home/platform-tools/adb", "/app/adb"])
        resolver.environment = ["ANDROID_SDK_ROOT": "/sdk-root", "ANDROID_HOME": "/sdk-home"]
        XCTAssertEqual(try resolver.resolve(customPath: nil).path, "/sdk-root/platform-tools/adb")
        resolver.environment.removeValue(forKey: "ANDROID_SDK_ROOT")
        XCTAssertEqual(try resolver.resolve(customPath: nil).path, "/sdk-home/platform-tools/adb")
    }

    func testPathIsScannedAndUnusableInstallationIsSkipped() throws {
        var resolver = resolver(available: ["/tools/bin/adb", "/app/adb"])
        resolver.environment = ["PATH": "/broken/bin:/tools/bin"]
        XCTAssertEqual(try resolver.resolve(customPath: "").path, "/tools/bin/adb")
    }

    func testHomebrewIsScanned() throws {
        let resolver = resolver(available: ["/opt/homebrew/bin/adb", "/app/adb"])
        XCTAssertEqual(try resolver.resolve(customPath: nil).path, "/opt/homebrew/bin/adb")
    }

    func testExplicitTildePathIsExpanded() throws {
        let result = try resolver(available: ["/test-home/tools/adb"]).resolve(customPath: "  ~/tools/adb  ")
        XCTAssertEqual(result.path, "/test-home/tools/adb")
        XCTAssertEqual(result.source, .custom)
    }

    func testRelativePathEntriesAreIgnored() {
        var resolver = resolver(available: ["./adb", "adb"])
        resolver.environment = ["PATH": ".::relative"]
        XCTAssertThrowsError(try resolver.resolve(customPath: nil))
    }

    func testNoUsableExecutableReportsAnError() {
        XCTAssertThrowsError(try resolver(available: []).resolve(customPath: nil))
    }

    private func tool(_ script: String, executable: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weft-adb-\(UUID().uuidString)")
        try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testVersionProbeAcceptsADBAndRejectsOtherExecutables() throws {
        let valid = try tool("printf '%s\\n' 'Android Debug Bridge version 1.0.41' 'Version 37.0.1-test'")
        let invalid = try tool("printf '%s\\n' 'some other tool'")
        let failing = try tool("exit 1")
        let nonExecutable = try tool("exit 0", executable: false)
        XCTAssertEqual(ADB.version(at: valid.path), "37.0.1-test")
        XCTAssertNil(ADB.version(at: invalid.path))
        XCTAssertNil(ADB.version(at: failing.path))
        XCTAssertNil(ADB.version(at: nonExecutable.path))
        XCTAssertNil(ADB.version(at: FileManager.default.temporaryDirectory.path))
    }

    func testVersionProbeTimesOutInsteadOfHangingTheScan() async throws {
        let hanging = try tool("exec /bin/sleep 10")
        let (version, elapsed) = await Task.detached(priority: .utility) {
            let start = Date()
            let version = ADB.version(at: hanging.path)
            return (version, Date().timeIntervalSince(start))
        }.value
        XCTAssertNil(version)
        XCTAssertLessThan(elapsed, 5)
    }

    func testBuiltAppContainsWorkingUniversalADBFallback() throws {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/adb").path
        let version = try XCTUnwrap(ADB.version(at: path))
        XCTAssertTrue(version.hasPrefix("37.0.1"))
        let resolver = ADBResolver(environment: [:], home: "/no-sdk", bundledPath: path,
                                   inspect: { $0 == path ? ADB.version(at: $0) : nil })
        XCTAssertEqual(try resolver.resolve(customPath: nil).source, .bundled)
        XCTAssertNotNil(Bundle.main.url(forResource: "ADB-NOTICE", withExtension: "txt"))
    }

    @MainActor
    private func scan(_ configuration: ADBConfiguration, action: (() -> Void)? = nil) async {
        let finished = expectation(description: "ADB scan completes")
        let observer = configuration.$scanning.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        if let action { action() } else { configuration.scan() }
        await fulfillment(of: [finished], timeout: 5)
        withExtendedLifetime(observer) {}
    }

    @MainActor
    func testPreferencePersistsAndRestoringAutomaticIgnoresEnvironmentOverride() async throws {
        let suite = "weft-adb-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = try tool("exit 0"), bundled = try tool("exit 0")
        let resolver = ADBResolver(environment: ["WEFT_ADB": custom.path], home: "/no-sdk", bundledPath: bundled.path,
                                  inspect: { [custom.path, bundled.path].contains($0) ? "test" : nil })
        let configuration = ADBConfiguration(defaults: defaults, resolver: resolver)
        XCTAssertEqual(configuration.customPath, custom.path)
        await scan(configuration)
        XCTAssertEqual(try configuration.requireExecutable().source, .custom)

        await scan(configuration, action: { configuration.select(path: "") })
        XCTAssertTrue(configuration.isAutomatic)
        XCTAssertEqual(try configuration.requireExecutable().source, .bundled)
        let reloaded = ADBConfiguration(defaults: defaults, resolver: resolver)
        XCTAssertTrue(reloaded.isAutomatic)

        await scan(reloaded, action: { reloaded.select(path: custom.path) })
        XCTAssertEqual(defaults.string(forKey: ADBConfiguration.preferenceKey), custom.path)
        XCTAssertEqual(try reloaded.requireExecutable().source, .custom)
    }

    @MainActor
    func testBrokenSavedPreferenceRemainsSelectedAfterRescan() async throws {
        let suite = "weft-adb-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/missing/adb", forKey: ADBConfiguration.preferenceKey)
        let configuration = ADBConfiguration(defaults: defaults, resolver: resolver(available: ["/app/adb"]))
        await scan(configuration)
        XCTAssertNil(configuration.selected)
        XCTAssertTrue(configuration.error.contains("用户指定"))
        XCTAssertEqual(configuration.customPath, "/missing/adb")
        XCTAssertThrowsError(try configuration.requireExecutable())
    }

    @MainActor
    func testDeviceDiscoveryShowsFinalErrorForBrokenSavedPreference() async throws {
        let suite = "weft-adb-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/missing/adb", forKey: ADBConfiguration.preferenceKey)
        let configuration = ADBConfiguration(defaults: defaults, resolver: resolver(available: ["/app/adb"]))
        let store = DeviceStore(defaults: defaults)
        store.observeADBConfiguration(configuration)
        let errorShown = expectation(description: "Discovery receives final ADB error")
        let observer = store.$discoveryError.filter { $0.contains("用户指定") }.prefix(1).sink { _ in errorShown.fulfill() }
        await scan(configuration)
        await fulfillment(of: [errorShown], timeout: 1)
        XCTAssertEqual(store.discoveryError, configuration.error)
        withExtendedLifetime(observer) {}
    }

    @MainActor
    func testChangingADBKeepsManualConnectionIntentAndRespectsSuspendedDevices() throws {
        let suite = "weft-adb-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(defaults: defaults)
        store.firstImport = false
        var manual = DeviceProfile(id: "manual", name: "Manual", model: "Test", kind: .phone)
        manual.autoConnect = false
        var suspended = manual; suspended.id = "suspended"
        var offline = manual; offline.id = "offline"
        var retrying = manual; retrying.id = "retrying"
        var exhausted = manual; exhausted.id = "exhausted"
        store.profiles = [manual, suspended, offline, retrying, exhausted]
        store.statuses = [manual.id: DeviceStatus(phase: .ready), suspended.id: DeviceStatus(phase: .ready),
                          retrying.id: DeviceStatus(phase: .failed), exhausted.id: DeviceStatus(phase: .failed)]
        store.suspended.insert(suspended.id)
        store.sessions[manual.id] = DeviceSession()
        let retrySession = DeviceSession(); retrySession.retry.beginRound()
        _ = retrySession.retry.admitAttempt(); retrySession.retry.recordFailure()
        store.sessions[retrying.id] = retrySession
        let exhaustedSession = DeviceSession(); exhaustedSession.retry.beginRound()
        for _ in 0..<3 { _ = exhaustedSession.retry.admitAttempt() }
        exhaustedSession.retry.recordFailure(); store.sessions[exhausted.id] = exhaustedSession

        store.adbConfigurationChanged()

        XCTAssertTrue(store.requested.contains(manual.id))
        XCTAssertTrue(store.requested.contains(retrying.id))
        XCTAssertFalse(store.requested.contains(exhausted.id))
        XCTAssertFalse(store.requested.contains(suspended.id))
        XCTAssertFalse(store.requested.contains(offline.id))
    }
}
