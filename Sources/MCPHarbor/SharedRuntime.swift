import Foundation

struct SharedServerSummary: Identifiable { let id: String; let name: String; let running: Bool; let allowedTools: [String] }

@MainActor extension HarborStore {
    func attachExistingGatewayIfPresent(force: Bool = false) {
        guard !takeoverBusy, gateway?.running != true, runtimeBridge?.running != true,
              initialConfigurationLoaded,
              force || !sharedConnectionAttempted,
              FileManager.default.fileExists(atPath: controlSocketURL.path) else { return }
        resolveRuntimePaths()
        let script = URL(fileURLWithPath: preferences.gatewayScript).deletingLastPathComponent().appendingPathComponent("runtime-bridge.js")
        guard runtimeFilesReady, RuntimeEnvironment.readableFile(script.path) else { return }
        sharedConnectionAttempted = true
        let process = ManagedProcess()
        runtimeBridge = process; sharedEventSequence = 0; gatewayState = "Connecting"
        process.onLine = { [weak self, weak process] channel, line in
            guard let self, let process, self.runtimeBridge === process else { return }
            if channel == "stdout" { self.consumeEvent(line) } else { self.log("shared gateway", line) }
        }
        process.onExit = { [weak self, weak process] _ in
            guard let self, let process, self.runtimeBridge === process else { return }
            self.runtimeBridge = nil; self.isAttachedGateway = false; self.attachedPort = nil
            let wasDisconnected = self.gatewayState == "Disconnected"
            self.gatewayState = "Disconnected"; self.clearPendingCommands()
            self.sharedRuntimeServers = []; self.states = [:]; self.tools = [:]; self.runningTunnelKeys = []; self.tunnelReady = [:]; self.tunnelHealthURLs = [:]; self.tunnelHealthSnapshots = [:]; self.requestTraces = []
            if !wasDisconnected { self.notice = "共享网关连接已结束。可点击启动服务重新连接，不会自动重发操作。" }
        }
        do {
            try process.start(executable: preferences.nodePath, arguments: [script.path, storageRoot.path, currentWorkspaceID])
        } catch { runtimeBridge = nil; gatewayState = "Disconnected"; errorMessage = "无法连接共享网关，请检查运行组件。" }
    }
    func applySharedSnapshot(_ snapshot: [String: Any]) {
        // The bridge already validates protocol, real storage root, workspace and immutable instance ID.
        guard snapshot["workspaceID"] as? String == currentWorkspaceID,
              snapshot["protocolVersion"] as? Int == 1 else { return }
        legacyCandidateJSON = nil
        isAttachedGateway = true; gatewayState = "Ready · loopback only"
        attachedPort = snapshot["port"] as? Int
        let servers = snapshot["servers"] as? [[String: Any]] ?? []
        sharedRuntimeServers = servers.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return SharedServerSummary(id: id, name: item["name"] as? String ?? id, running: item["running"] as? Bool ?? false, allowedTools: item["allowedTools"] as? [String] ?? [])
        }
        requestTraces = (snapshot["requests"] as? [[String: Any]] ?? []).suffix(80).compactMap { MCPRequestTrace.decode($0) }
        states = [:]; tools = [:]
        for server in servers {
            guard let id = server["id"] as? String else { continue }
            states[id] = server["running"] as? Bool == true ? "running" : "stopped"
            if let catalogue = server["tools"] as? [[String: Any]],
               let data = try? JSONSerialization.data(withJSONObject: ["type":"tools", "serverId":id, "tools":catalogue]),
               let line = String(data: data, encoding: .utf8) { consumeEvent(line) }
        }
        runningTunnelKeys = []; tunnelReady = [:]; tunnelHealthURLs = [:]; tunnelHealthSnapshots = [:]
        for event in snapshot["tunnels"] as? [[String: Any]] ?? [] {
            if let data = try? JSONSerialization.data(withJSONObject: event), let line = String(data: data, encoding: .utf8) { consumeEvent(line) }
        }
        for entry in snapshot["events"] as? [[String: Any]] ?? [] {
            guard let sequence = entry["sequence"] as? Int, sequence > sharedEventSequence,
                  let event = entry["event"] as? [String: Any] else { continue }
            sharedEventSequence = sequence
            if let message = event["message"] as? String { log(event["serverId"] as? String ?? "shared gateway", message) }
        }
        if Set(preferences.servers.map(\.id)) != Set(sharedRuntimeServers.map(\.id)) || sharedRuntimeServers.contains(where: { live in preferences.servers.first(where: { $0.id == live.id })?.allowedTools != live.allowedTools }) {
            externalConfigurationNotice = "磁盘配置与当前运行快照不同。当前服务及权限见设置中的共享网关；保存不会自动重启或改变运行权限。"
        } else if preferences.port != attachedPort { externalConfigurationNotice = "正在使用现有网关的端口。磁盘配置不会自动改变运行实例。" }
    }
    var legacyGatewayPID: String {
        guard let json = legacyCandidateJSON, let data = json.data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let pid = value["pid"] as? Int else { return "未知" }
        return String(pid)
    }
    func takeOverLegacyGateway() {
        guard !takeoverBusy, let candidate = legacyCandidateJSON, initialConfigurationLoaded else { return }
        // Persist only through the same revision-checked transaction before any disruption.
        guard save() else { return }
        let revision = savedRevision, workspace = currentWorkspaceID, config = preferences
        detachSharedGateway()
        let script = URL(fileURLWithPath: preferences.gatewayScript).deletingLastPathComponent().appendingPathComponent("takeover-command.js")
        guard RuntimeEnvironment.readableFile(script.path) else { errorMessage = "缺少接管组件，请重新构建完整应用。"; return }
        let process = ManagedProcess(); takeoverProcess = process; takeoverBusy = true
        var confirmedStopped = false
        process.onLine = { [weak self, weak process] channel, line in
            guard let self, let process, self.takeoverProcess === process, channel == "stdout",
                  let data = line.data(using: .utf8), let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            if event["type"] as? String == "takeoverStopped" { confirmedStopped = true }
            if event["type"] as? String == "takeoverFailed" { self.errorMessage = event["message"] as? String }
        }
        process.onExit = { [weak self, weak process] status in
            guard let self, let process, self.takeoverProcess === process else { return }
            self.takeoverBusy = false; self.takeoverProcess = nil
            guard status == 0, confirmedStopped else {
                self.notice = "旧网关退出未确认，未启动新实例。可重新连接检查。"; return
            }
            self.legacyCandidateJSON = nil
            guard self.currentWorkspaceID == workspace, self.preferences == config,
                  self.configurationRevision() == revision else {
                self.notice = "旧网关已停止，但配置在等待期间发生变化。请核对后启动服务。"; return
            }
            self.sharedConnectionAttempted = false
            self.notice = "旧网关已安全退出，正在启动新版网关。原有 MCP 和隧道不会自动重启。"
            self.startGateway()
        }
        do { try process.start(executable: preferences.nodePath, arguments: [script.path, storageRoot.path, workspace, candidate]) }
        catch { takeoverBusy = false; takeoverProcess = nil; errorMessage = "无法启动安全接管检查，未停止旧网关。" }
    }
    func detachSharedGateway() {
        let bridge = runtimeBridge
        runtimeBridge = nil; isAttachedGateway = false; attachedPort = nil
        bridge?.stop() // Stops only our adapter; never sends shutdown to the external gateway.
    }
}
