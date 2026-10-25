import XCTest
import WeftCore
@testable import Weft

final class ConnectionRetryTests: XCTestCase {
    private final class Channel: AgentTransport {
        var onEvent: (([String: Any]) -> Void)?
        var onFailure: ((String) -> Void)?
        var starts = 0
        var stops = 0
        func start(serial: String) { starts += 1 }
        func send(_ line: String) {}
        func stop() { stops += 1 }
    }
    private var suite: String!
    private var defaults: UserDefaults!
    override func setUp() {
        suite = "io.baiyanwu.weft.retry-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil; suite = nil
    }
    private func fixture(autoConnect: Bool) throws -> (DeviceStore, Channel, DeviceSession) {
        let device = DeviceProfile(id: "device", name: "Device", model: "test", kind: .phone, autoConnect: autoConnect)
        defaults.set(try JSONEncoder().encode([device]), forKey: "deviceProfiles.v2")
        let store = DeviceStore(defaults: defaults)
        let channel = Channel(), session = DeviceSession(connection: channel)
        store.sessions[device.id] = session
        store.endpoints = [DeviceEndpoint(serial: "device", hardwareID: device.id, model: "test", kind: .phone,
            usb: true, authorization: "device")]
        return (store, channel, session)
    }
    private func rescan(_ store: DeviceStore, session: DeviceSession) {
        for _ in 0..<10 {
            session.attemptAt = -100
            store.reconcile()
        }
    }

    func testManualConnectionWithAutoConnectOffStartsOneBoundedRound() throws {
        let (store, channel, session) = try fixture(autoConnect: false)
        store.beginConnectionRound("device")
        store.reconcile()
        XCTAssertEqual(channel.starts, 1)
        XCTAssertFalse(session.automaticAttempt)
        XCTAssertFalse(store.requested.contains("device"))
        for attempt in 1...ConnectionRetryState.maximumAttempts {
            XCTAssertEqual(channel.starts, attempt)
            channel.onFailure?("registration failed")
            session.attemptAt = -100
            store.reconcile()
        }
        rescan(store, session: session)
        XCTAssertEqual(channel.starts, ConnectionRetryState.maximumAttempts)
        XCTAssertEqual(store.status("device").phase, .failed)
        XCTAssertTrue(store.status("device").retryStopped)
        XCTAssertTrue(store.status("device").message.contains("已停止重连"))
        XCTAssertTrue(store.status("device").message.contains("registration failed"))
    }

    func testAutomaticRoundStopsAtLimitUntilUserStartsAnotherRound() throws {
        let (store, channel, session) = try fixture(autoConnect: true)
        store.reconcile()
        for _ in 0..<ConnectionRetryState.maximumAttempts {
            channel.onFailure?("initialization failed")
            session.attemptAt = -100
            store.reconcile()
        }
        rescan(store, session: session)
        XCTAssertEqual(channel.starts, ConnectionRetryState.maximumAttempts)
        XCTAssertTrue(session.retry.isExhausted)

        store.endpoints = []
        store.reconcile()
        XCTAssertTrue(store.status("device").retryStopped)
        store.endpoints = [DeviceEndpoint(serial: "device", hardwareID: "device", model: "test", kind: .phone,
            usb: true, authorization: "device")]
        rescan(store, session: session)
        XCTAssertEqual(channel.starts, ConnectionRetryState.maximumAttempts)

        store.beginConnectionRound("device")
        store.reconcile()
        XCTAssertEqual(session.retry.attempts, 1)
        XCTAssertFalse(session.retry.isExhausted)
        for _ in 0..<ConnectionRetryState.maximumAttempts {
            channel.onFailure?("failed again")
            session.attemptAt = -100
            store.reconcile()
        }
        rescan(store, session: session)
        XCTAssertEqual(channel.starts, ConnectionRetryState.maximumAttempts * 2)
        XCTAssertTrue(store.status("device").retryStopped)
    }

    func testDisablingAutoConnectCancelsAnAutomaticAttemptAndPendingRequests() throws {
        let (store, channel, session) = try fixture(autoConnect: true)
        store.reconcile()
        XCTAssertTrue(session.automaticAttempt)
        store.requested.insert("device")
        store.update("device") { $0.autoConnect = false }
        rescan(store, session: session)
        XCTAssertFalse(store.requested.contains("device"))
        XCTAssertFalse(session.automaticAttempt)
        XCTAssertEqual(channel.stops, 1)
        XCTAssertEqual(channel.starts, 1)
    }

    func testDisablingAutoConnectAllowsOneExistingManualAttemptToFinish() throws {
        let (store, channel, session) = try fixture(autoConnect: true)
        store.requested.insert("device")
        store.reconcile()
        store.update("device") { $0.autoConnect = false }
        XCTAssertEqual(channel.stops, 0)
        XCTAssertEqual(store.status("device").phase, .connecting)
        channel.onFailure?("failed once")
        rescan(store, session: session)
        XCTAssertEqual(channel.starts, 1)
    }

    func testDisablingAutoConnectDoesNotDisconnectAReadyDevice() throws {
        let (store, channel, _) = try fixture(autoConnect: true)
        store.reconcile()
        channel.onEvent?(["type": "ready", "protocol": 3, "pointerMode": "absolute"])
        store.update("device") { $0.autoConnect = false }
        XCTAssertEqual(store.status("device").phase, .ready)
        XCTAssertEqual(channel.stops, 0)
    }

    func testEnabledAutoConnectCanRetryAfterFailure() throws {
        let (store, channel, session) = try fixture(autoConnect: true)
        store.reconcile()
        channel.onFailure?("temporary error")
        session.attemptAt = -100
        store.reconcile()
        XCTAssertEqual(channel.starts, 2)
        XCTAssertTrue(session.automaticAttempt)
    }

    func testSuccessfulConnectionResetsBudgetForLaterDisconnect() throws {
        let (store, channel, session) = try fixture(autoConnect: true)
        store.reconcile()
        channel.onFailure?("first failure")
        session.attemptAt = -100; store.reconcile()
        channel.onEvent?(["type": "ready", "protocol": 3, "pointerMode": "absolute"])
        XCTAssertEqual(session.retry.attempts, 0)
        XCTAssertFalse(session.retry.isActive)
        channel.onFailure?("connection lost")
        session.attemptAt = -100; store.reconcile()
        XCTAssertEqual(session.retry.attempts, 1)
        XCTAssertEqual(channel.starts, 3)
    }

    func testTransportChangeOnLastAttemptCannotResetRetryLimit() throws {
        let (store, channel, session) = try fixture(autoConnect: true)
        store.reconcile()
        for _ in 1..<ConnectionRetryState.maximumAttempts {
            channel.onFailure?("failed")
            session.attemptAt = -100; store.reconcile()
        }
        store.endpoints = [DeviceEndpoint(serial: "192.0.2.1:5555", hardwareID: "device", model: "test", kind: .phone,
            usb: false, authorization: "device")]
        store.reconcile()
        XCTAssertTrue(session.retry.isExhausted)
        rescan(store, session: session)
        XCTAssertEqual(channel.starts, ConnectionRetryState.maximumAttempts)
        XCTAssertTrue(store.status("device").retryStopped)
    }
}
