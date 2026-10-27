import XCTest
import Combine
@testable import Weft

final class ScrcpyConfigurationTests: XCTestCase {
    private func resolver(_ paths: Set<String>) -> ScrcpyResolver {
        ScrcpyResolver(environment: [:], home: "/test-home", inspect: { paths.contains($0) ? "3.3.4" : nil })
    }

    func testAutomaticDiscoveryWorksWithoutTerminalPath() throws {
        let tool = try resolver(["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"]).resolve(customPath: nil)
        XCTAssertEqual(tool.path, "/opt/homebrew/bin/scrcpy")
        XCTAssertEqual(tool.version, "3.3.4")
        XCTAssertEqual(try resolver(["/usr/local/bin/scrcpy"]).resolve(customPath: "").path, "/usr/local/bin/scrcpy")
    }

    func testExplicitPathWinsAndExpandsTilde() throws {
        let tool = try resolver(["/opt/homebrew/bin/scrcpy", "/test-home/tools/scrcpy"]).resolve(customPath: "  ~/tools/scrcpy  ")
        XCTAssertEqual(tool.path, "/test-home/tools/scrcpy")
    }

    func testBrokenExplicitPathNeverSilentlyFallsBack() {
        XCTAssertThrowsError(try resolver(["/opt/homebrew/bin/scrcpy"]).resolve(customPath: "/missing/scrcpy"))
        XCTAssertThrowsError(try resolver(["/opt/homebrew/bin/scrcpy"]).resolve(customPath: "scrcpy"))
    }

    func testPathDiscoveryIgnoresRelativeEntriesAndDeduplicates() throws {
        var resolver = resolver(["/custom/bin/scrcpy"])
        resolver.environment = ["PATH": ".::relative:/custom/bin:/custom/bin:/opt/homebrew/bin"]
        XCTAssertEqual(try resolver.resolve(customPath: nil).path, "/custom/bin/scrcpy")
        XCTAssertEqual(resolver.candidates.filter { $0 == "/custom/bin/scrcpy" }.count, 1)
        XCTAssertFalse(resolver.candidates.contains { !$0.hasPrefix("/") })
    }

    func testMissingInstallationReportsActionableError() {
        XCTAssertThrowsError(try resolver([]).resolve(customPath: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains("安装"))
            XCTAssertTrue(error.localizedDescription.contains("scrcpy"))
        }
    }

    private func tool(_ text: String, executable: Bool = true) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("weft scrcpy \(UUID().uuidString)")
        try ("#!/bin/sh\nprintf '%s\\n' '" + text + "'\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file
    }

    func testVersionProbeRejectsWrongOrNonExecutableFiles() throws {
        XCTAssertEqual(ScrcpyResolver.version(at: try tool("scrcpy 3.3.4 <https://github.com/Genymobile/scrcpy>").path), "3.3.4")
        XCTAssertNil(ScrcpyResolver.version(at: try tool("Android Debug Bridge version 1.0.41").path))
        XCTAssertNil(ScrcpyResolver.version(at: try tool("scrcpy invalid").path))
        XCTAssertNil(ScrcpyResolver.version(at: try tool("scrcpy 3.3.4", executable: false).path))
        XCTAssertNil(ScrcpyResolver.version(at: FileManager.default.temporaryDirectory.path))
    }

    @MainActor
    private func scan(_ configuration: ScrcpyConfiguration, action: (() -> Void)? = nil) async {
        let completed = expectation(description: "scrcpy scan finishes")
        let observer = configuration.$scanning.dropFirst().filter { !$0 }.prefix(1).sink { _ in completed.fulfill() }
        if let action { action() } else { configuration.scan() }
        await fulfillment(of: [completed], timeout: 5)
        withExtendedLifetime(observer) {}
    }

    @MainActor
    func testPreferencePersistsAndCanReturnToAutomaticDiscovery() async throws {
        let suite = "weft-scrcpy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = try tool("scrcpy 3.3.4")
        let configuration = ScrcpyConfiguration(defaults: defaults, resolver: resolver([custom.path, "/opt/homebrew/bin/scrcpy"]))
        await scan(configuration, action: { configuration.select(path: custom.path) })
        XCTAssertEqual(try configuration.requireExecutable().path, custom.path)
        let restored = ScrcpyConfiguration(defaults: defaults, resolver: resolver([custom.path]))
        XCTAssertEqual(restored.customPath, custom.path)
        await scan(configuration, action: { configuration.select(path: "") })
        XCTAssertTrue(configuration.isAutomatic)
        XCTAssertEqual(configuration.selected?.path, "/opt/homebrew/bin/scrcpy")
        XCTAssertTrue(ScrcpyConfiguration(defaults: defaults).isAutomatic)
    }

    @MainActor
    func testBrokenPreferenceIsRetainedAfterRescanning() async throws {
        let suite = "weft-scrcpy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/missing/scrcpy", forKey: ScrcpyConfiguration.preferenceKey)
        let configuration = ScrcpyConfiguration(defaults: defaults, resolver: resolver(["/opt/homebrew/bin/scrcpy"]))
        await scan(configuration)
        XCTAssertNil(configuration.selected)
        XCTAssertEqual(configuration.customPath, "/missing/scrcpy")
        XCTAssertFalse(configuration.error.isEmpty)
        XCTAssertThrowsError(try configuration.requireExecutable())
    }
}
