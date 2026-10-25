import Foundation

enum ADB {
    static var path: String? { try? ADBConfiguration.shared.requireExecutable().path }

    static func version(at path: String) -> String? {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue,
              FileManager.default.isExecutableFile(atPath: path),
              let output = try? run(at: path, ["version"], timeout: 2),
              output.hasPrefix("Android Debug Bridge version "),
              let version = output.split(separator: "\n").first(where: { $0.hasPrefix("Version ") }) else { return nil }
        return String(version.dropFirst("Version ".count))
    }

    static func run(_ args: [String], input: String? = nil, timeout: Double = 8) throws -> String {
        try run(at: ADBConfiguration.shared.requireExecutable().path, args, input: input, timeout: timeout)
    }

    static func run(at executable: String, _ args: [String], input: String? = nil, timeout: Double = 8) throws -> String {
        let child = Process(), output = Pipe(), stdin = Pipe()
        child.executableURL = URL(fileURLWithPath: executable); child.arguments = args
        child.standardOutput = output; child.standardError = output; child.standardInput = stdin
        try child.run()
        let result = CommandResult(), finished = DispatchGroup()
        finished.enter()
        DispatchQueue.global(qos: .utility).async {
            result.data = output.fileHandleForReading.readDataToEndOfFile(); finished.leave()
        }
        if let input { try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if child.isRunning {
            child.terminate(); _ = finished.wait(timeout: .now() + 1)
            throw BridgeError.message("设备响应超时，请检查连接和调试授权")
        }
        guard finished.wait(timeout: .now() + 1) == .success else { throw BridgeError.message("设备输出读取超时") }
        let text = String(data: result.data, encoding: .utf8) ?? ""
        guard child.terminationStatus == 0 else { throw BridgeError.message(String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(350))) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
private final class CommandResult: @unchecked Sendable { var data = Data() }
enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Log {
    private static let lock = NSLock()
    static let url = FileManager.default.temporaryDirectory.appendingPathComponent("weft-status.log")
    static func write(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(Date().ISO8601Format()) \(text)\n"; fputs(line, stderr)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
        }
    }
}
