import Foundation
import Combine

final class ADBConfiguration: ObservableObject {
    static let shared = ADBConfiguration()
    static let preferenceKey = "adb.customPath"

    @Published private(set) var customPath: String
    @Published private(set) var selected: ADBExecutable?
    @Published private(set) var scanning = false
    @Published private(set) var error = ""

    private let defaults: UserDefaults
    private let resolver: ADBResolver
    private let queue = DispatchQueue(label: "weft.adb-resolution", qos: .utility)
    private let lock = NSLock()
    private var executable: ADBExecutable?
    private var failure = "正在查找 ADB，请稍候。"
    private var generation = 0
    var isAutomatic: Bool { customPath.isEmpty }

    init(defaults: UserDefaults = .standard, resolver: ADBResolver = ADBResolver()) {
        self.defaults = defaults; self.resolver = resolver
        // An explicitly saved empty string means the user chose automatic mode,
        // including when WEFT_ADB was inherited from a terminal launch.
        customPath = resolver.normalized(defaults.string(forKey: Self.preferenceKey) ?? resolver.environment["WEFT_ADB"] ?? "")
    }

    func requireExecutable() throws -> ADBExecutable {
        lock.lock(); defer { lock.unlock() }
        guard let executable else { throw BridgeError.message(failure) }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw BridgeError.message("\(executable.source.rawValue)的 ADB 已不可用，请前往通用设置重新选择或扫描。")
        }
        return executable
    }

    func select(path: String) {
        customPath = resolver.normalized(path)
        defaults.set(customPath, forKey: Self.preferenceKey)
        publish(nil, error: "正在验证 ADB，请稍候。")
        scan()
    }

    func scan() {
        generation += 1
        let token = generation, path = customPath, resolver = resolver
        scanning = true; error = ""
        queue.async { [weak self] in
            let result = Result { try resolver.resolve(customPath: path) }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let executable): self.publish(executable, error: "")
                case .failure(let error): self.publish(nil, error: error.localizedDescription)
                }
                self.scanning = false
            }
        }
    }

    private func publish(_ value: ADBExecutable?, error message: String) {
        lock.lock(); executable = value; failure = message; lock.unlock()
        error = message; selected = value
    }
}
