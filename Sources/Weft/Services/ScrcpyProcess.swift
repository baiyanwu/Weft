import Foundation
import Darwin

struct ScrcpyLaunchRequest {
    let executable: String
    let arguments: [String]
    let environment: [String: String]

    init(executable: String, adb: String, serial: String, name: String,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable
        arguments = ["--serial", serial, "--window-title", "\(name) · weft"]
        var values = environment
        values["ADB"] = adb
        values.removeValue(forKey: "ANDROID_SERIAL")
        values.removeValue(forKey: "SCRCPY_SERVER_PATH")
        let folders = [URL(fileURLWithPath: executable).deletingLastPathComponent().path,
                       URL(fileURLWithPath: adb).deletingLastPathComponent().path]
        values["PATH"] = (folders + [values["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        self.environment = values
    }
}

protocol ScrcpyProcessRunning: AnyObject {
    func start(_ request: ScrcpyLaunchRequest, completion: @escaping (Int32, String) -> Void) throws
    func stop()
}

/// Owns only the child launched by Weft; never searches for or kills external scrcpy sessions.
final class ScrcpyProcess: ScrcpyProcessRunning {
    private let child = Process()

    func start(_ request: ScrcpyLaunchRequest, completion: @escaping (Int32, String) -> Void) throws {
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: request.executable)
        child.arguments = request.arguments; child.environment = request.environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output; child.standardError = output
        try child.run()
        DispatchQueue.global(qos: .utility).async { [child] in
            var tail = Data()
            while let data = try? output.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {
                tail.append(data)
                if tail.count > 16384 { tail.removeFirst(tail.count - 16384) }
            }
            child.waitUntilExit()
            try? output.fileHandleForReading.close()
            completion(child.terminationStatus, String(decoding: tail, as: UTF8.self))
        }
    }

    func stop() {
        guard child.isRunning else { return }
        child.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [child] in
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}
