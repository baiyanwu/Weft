import CoreGraphics
import Foundation
import Darwin

/// Owns one balanced hide/disassociate pair, independently of app/window focus.
final class MacCursorCapture {
    struct Operations {
        var prepare: () -> CGError
        var hide: () -> CGError
        var associate: (Bool) -> CGError
        var warp: (CGPoint) -> CGError
        var show: () -> CGError

        static let system = Operations(
            prepare: { BackgroundCursor.prepare() },
            hide: { CGDisplayHideCursor(CGMainDisplayID()) },
            associate: { CGAssociateMouseAndMouseCursorPosition($0 ? 1 : 0) },
            warp: { CGWarpMouseCursorPosition($0) },
            show: { CGDisplayShowCursor(CGMainDisplayID()) })
    }

    private let operations: Operations
    private var hidden = false
    private var detached = false
    var isCaptured: Bool { hidden || detached }

    init(operations: Operations = .system) { self.operations = operations }

    func capture(at point: CGPoint) -> CGError {
        guard !isCaptured else { return .invalidOperation }
        let prepared = operations.prepare()
        guard prepared == .success else { return prepared }
        let hide = operations.hide()
        guard hide == .success else { return hide }
        hidden = true
        let associate = operations.associate(false)
        guard associate == .success else { _ = restore(); return associate }
        detached = true
        // Position changes happen only while hidden. Never park at screen center.
        let warp = operations.warp(point)
        guard warp == .success else { _ = restore(); return warp }
        return .success
    }

    @discardableResult func restore(at point: CGPoint? = nil) -> CGError {
        guard isCaptured else { return .success }
        var result = CGError.success
        if let point { result = operations.warp(point) }
        if detached {
            let associate = operations.associate(true)
            if associate == .success { detached = false }
            if result == .success { result = associate }
        }
        if hidden {
            let show = operations.show()
            if show == .success { hidden = false }
            if result == .success { result = show }
        }
        return result
    }

    deinit { restore() }
}

private enum BackgroundCursor {
    typealias Connection = @convention(c) () -> Int32
    typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFBoolean) -> Int32

    // Quartz normally requires foreground ownership. Resolve this WindowServer
    // capability at runtime so a missing private API fails without stealing focus.
    static func prepare() -> CGError {
        let symbols = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connectionSymbol = dlsym(symbols, "CGSMainConnectionID"),
              let propertySymbol = dlsym(symbols, "CGSSetConnectionProperty") else { return .notImplemented }
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
        let setProperty = unsafeBitCast(propertySymbol, to: SetProperty.self)
        let result = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        return CGError(rawValue: result) ?? .failure
    }
}
