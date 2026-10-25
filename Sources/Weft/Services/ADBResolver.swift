import Foundation

enum ADBSource: String {
    case custom = "用户指定"
    case scanned = "自动扫描"
    case bundled = "应用内置"
}

struct ADBExecutable: Equatable {
    let path: String
    let version: String
    let source: ADBSource
}

struct ADBResolver {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser.path
    var bundledPath: String? = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/adb").path
    var inspect: (String) -> String? = ADB.version

    func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") { return home + String(trimmed.dropFirst()) }
        return trimmed
    }

    var candidates: [String] {
        var paths = [String]()
        for key in ["ANDROID_SDK_ROOT", "ANDROID_HOME"] {
            if let root = environment[key], !normalized(root).isEmpty {
                paths.append(normalized(root) + "/platform-tools/adb")
            }
        }
        paths += [home + "/Library/Android/sdk/platform-tools/adb",
                  "/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/opt/local/bin/adb"]
        paths += (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/adb" }
        var seen = Set<String>()
        return paths.map(normalized).filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    func resolve(customPath: String?) throws -> ADBExecutable {
        if let path = customPath.map(normalized), !path.isEmpty {
            guard path.hasPrefix("/"), let version = inspect(path) else {
                throw BridgeError.message("用户指定的 ADB 无法运行：\(path)。请重新选择，或恢复自动查找。")
            }
            return ADBExecutable(path: path, version: version, source: .custom)
        }
        for path in candidates {
            if let version = inspect(path) { return ADBExecutable(path: path, version: version, source: .scanned) }
        }
        if let path = bundledPath, let version = inspect(path) {
            return ADBExecutable(path: path, version: version, source: .bundled)
        }
        throw BridgeError.message("没有找到可用的 ADB，应用内置版本也无法运行。请重新扫描或选择 ADB 文件。")
    }
}
