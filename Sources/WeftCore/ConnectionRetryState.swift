import Foundation

/// One explicitly started or automatic connection round, shared by every device.
public struct ConnectionRetryState {
    public static let maximumAttempts = 3
    public private(set) var attempts = 0
    public private(set) var isActive = false
    public private(set) var isExhausted = false

    public init() {}
    public mutating func beginRound() {
        attempts = 0; isActive = true; isExhausted = false
    }
    public mutating func admitAttempt() -> Bool {
        guard isActive, !isExhausted, attempts < Self.maximumAttempts else { return false }
        attempts += 1
        return true
    }
    public mutating func recordFailure() {
        guard isActive, attempts >= Self.maximumAttempts else { return }
        isActive = false; isExhausted = true
    }
    public mutating func succeed() {
        attempts = 0; isActive = false; isExhausted = false
    }
    public mutating func cancel() { isActive = false }
}
