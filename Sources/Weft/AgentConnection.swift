import Foundation
import WeftCore

protocol AgentTransport: AnyObject {
    var onEvent: (([String: Any]) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start(serial: String)
    func send(_ line: String)
    func sendPointer(_ frame: PointerFrame)
    func stop()
}

extension AgentTransport {
    func sendPointer(_ frame: PointerFrame) { send(frame.command) }
}

/// One independent channel per physical Android device. Retired callbacks are fenced.
final class AgentConnection: AgentTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: ((String) -> Void)?
    private let queue = DispatchQueue(label: "weft.transport", qos: .userInteractive)
    private let lock = NSLock()
    private var generation = 0
    private var process: Process?
    private var stdin: FileHandle?
    private var output = Data()
    private let testWriter: ((String) -> Void)?
    private var pendingPointer: PointerFrame?
    private var motionTask = 0
    private var motionScheduled = false
    private var lastPointerButtons = 0, lastPointerEpoch = -1

    init(writer: ((String) -> Void)? = nil) { testWriter = writer }

    private func advance() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1; motionTask += 1
        pendingPointer = nil; motionScheduled = false
        lastPointerButtons = 0; lastPointerEpoch = -1
        return generation
    }
    private func current() -> Int { lock.lock(); defer { lock.unlock() }; return generation }
    private func deliver(_ token: Int, _ body: @escaping (AgentConnection) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current() == token else { return }; body(self)
        }
    }
    func start(serial: String) {
        let token = advance()
        queue.async { [weak self] in
            guard let self, self.current() == token else { return }; self.stopWorker()
            do {
                let adb = try ADBConfiguration.shared.requireExecutable().path
                guard let dex = Bundle.main.url(forResource: "weft-agent", withExtension: "dex") else {
                    throw BridgeError.message("未找到 Android 控制程序")
                }
                _ = try ADB.run(at: adb, ["-s", serial, "push", dex.path, "/data/local/tmp/weft-agent-v2.dex"], timeout: 10)
                guard self.current() == token else { return }
                let child = Process(), input = Pipe(), outputPipe = Pipe(), errors = Pipe()
                child.executableURL = URL(fileURLWithPath: adb)
                child.arguments = ["-s", serial, "shell", "-T", "CLASSPATH=/data/local/tmp/weft-agent-v2.dex", "app_process", "/", "io.baiyanwu.weft.BridgeAgent"]
                child.standardInput = input; child.standardOutput = outputPipe; child.standardError = errors
                self.output.removeAll(keepingCapacity: true)
                outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                    self?.queue.async { [weak self] in self?.receive(data, token: token) }
                }
                errors.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { handle.readabilityHandler = nil; return }
                    if let message = String(data: data, encoding: .utf8) { Log.write("agent[\(serial)]: \(message.trimmingCharacters(in: .whitespacesAndNewlines))") }
                }
                child.terminationHandler = { [weak self] _ in self?.deliver(token) { $0.onFailure?("设备连接已断开") } }
                try child.run(); self.process = child; self.stdin = input.fileHandleForWriting
            } catch { self.deliver(token) { $0.onFailure?(error.localizedDescription) } }
        }
    }
    func send(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        enqueueBarrier(line, token: generation)
    }
    func sendPointer(_ frame: PointerFrame) {
        lock.lock(); defer { lock.unlock() }
        let token = generation
        let barrier = frame.epoch != lastPointerEpoch || frame.buttons != lastPointerButtons || frame.wheel != 0 || frame.pan != 0
        lastPointerEpoch = frame.epoch; lastPointerButtons = frame.buttons
        if barrier { enqueueBarrier(frame.command, token: token); return }
        pendingPointer = frame
        guard !motionScheduled else { return }
        motionScheduled = true; motionTask += 1
        let task = motionTask
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.generation == token, self.motionTask == task else { self.lock.unlock(); return }
            let pending = self.pendingPointer
            self.pendingPointer = nil; self.motionScheduled = false
            self.lock.unlock()
            if let pending { self.write(pending.command, token: token) }
        }
    }
    // Called with lock held: flush pending motion before every input/control barrier.
    private func enqueueBarrier(_ line: String, token: Int) {
        let pending = pendingPointer
        pendingPointer = nil; motionScheduled = false; motionTask += 1
        queue.async { [weak self] in
            guard let self else { return }
            if let pending { self.write(pending.command, token: token) }
            self.write(line, token: token)
        }
    }
    private func write(_ line: String, token: Int) {
        guard current() == token else { return }
        if let testWriter { testWriter(line); return }
        guard let handle = stdin else { return }
        do { try handle.write(contentsOf: Data((line + "\n").utf8)) }
        catch { stopWorker(); deliver(token) { $0.onFailure?("输入连接中断") } }
    }
    func stop() {
        _ = advance()
        // Removing a device releases its session; retain the channel until cleanup finishes.
        queue.async { self.stopWorker() }
    }
    private func stopWorker() {
        if let handle = stdin { try? handle.write(contentsOf: Data("release\nquit\n".utf8)); try? handle.close() }
        stdin = nil
        if let child = process, child.isRunning { child.terminate() }; process = nil
    }
    private func receive(_ data: Data, token: Int) {
        guard current() == token else { return }; output.append(data)
        guard output.count < 262144 else { output.removeAll(); deliver(token) { $0.onFailure?("设备协议数据异常") }; return }
        while let newline = output.firstIndex(of: 10) {
            let line = output.prefix(upTo: newline); output.removeSubrange(...newline)
            if let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { deliver(token) { $0.onEvent?(event) } }
        }
    }
}
