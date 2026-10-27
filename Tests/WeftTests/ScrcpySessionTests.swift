import XCTest
import WeftCore
@testable import Weft

private final class FakeScrcpyProcess: ScrcpyProcessRunning {
    var request: ScrcpyLaunchRequest?
    var completion: ((Int32, String) -> Void)?
    var stops = 0
    var failsToStart = false
    func start(_ request: ScrcpyLaunchRequest, completion: @escaping (Int32, String) -> Void) throws {
        if failsToStart { throw BridgeError.message("test launch error") }
        self.request = request; self.completion = completion
    }
    func stop() { stops += 1 }
}

final class ScrcpySessionTests: XCTestCase {
    @MainActor
    private func flushCallbacks() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func start(_ manager: ScrcpySessionManager, id: String = "phone", serial: String = "usb-phone") {
        manager.start(id: id, serial: serial, name: "设备 \(id)", executable: "/tools/scrcpy", adb: "/sdk/adb")
    }

    func testLaunchRequestKeepsArgumentsLiteralAndUsesSelectedADB() {
        let serial = "192.0.2.1:37111", name = "我的平板 ' $(example)"
        let request = ScrcpyLaunchRequest(executable: "/some tools/scrcpy", adb: "/android sdk/adb", serial: serial, name: name,
                                          environment: ["PATH": "/usr/bin:/bin", "ADB": "/wrong/adb", "ANDROID_SERIAL": "wrong",
                                                        "SCRCPY_SERVER_PATH": "/wrong/server", "EXTRA": "kept"])
        XCTAssertEqual(request.arguments, ["--serial", serial, "--window-title", name + " · weft"])
        XCTAssertEqual(request.environment["ADB"], "/android sdk/adb")
        XCTAssertEqual(request.environment["EXTRA"], "kept")
        XCTAssertNil(request.environment["ANDROID_SERIAL"])
        XCTAssertNil(request.environment["SCRCPY_SERVER_PATH"])
        XCTAssertFalse(request.arguments.contains("--no-control"))
        XCTAssertFalse(request.arguments.contains("--no-audio"))
    }

    @MainActor
    func testOneSessionPerDeviceAllowsMultipleDevices() {
        var processes: [FakeScrcpyProcess] = []
        let manager = ScrcpySessionManager { let process = FakeScrcpyProcess(); processes.append(process); return process }
        start(manager); start(manager); start(manager, id: "tablet", serial: "192.0.2.2:43210")
        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(manager.state("phone"), .running)
        XCTAssertEqual(manager.state("tablet"), .running)
        XCTAssertEqual(processes[1].request?.arguments[1], "192.0.2.2:43210")
    }

    @MainActor
    func testNormalWindowCloseReturnsToIdleAndAllowsRestart() async {
        let process = FakeScrcpyProcess(), manager = ScrcpySessionManager(makeProcess: { process })
        start(manager); process.completion?(0, "")
        await flushCallbacks()
        XCTAssertEqual(manager.state("phone"), .idle)
        start(manager)
        XCTAssertEqual(manager.state("phone"), .running)
    }

    @MainActor
    func testFailedExitShowsUsefulErrorAndCanBeRetried() async {
        let process = FakeScrcpyProcess(), manager = ScrcpySessionManager(makeProcess: { process })
        start(manager)
        process.completion?(1, "INFO: starting\nERROR: Device is unauthorized\nINFO: cleanup\n")
        await flushCallbacks()
        guard case .failed(let message) = manager.state("phone") else { return XCTFail("Missing failure state") }
        XCTAssertTrue(message.contains("Device is unauthorized"))
        start(manager)
        XCTAssertEqual(manager.state("phone"), .running)
    }

    @MainActor
    func testManualStopIsIdempotentAndNeverReportedAsFailure() async {
        let process = FakeScrcpyProcess(), manager = ScrcpySessionManager(makeProcess: { process })
        start(manager); manager.stop("phone"); manager.stop("phone")
        XCTAssertEqual(process.stops, 1)
        XCTAssertEqual(manager.state("phone"), .stopping)
        process.completion?(15, "ERROR: interrupted")
        await flushCallbacks()
        XCTAssertEqual(manager.state("phone"), .idle)
    }

    @MainActor
    func testRemovedSessionIgnoresOldCallbackAfterRestart() async {
        var processes: [FakeScrcpyProcess] = []
        let manager = ScrcpySessionManager { let process = FakeScrcpyProcess(); processes.append(process); return process }
        start(manager); manager.forget("phone"); start(manager)
        processes[0].completion?(1, "ERROR: late old failure")
        await flushCallbacks()
        XCTAssertEqual(processes[0].stops, 1)
        XCTAssertEqual(manager.state("phone"), .running)
        XCTAssertEqual(processes[1].stops, 0)
    }

    @MainActor
    func testDiscoveryStopsOnlyTheDisconnectedEndpoint() {
        var processes: [FakeScrcpyProcess] = []
        let manager = ScrcpySessionManager { let process = FakeScrcpyProcess(); processes.append(process); return process }
        start(manager); start(manager, id: "tablet", serial: "wifi-tablet")
        manager.reconcile(endpoints: [endpoint("phone", serial: "other-transport"), endpoint("tablet", serial: "wifi-tablet")])
        XCTAssertEqual(processes[0].stops, 1)
        XCTAssertEqual(processes[1].stops, 0)
        XCTAssertEqual(manager.state("tablet"), .running)
    }

    @MainActor
    func testLaunchFailureDoesNotLeaveAnActiveSession() {
        let process = FakeScrcpyProcess(); process.failsToStart = true
        let manager = ScrcpySessionManager(makeProcess: { process })
        start(manager)
        XCTAssertFalse(manager.state("phone").isActive)
        XCTAssertTrue(manager.state("phone").message.contains("test launch error"))
        process.failsToStart = false; start(manager)
        XCTAssertEqual(manager.state("phone"), .running)
    }

    private func endpoint(_ id: String, serial: String, usb: Bool = true) -> DeviceEndpoint {
        DeviceEndpoint(serial: serial, hardwareID: id, model: "Test", kind: .phone, usb: usb, authorization: "device")
    }

    @MainActor
    func testMirroringRemainsIndependentOfMousePauseAndDeviceDisconnect() {
        let process = FakeScrcpyProcess(), manager = ScrcpySessionManager(makeProcess: { process })
        let store = DeviceStore(preview: true, mirroring: manager)
        store.endpoints = [endpoint("preview-phone", serial: "usb-phone"), endpoint("preview-phone", serial: "wifi-phone", usb: false)]
        store.sessions["preview-phone"] = DeviceSession()
        store.sessions["preview-phone"]?.endpoint = "wifi-phone"
        XCTAssertEqual(store.mirroringEndpoint("preview-phone")?.serial, "wifi-phone")
        start(manager, id: "preview-phone")
        store.disconnect("preview-phone"); store.togglePause()
        XCTAssertEqual(process.stops, 0)
        XCTAssertEqual(manager.state("preview-phone"), .running)
        store.remove("preview-phone")
        XCTAssertEqual(process.stops, 1)
        XCTAssertEqual(manager.state("preview-phone"), .idle)
    }

    func testRealProcessReceivesLiteralArgumentsAndCapturesFailureOutput() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("weft scrcpy process \(UUID().uuidString)")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" \"$ADB\"\nprintf '%s\\n' 'ERROR: expected test failure' >&2\nexit 7\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        defer { try? FileManager.default.removeItem(at: file) }
        let completed = expectation(description: "real child exits with captured output")
        let process = ScrcpyProcess()
        let request = ScrcpyLaunchRequest(executable: file.path, adb: "/sdk with spaces/adb", serial: "192.0.2.1:43210", name: "平板 ' $(literal)")
        try process.start(request) { code, output in
            XCTAssertEqual(code, 7)
            XCTAssertTrue(output.contains("平板 ' $(literal) · weft"))
            XCTAssertTrue(output.contains("192.0.2.1:43210"))
            XCTAssertTrue(output.contains("/sdk with spaces/adb"))
            XCTAssertTrue(output.contains("ERROR: expected test failure"))
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
        process.stop()
    }
}
