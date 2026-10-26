import Foundation
import Combine

final class ScrcpyConfiguration: ObservableObject {
    static let shared = ScrcpyConfiguration()
    static let preferenceKey = "scrcpy.customPath"

    @Published private(set) var customPath: String
    @Published private(set) var selected: ScrcpyExecutable?
    @Published private(set) var scanning = false
    @Published private(set) var error = ""
    private let defaults: UserDefaults
    private let resolver: ScrcpyResolver
    private let queue = DispatchQueue(label: "weft.scrcpy-resolution", qos: .utility)
    private var generation = 0
    var isAutomatic: Bool { customPath.isEmpty }

    init(defaults: UserDefaults = .standard, resolver: ScrcpyResolver = ScrcpyResolver()) {
        self.defaults = defaults; self.resolver = resolver
        customPath = resolver.normalized(defaults.string(forKey: Self.preferenceKey) ?? "")
    }

    func select(path: String) {
        customPath = resolver.normalized(path)
        defaults.set(customPath, forKey: Self.preferenceKey)
        scan()
    }

    func scan() {
        generation += 1
        let token = generation, path = customPath, resolver = resolver
        selected = nil; error = ""; scanning = true
        queue.async { [weak self] in
            let result = Result { try resolver.resolve(customPath: path) }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                switch result {
                case .success(let executable): self.selected = executable; self.error = ""
                case .failure(let error): self.selected = nil; self.error = error.localizedDescription
                }
                self.scanning = false
            }
        }
    }

    func requireExecutable() throws -> ScrcpyExecutable {
        guard !scanning else { throw BridgeError.message("正在查找 scrcpy，请稍候。") }
        guard let selected else {
            throw BridgeError.message(error.isEmpty ? "请先在通用设置中查找或选择 scrcpy。" : error)
        }
        guard FileManager.default.isExecutableFile(atPath: selected.path) else {
            throw BridgeError.message("scrcpy 已不可用，请在通用设置中重新扫描或选择文件。")
        }
        return selected
    }
}
