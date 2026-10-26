import Foundation

struct ScrcpyExecutable: Equatable {
    let path: String
    let version: String
}

struct ScrcpyResolver {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser.path
    var inspect: (String) -> String? = ScrcpyResolver.version

    func normalized(_ path: String) -> String {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "~" { return home }
        if value.hasPrefix("~/") { return home + String(value.dropFirst()) }
        return value
    }

    var candidates: [String] {
        var paths = ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy", "/opt/local/bin/scrcpy", home + "/.local/bin/scrcpy"]
        paths += (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/scrcpy" }
        var seen = Set<String>()
        return paths.map(normalized).filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    func resolve(customPath: String?) throws -> ScrcpyExecutable {
        if let path = customPath.map(normalized), !path.isEmpty {
            guard path.hasPrefix("/"), let version = inspect(path) else {
                throw BridgeError.message("指定的 scrcpy 无法运行，请重新选择文件或恢复自动查找。")
            }
            return ScrcpyExecutable(path: path, version: version)
        }
        for path in candidates {
            if let version = inspect(path) { return ScrcpyExecutable(path: path, version: version) }
        }
        throw BridgeError.message("未找到 scrcpy。请先在这台 Mac 安装，或选择已安装的 scrcpy 文件。")
    }

    static func version(at path: String) -> String? {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue,
              FileManager.default.isExecutableFile(atPath: path),
              let output = try? ADB.run(at: path, ["--version"], timeout: 2),
              let line = output.split(separator: "\n").first(where: { $0.hasPrefix("scrcpy ") }),
              let version = line.split(separator: " ").dropFirst().first,
              version.first?.isNumber == true else { return nil }
        return String(version)
    }
}
