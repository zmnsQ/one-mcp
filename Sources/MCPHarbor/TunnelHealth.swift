import Foundation

@MainActor extension HarborStore {
    func monitorTunnel(key: String, process: ManagedProcess, file: URL) {
        healthTasks[key]?.cancel()
        healthTasks[key] = Task { @MainActor [weak self, weak process] in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 4
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration, delegate: LocalOnlySessionDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            while !Task.isCancelled {
                guard let self, let process, process.running, self.tunnels[key] === process else { return }
                do {
                    let content = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard content.count < 256, let base = URL(string: content), base.scheme == "http", base.host == "127.0.0.1",
                          base.user == nil, base.password == nil, let port = base.port, (1...65535).contains(port),
                          base.query == nil, base.fragment == nil, base.path == "" || base.path == "/" else {
                        throw NSError(domain: "MCPHarbor", code: 20, userInfo: [NSLocalizedDescriptionKey: "官方CLI返回的健康地址不是预期loopback URL"])
                    }
                    let readyURL = base.appendingPathComponent("readyz")
                    let (_, response) = try await session.data(from: readyURL)
                    guard !Task.isCancelled, process.running, self.tunnels[key] === process else { return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.tunnelHealthURLs[key] = base
                    self.tunnelReady[key] = status == 200
                    self.tunnelStates[key] = status == 200 ? "隧道 ready（实际 /readyz HTTP 200）；ChatGPT 调用待验收" : "隧道未 ready（HTTP \(status)），正在持续检查"
                } catch {
                    if !Task.isCancelled, self.tunnels[key] === process {
                        self.tunnelReady[key] = false
                        self.tunnelStates[key] = "等待官方客户端健康端点：" + self.redacted(error.localizedDescription)
                    }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
