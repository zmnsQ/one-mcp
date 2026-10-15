import Foundation
import Darwin

/// No shell interpolation. Each child has dedicated pipes and a minimal environment.
@MainActor final class ManagedProcess {
    private(set) var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var error: Pipe?
    private var generation = UUID()
    private var endedChannels = Set<String>()
    private var exitStatus: Int32?
    private var buffers: [String: Data] = [:]
    var onLine: ((String, String) -> Void)?
    var onExit: ((Int32) -> Void)?
    var running: Bool { process?.isRunning == true }

    static func baseEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        return ["HOME", "USER", "TMPDIR", "LANG"].reduce(into: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) { result, key in
            if let value = source[key] { result[key] = value }
        }
    }
    func start(executable: String, arguments: [String], environment: [String: String] = [:], directory: String? = nil) throws {
        guard !running else { throw NSError(domain: "MCPHarbor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process already running"]) }
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
            throw NSError(domain: "MCPHarbor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose an absolute path to an installed executable."])
        }
        cleanup()
        let token = UUID(); generation = token
        let child = Process(); let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.environment = Self.baseEnvironment().merging(environment) { _, new in new }
        if let directory, !directory.isEmpty { child.currentDirectoryURL = URL(fileURLWithPath: directory) }
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        self.input = stdin; self.output = stdout; self.error = stderr; self.process = child
        for (channel, pipe) in [("stdout", stdout), ("stderr", stderr)] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                if bytes.isEmpty { handle.readabilityHandler = nil }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if bytes.isEmpty {
                        self.endedChannels.insert(channel)
                        if let tail = self.buffers.removeValue(forKey: channel), !tail.isEmpty {
                            self.onLine?(channel, String(decoding: tail, as: UTF8.self))
                        }
                        self.finishIfDrained()
                    } else { self.consume(bytes, channel: channel) }
                }
            }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.exitStatus = status
                self.finishIfDrained()
                // A descendant can retain a pipe after the direct child exits. Bound the drain wait.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, self.generation == token, self.exitStatus != nil else { return }
                    for channel in ["stdout", "stderr"] {
                        if let tail = self.buffers.removeValue(forKey: channel), !tail.isEmpty {
                            self.onLine?(channel, String(decoding: tail, as: UTF8.self))
                        }
                    }
                    self.endedChannels = ["stdout", "stderr"]
                    self.finishIfDrained()
                }
            }
        }
        do { try child.run() } catch { cleanup(); throw error }
    }
    private func finishIfDrained() {
        guard let status = exitStatus, endedChannels.count == 2 else { return }
        let callback = onExit
        cleanup()
        callback?(status)
    }
    private func consume(_ data: Data, channel: String) {
        buffers[channel, default: Data()].append(data)
        while let index = buffers[channel]?.firstIndex(of: 10) {
            guard let bytes = buffers[channel] else { break }
            let line = String(decoding: bytes[..<index], as: UTF8.self)
            buffers[channel]?.removeSubrange(...index)
            onLine?(channel, line)
        }
        if (buffers[channel]?.count ?? 0) > 128_000 { buffers[channel] = Data(); onLine?(channel, "[Oversized output line dropped]") }
    }
    func send(_ object: [String: Any]) throws {
        guard running, let input else { throw NSError(domain: "MCPHarbor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Gateway is not running"]) }
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func stop() {
        guard let child = process, child.isRunning else { return }
        try? input?.fileHandleForWriting.close()
        child.terminate()
        // Do not kill by a stale PID. Escalate only this still-running Process object.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
    private func cleanup() {
        generation = UUID(); endedChannels = []; exitStatus = nil
        output?.fileHandleForReading.readabilityHandler = nil
        error?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        try? error?.fileHandleForReading.close()
        process = nil; input = nil; output = nil; error = nil; buffers = [:]
    }
}
