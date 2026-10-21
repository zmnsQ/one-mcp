import SwiftUI
import AppKit

@MainActor final class HarborStore: ObservableObject {
    @Published var importCandidates: [ImportCandidate] = []
    @Published var selectedImportIDs = Set<String>()
    @Published var showImportPreview = false
    @Published var workspaces: [WorkspaceRecord] = []
    @Published var currentWorkspaceID = "default"
    @Published var setupChecks: [CheckResult] = []
    @Published var notice: String?
    @Published var toolChanges: [String: String] = [:]
    @Published var tunnelReady: [String: Bool] = [:]
    @Published var profileCreation: [String: TunnelProfileCreation] = [:]
    var profileCreationOperationIDs: [String: String] = [:]
    @Published var initializedTargets: [String: String] = [:]
    @Published var checkedTargets: [String: String] = [:]
    @Published var doctorPassed: [String: Bool] = [:]
    @Published var connectionEvents: [ConnectionLogEvent] = []
    @Published var requestTraces: [MCPRequestTrace] = []
    @Published var tunnelCredentialStatus = "仅本次会话使用。"
    @Published var tunnelHealthSnapshots: [String: TunnelHealthSnapshot] = [:]
    @Published var tunnelHealthURLs: [String: URL] = [:]
    var healthTasks: [String: Task<Void, Never>] = [:]
    @Published var discoveryBusy = false
    @Published var discoveryError: String?
    @Published var environmentDiscovery: EnvironmentDiscovery?
    @Published var runningTunnelKeys = Set<String>()
    var configurationLeaseToken: String?
    var gatewayStartupLeaseToken: String?
    var savedRevision = "missing"
    var savedIndexRevision = "missing"
    var configurationWatchTask: Task<Void, Never>?
    @Published var externalConfigurationNotice: String?
    var initialConfigurationLoaded = false
    var initialReadAttempts = 0
    var storageReadable = true
    var redactionValues = Set<String>()
    @Published var preferences = Preferences()
    @Published var savedPreferences = Preferences()
    var hasUnsavedChanges: Bool { preferences != savedPreferences }
    @Published var startAllBusy = false
    @Published var startAllSteps: [StartAllStep] = []
    var startAllRevision: String?
    var startAllTask: Task<Void, Never>?
    var commandResults: [String: String] = [:]
    @Published var pendingCommands: [String: String] = [:]
    private var commandContexts: [String: (method: String, serverID: String?)] = [:]
    private var commandTimeouts: [String: Task<Void, Never>] = [:]
    @Published var selectedID: String?
    @Published var gatewayState = "Stopped"
    @Published var states: [String: String] = [:]
    var shownTunnelFailures: [String: String] = [:]
    @Published var tunnelProfileLocations: [String: String] = [:]
    @Published var tunnelStates: [String: String] = [:]
    @Published var tunnelMenuStates: [String: MenuBarStatus] = [:]
    @Published var cloudflarePublicURL: String?
    @Published var recordCloudflarePublicURLs: [String: String] = [:]
    @Published var tools: [String: [ToolInfo]] = [:]
    @Published var logs: [LogLine] = []
    @Published var errorMessage: String?
    // Secrets are deliberately memory-only, excluded from Codable and persistence.
    @Published var runtimeValues: [String: String] = [:]
    @Published var tunnelKey = ""
    @Published var recordTunnelKeys: [String: String] = [:]
    var recordTunnelKeyAccountIDs: [String: String] = [:]
    var gateway: ManagedProcess?
    var runtimeBridge: ManagedProcess?
    var startupPreparation: ManagedProcess?
    var gatewayStartCancelled = false
    @Published var gatewayStartBusy = false
    var takeoverProcess: ManagedProcess?
    @Published var takeoverBusy = false
    @Published var legacyCandidateJSON: String?
    @Published var isAttachedGateway = false
    @Published var sharedRuntimeServers: [SharedServerSummary] = []
    @Published var appliedServerFingerprints: [String: [String: String]] = [:]
    @Published var appliedTunnelFingerprints: [String: [String: String]] = [:]
    @Published var appliedGatewayFingerprints: [String: String] = [:]
    var attachedPort: Int?
    var sharedEventSequence = 0
    var sharedConnectionAttempted = false
    var tunnels: [String: ManagedProcess] = [:]
    private var tunnelTargets: [String: (profile: String, tunnelID: String)] = [:]
    let fileURL: URL
    var isGatewayRunning: Bool { gateway?.running == true || isAttachedGateway }
    var gatewayReady: Bool { gatewayState == "Ready · loopback only" }

    init(configurationFileURL: URL? = nil, startWatcher: Bool = true) {
        fileURL = configurationFileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MCPHarbor", isDirectory: true).appendingPathComponent("settings.json")
        // Opening a window is a read operation, never a configuration transaction.
        loadInitialConfiguration()
        if startWatcher { startConfigurationWatch() }
        checkSetup()
        attachExistingGatewayIfPresent()
        // Never restore process state or start services from disk.
    }
    @discardableResult func save() -> Bool {
        guard initialConfigurationLoaded else { errorMessage = "配置尚未完整载入，未写入任何内容。请先重新载入磁盘版本。"; return false }
        let ownsLease = configurationLeaseToken == nil
        if ownsLease { acquireConfigurationLease() }
        guard configurationLeaseToken != nil else { return false }
        defer { if ownsLease { releaseConfigurationLease() } }
        guard savedRevision == configurationRevision() else { errorMessage = "AI 或另一窗口已更新配置。当前修改已保留，请先核对外部更新，避免覆盖。"; return false }
        guard storageReadable else { errorMessage = "配置文件损坏，禁止覆盖。请先导入有效配置或创建新工作空间。"; return false }
        do {
            try validatePreferences(preferences, requireInstalled: false)
            if let issue = RemoteConnectionValidation.issue(preferences.remoteConnection) {
                throw NSError(domain: "OneMCP", code: 12, userInfo: [NSLocalizedDescriptionKey: issue])
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try encoder.encode(preferences).write(to: activeConfigurationURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activeConfigurationURL.path)
            savedPreferences = preferences
            savedRevision = configurationRevision()
            externalConfigurationNotice = nil
            if anyProcessRunning { notice = "配置已保存；运行中的服务不变，需明确重启相关服务后生效。" }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func addServer() { guard preferences.servers.count < 16 else { errorMessage = "每个工作空间最多16个服务器。"; return }; let item = ServerConfig(); preferences.servers.append(item); selectedID = item.id; save() }
    func removeServer(_ server: ServerConfig) {
        cancelStartAll()
        if isGatewayRunning { command("stopServer", params: ["serverId": server.id]) }
        tools[server.id] = nil; states[server.id] = nil; toolChanges[server.id] = nil
        for key in Array(runtimeValues.keys) where key.hasPrefix(server.id + ":") {
            if let value = runtimeValues.removeValue(forKey: key), !value.isEmpty { redactionValues.insert(value) }
        }
        preferences.tunnelRecords = preferences.effectiveTunnelRecords.map { record in
            var updated = record; updated.serverIDs.removeAll { $0 == server.id }; return updated
        }
        preferences.servers.removeAll { $0.id == server.id }; selectedID = preferences.servers.first?.id; save()
    }
    func redacted(_ text: String) -> String {
        var safe = text
        for value in Array(redactionValues) + Array(runtimeValues.values) + Array(recordTunnelKeys.values) + [tunnelKey] where !value.isEmpty { safe = safe.replacingOccurrences(of: value, with: "[REDACTED]") }
        if let regex = try? NSRegularExpression(pattern: "(?i)(bearer\\s+|sk-)[A-Za-z0-9_./+=-]+") {
            safe = regex.stringByReplacingMatches(in: safe, range: NSRange(safe.startIndex..., in: safe), withTemplate: "[REDACTED]")
        }
        return safe
    }
    func log(_ source: String, _ text: String) {
        logs.append(LogLine(source: source, text: String(redacted(text).prefix(8000))))
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }
    func startGateway(persistConfiguration: Bool = true) {
        guard !takeoverBusy, !gatewayStartBusy, !isGatewayRunning else { return }
        // Retire an exited owner before acquiring a new lease. Its delayed pipe-drain
        // callback must not clear the new startup state or release the new lease.
        gateway = nil
        releaseGatewayStartupLease()
        clearPendingCommands()
        detachSharedGateway() // Discard only a failed adapter, never stop the shared gateway.
        clearAppliedConfiguration(); sharedRuntimeServers = []; states = [:]; tools = [:]; runningTunnelKeys = []
        tunnelReady = [:]; tunnelHealthURLs = [:]; tunnelHealthSnapshots = [:]; cloudflarePublicURL = nil; recordCloudflarePublicURLs = [:]
        requestTraces = []; connectionEvents = []
        resolveRuntimePaths()
        guard runtimeFilesReady else { errorMessage = runtimeSetupSummary; checkSetup(); return }
        acquireConfigurationLease()
        guard configurationLeaseToken != nil else { return }
        // Save only when actually launching; attaching to a live instance remains read-only.
        gatewayStartupLeaseToken = configurationLeaseToken
        let workspace = currentWorkspaceID, config = preferences, revision = savedRevision
        let process = ManagedProcess()
        startupPreparation = process; gatewayStartCancelled = false; gatewayStartBusy = true; tunnelMenuStates = [:]; gatewayState = "Checking"
        notice = nil; errorMessage = nil
        var preparedState: String?
        process.onLine = { [weak self, weak process] channel, line in
            guard let self, let process, self.startupPreparation === process else { return }
            guard channel == "stdout", let data = line.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { self.log("gateway start", line); return }
            if event["type"] as? String == "runtimeStartPrepared" { preparedState = event["state"] as? String }
            if event["type"] as? String == "runtimeStartFailed" { self.errorMessage = event["message"] as? String }
        }
        process.onExit = { [weak self, weak process] status in
            guard let self, let process, self.startupPreparation === process else { return }
            self.startupPreparation = nil; self.gatewayStartBusy = false
            guard !self.gatewayStartCancelled, status == 0, let preparedState,
                  self.currentWorkspaceID == workspace, self.preferences == config,
                  self.configurationRevision() == revision else {
                self.releaseGatewayStartupLease(); self.gatewayState = "Disconnected"
                if self.errorMessage == nil { self.errorMessage = "启动检查未完成或配置已改变，请检查后重试。" }
                return
            }
            if preparedState == "existing" {
                self.releaseGatewayStartupLease(); self.attachExistingGatewayIfPresent(force: true); return
            }
            guard preparedState == "available", (!persistConfiguration || self.save()) else { self.releaseGatewayStartupLease(); self.gatewayState = "Disconnected"; return }
            self.launchGatewayWithStartupLease()
        }
        do {
            let script = URL(fileURLWithPath: preferences.gatewayScript).deletingLastPathComponent().appendingPathComponent("runtime-start-command.js")
            try process.start(executable: preferences.nodePath, arguments: [script.path, storageRoot.path])
            Task { @MainActor [weak self, weak process] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, let process, self.startupPreparation === process else { return }
                self.gatewayStartCancelled = true
                self.errorMessage = "网关状态检查超时，未启动新实例。"
                process.stop() // Keep the lease until the preparation process has exited.
            }
        } catch {
            startupPreparation = nil; gatewayStartBusy = false; releaseGatewayStartupLease()
            gatewayState = "Disconnected"; errorMessage = error.localizedDescription
        }
    }
    private func launchGatewayWithStartupLease() {
        let process = ManagedProcess()
        process.onLine = { [weak self, weak process] channel, line in
            guard let self, let process, self.gateway === process else { return }
            if channel == "stdout" { self.consumeEvent(line) } else { self.log("gateway", line) }
        }
        process.onExit = { [weak self, weak process] status in
            guard let self, let process, self.gateway === process else { return }
            self.releaseGatewayStartupLease()
            self.gatewayState = "Stopped (exit \(status))"
            self.clearAppliedConfiguration(); self.sharedRuntimeServers = []; self.attachedPort = nil
            self.clearPendingCommands()
            self.runningTunnelKeys.removeAll(); self.tunnelMenuStates = [:]
            self.tunnelReady = [:]; self.tunnelHealthURLs = [:]; self.tunnelHealthSnapshots = [:]; self.cloudflarePublicURL = nil; self.recordCloudflarePublicURLs = [:]; self.requestTraces = []; self.connectionEvents = []
            for id in Array(self.states.keys) { self.states[id] = "stopped" }
            self.stopAllTunnels()
        }
        do {
            gateway = process; gatewayState = "Starting"
            try FileManager.default.createDirectory(at: controlSocketURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try process.start(executable: preferences.nodePath, arguments: [preferences.gatewayScript, "--port", String(preferences.port), "--workspace-id", currentWorkspaceID, "--control-socket", controlSocketURL.path], environment: ManagedProcess.tunnelLocationEnvironment())
            Task { @MainActor [weak self, weak process] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, let process, self.gateway === process, !self.gatewayReady, process.running else { return }
                self.errorMessage = "网关启动超时，已请求停止。"
                process.stop() // The exit callback releases the startup lease after the process stops.
            }
        } catch { releaseGatewayStartupLease(); gatewayState = "Stopped"; errorMessage = error.localizedDescription }
    }
    func stopGateway() {
        cancelStartAll()
        if isAttachedGateway {
            command("shutdown", params: [:]); gatewayState = "Stopping"; return
        }
        stopAllTunnels()
        guard let process = gateway else { return }
        try? process.send(["id": UUID().uuidString, "method": "shutdown", "params": [:]])
        gatewayState = "Stopping"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            process.stop()
        }
    }
    func consumeEvent(_ line: String) {
        guard let data = line.data(using: .utf8), let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { log("gateway", line); return }
        let id = event["serverId"] as? String ?? "gateway"
        switch event["type"] as? String {
        case "legacyGatewayAvailable":
            if let candidate = event["candidate"], let data = try? JSONSerialization.data(withJSONObject: candidate, options: .sortedKeys) {
                legacyCandidateJSON = String(data: data, encoding: .utf8)
            }
        case "sharedSnapshot":
            if let snapshot = event["snapshot"] as? [String: Any] { applySharedSnapshot(snapshot) }
        case "sharedDisconnected":
            notice = event["message"] as? String
            runtimeBridge?.stop()
            isAttachedGateway = false; gatewayState = "Disconnected"; attachedPort = nil; tunnelMenuStates = [:]
            clearPendingCommands(); clearAppliedConfiguration(); sharedRuntimeServers = []; states = [:]; tools = [:]; runningTunnelKeys = []; tunnelReady = [:]; tunnelHealthURLs = [:]; tunnelHealthSnapshots = [:]; cloudflarePublicURL = nil; recordCloudflarePublicURLs = [:]; requestTraces = []; self.connectionEvents = []
        case "response":
            if let requestID = event["id"] as? String {
                if commandResults.count > 100 { commandResults = [:] }
                commandResults[requestID] = event["ok"] as? Bool == true ? "ok" : redacted(event["error"] as? String ?? "网关未确认操作成功")
                let context = commandContexts.removeValue(forKey: requestID)
                pendingCommands[requestID] = nil
                if event["ok"] as? Bool == false, let context, let key = context.serverID,
                   ["tunnelAction", "cloudflareAction", "startTunnel", "startCloudflare", "stopTunnel", "stopCloudflare"].contains(context.method) {
                    tunnelMenuStates[key] = .failed
                    if profileCreation[key]?.isInFlight == true {
                        profileCreation[key] = .failed
                        tunnelStates[key] = redacted(event["error"] as? String ?? "本地 Profile 创建失败，请检查配置后重试。")
                    }
                }
                if event["ok"] as? Bool == true, let context, let key = context.serverID,
                   ["stopTunnel", "stopCloudflare"].contains(context.method) {
                    tunnelMenuStates[key] = .stopped
                }
                commandTimeouts.removeValue(forKey: requestID)?.cancel()
                if event["ok"] as? Bool == false, let context, context.method == "startServer", let serverID = context.serverID, states[serverID] == "starting" {
                    states[serverID] = "error"
                }
            }
        case "connectionEvent":
            if let value = event["entry"] as? [String: Any], let record = ConnectionLogEvent.decode(value) {
                connectionEvents.append(record); if connectionEvents.count > 200 { connectionEvents.removeFirst(connectionEvents.count - 200) }
            }
        case "httpRequest":
            if let value = event["request"] as? [String: Any], let record = MCPRequestTrace.decode(value) {
                requestTraces.append(record); if requestTraces.count > 80 { requestTraces.removeFirst(requestTraces.count - 80) }
            }
        case "tunnelProfile":
            if let key = event["key"] as? String, let path = event["profileLocation"] as? String { tunnelProfileLocations[key] = path }
        case "tunnelStatus":
            refreshStartAllTunnel(event)
            if let key = event["key"] as? String, let operationID = profileCreationOperationIDs[key],
               let phase = TunnelProfileCreation.correlatedEvent(event, operationID: operationID) {
                profileCreation[key] = phase
            }
            if let key = event["key"] as? String { tunnelMenuStates[key] = .tunnel(event: event) }
            if let key = event["key"] as? String {
                if event["running"] as? Bool == true { runningTunnelKeys.insert(key) } else { runningTunnelKeys.remove(key) }
                appliedTunnelFingerprints[key] = event["running"] as? Bool == true ? ConfigurationFingerprint.decode(event) : nil
                tunnelReady[key] = event["ready"] as? Bool ?? false
                tunnelHealthSnapshots[key] = (event["running"] as? Bool == true) ? TunnelHealthSnapshot(event["health"] as? [String: Any]) : nil
                tunnelHealthURLs[key] = (event["running"] as? Bool == true) ? TunnelDashboardURL.validated(event["healthURL"] as? String) : nil
                tunnelStates[key] = event["state"] as? String ?? "状态已更新"
                recordCloudflarePublicURLs[key] = (event["running"] as? Bool == true)
                    ? (event["mcpURL"] as? String).flatMap { RemoteConnectionValidation.publicHTTPS($0)?.absoluteString } : nil
                if key == "transport:cloudflare" {
                    cloudflarePublicURL = (event["running"] as? Bool == true)
                        ? (event["mcpURL"] as? String).flatMap { RemoteConnectionValidation.publicHTTPS($0)?.absoluteString } : nil
                }
                if event["running"] as? Bool == true { shownTunnelFailures[key] = nil }
                if let code = event["errorCode"] as? String, let message = event["message"] as? String {
                    let identity = (event["signature"] as? String ?? "") + code
                    tunnelStates[key] = message
                    if shownTunnelFailures[key] != identity { shownTunnelFailures[key] = identity; errorMessage = message }
                }
                if let exitCode = event["exitCode"] as? Int, let signature = event["signature"] as? String {
                    if event["action"] as? String == "doctor" { doctorPassed[key] = exitCode == 0; checkedTargets[key] = exitCode == 0 ? signature : nil }
                    if event["action"] as? String == "init" { initializedTargets[key] = exitCode == 0 ? signature : nil }
                }
            }
        case "ready":
            gatewayState = "Ready · loopback only"; releaseGatewayStartupLease()
            attachedPort = event["port"] as? Int
            appliedGatewayFingerprints = ConfigurationFingerprint.decode(event)
        case "serverStatus":
            states[id] = event["status"] as? String ?? "unknown"
            appliedServerFingerprints[id] = ConfigurationFingerprint.decode(event)
            if event["status"] as? String == "running" {
                let name = event["name"] as? String ?? preferences.servers.first(where: { $0.id == id })?.name ?? id
                let allowed = event["allowedTools"] as? [String] ?? []
                sharedRuntimeServers.removeAll { $0.id == id }
                sharedRuntimeServers.append(.init(id: id, name: name, running: true, allowedTools: allowed, permissionsKnown: event["allowedTools"] is [String]))
            } else if ["stopped", "error", "failed"].contains(event["status"] as? String ?? "") {
                sharedRuntimeServers.removeAll { $0.id == id }
            }
        case "tools":
            let previous = tools[id]
            tools[id] = (event["tools"] as? [[String: Any]] ?? []).compactMap {
                guard let name = $0["name"] as? String else { return nil }
                var metadata: [String: Any] = [:]
                for key in ["inputSchema", "outputSchema", "annotations"] { if let value = $0[key] { metadata[key] = value } }
                let encoded = (try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                return ToolInfo(name: name, description: $0["description"] as? String ?? "", publicName: $0["publicName"] as? String ?? "", metadataJSON: String(decoding: encoded, as: UTF8.self))
            }
            if let previous {
                let before = Dictionary(previous.map { ($0.name, $0.description + $0.metadataJSON) }, uniquingKeysWith: { _, last in last })
                let after = Dictionary((tools[id] ?? []).map { ($0.name, $0.description + $0.metadataJSON) }, uniquingKeysWith: { _, last in last })
                if before != after { toolChanges[id] = "工具目录或说明已变化，请重新核对白名单并在 ChatGPT Refresh。" }
            }
        default: break
        }
        if let message = event["message"] as? String { log(id, message) }
        if let error = event["error"] as? String { log(id, error); errorMessage = redacted(error) }
    }
    func clearPendingCommands() {
        for (key, phase) in profileCreation where phase.isInFlight { profileCreation[key] = .unknown }
        commandTimeouts.values.forEach { $0.cancel() }
        commandTimeouts = [:]; commandContexts = [:]; pendingCommands = [:]
    }
    func hasPendingCommand(for serverID: String) -> Bool {
        commandContexts.values.contains { $0.serverID == serverID }
    }
    @discardableResult func command(_ method: String, params: [String: Any]) -> Bool {
        if ["stopServer", "stopTunnel", "stopAllTunnels", "shutdown"].contains(method) { cancelStartAll() }
        guard isGatewayRunning else { errorMessage = "网关未运行，请先启动网关。"; return false }
        let id = UUID().uuidString
        let configID = (params["server"] as? [String: Any])?["id"] as? String
        let serverID = (params["serverId"] as? String) ?? configID ?? (params["key"] as? String)
        do {
            guard let transport = isAttachedGateway ? runtimeBridge : gateway else { return false }
            try transport.send(["id": id, "method": method, "params": params])
            pendingCommands[id] = method
            commandContexts[id] = (method, serverID)
            if let key = serverID {
                if ["tunnelAction", "cloudflareAction", "startTunnel", "startCloudflare"].contains(method) {
                    tunnelMenuStates[key] = (params["action"] as? String ?? "run") == "run" ? .starting : .checking
                } else if ["stopTunnel", "stopCloudflare"].contains(method) { tunnelMenuStates[key] = .stopping }
            }
            commandTimeouts[id] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self, self.pendingCommands[id] != nil else { return }
                if let key = serverID, ["tunnelAction", "cloudflareAction", "startTunnel", "startCloudflare", "stopTunnel", "stopCloudflare"].contains(method) { self.tunnelMenuStates[key] = .unknown }
                self.errorMessage = "网关尚未确认 \(method)。操作可能仍在执行；请查看日志，必要时全部停止后重试。"
                // Keep the pending marker until a real response or gateway exit, preventing duplicate starts.
            }
            return true
        } catch { errorMessage = redacted(error.localizedDescription); return false }
    }
    func credentialKey(serverID: String, variable: String) -> String { serverID + ":" + variable }
    @discardableResult func startServer(_ server: ServerConfig, persistConfiguration: Bool = true) -> Bool {
        guard !hasPendingCommand(for: server.id), states[server.id] != "running" else { return false }
        guard gatewayReady else { errorMessage = "请先启动本机网关。"; return false }
        if server.isCLI && appliedGatewayFingerprints["cliServiceVersion"] != ConfigurationFingerprint.scalar("1") {
            errorMessage = "当前网关不支持 CLI 服务。请更新运行组件并重新启动网关。"; return false
        }
        guard server.executable.hasPrefix("/") else { errorMessage = "MCP可执行文件须为绝对路径。"; return false }
        var validationScope = preferences; validationScope.servers = [server]; validationScope.tunnelRecords = []
        do { try validatePreferences(validationScope) } catch { errorMessage = error.localizedDescription; return false }
        var environment: [String: String] = [:]
        for key in server.environmentKeys {
            guard let value = runtimeValues[credentialKey(serverID: server.id, variable: key)], !value.isEmpty else { errorMessage = "请输入 \(server.name) 的 \(key) 本次会话值。"; return false }
            environment[key] = value
            redactionValues.insert(value)
        }
        var config: [String: Any] = ["id": server.id, "name": server.name, "executable": server.executable,
            "arguments": server.arguments, "environment": environment, "allowedTools": server.allowedTools]
        config["kind"] = server.kind ?? "mcp"
        if server.isCLI, let cli = server.cli {
            do { config["cli"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cli)) }
            catch { errorMessage = "CLI 配置无法编码。"; return false }
        }
        if !server.workingDirectory.isEmpty { config["workingDirectory"] = server.workingDirectory }
        guard !persistConfiguration || save() else { return false }
        if command("startServer", params: ["server": config]) { states[server.id] = "starting"; return true }
        return false
    }
    func stopServer(_ server: ServerConfig) {
        cancelStartAll()
        // The gateway withdraws only tunnels bound to this backend.
        command("stopServer", params: ["serverId": server.id])
    }
    func endpoint(_ server: ServerConfig?) -> String {
        "http://127.0.0.1:\(attachedPort ?? preferences.port)" + (server.map { "/servers/\($0.id)/mcp" } ?? "/mcp")
    }
    func tunnelRunning(_ key: String) -> Bool { runningTunnelKeys.contains(key) }
    func endpoint(record: TunnelRecord) -> String { "http://127.0.0.1:\(attachedPort ?? preferences.port)/tunnels/\(record.id)/mcp" }
    func validRecordBinding(_ record: TunnelRecord) -> Bool {
        let known = Set(preferences.servers.map(\.id))
        guard !record.serverIDs.isEmpty, Set(record.serverIDs).count == record.serverIDs.count,
              record.serverIDs.allSatisfy({ known.contains($0) }) else {
            errorMessage = "请为隧道选择至少一个现有 MCP 服务；已移除的服务须重新选择。"; return false
        }
        return true
    }
    func requireScopedTunnelRuntime() -> Bool {
        guard appliedGatewayFingerprints["tunnelRecordsVersion"] == ConfigurationFingerprint.scalar("1") else {
            errorMessage = "当前网关尚未证明支持独立服务绑定。请明确停止并使用新版网关重启，再启动此隧道；不会通过旧版网关公开工具。"
            return false
        }
        return true
    }
    func requireProfileCreationRuntime() -> Bool {
        guard appliedGatewayFingerprints["tunnelProfileCreationVersion"] == ConfigurationFingerprint.scalar("1") else {
            errorMessage = "当前网关不支持安全创建与结果确认。请明确停止并使用新版网关重启，再创建 Profile；不会调用旧版初始化。"
            return false
        }
        return true
    }
    @discardableResult func tunnelAction(_ action: String, record: TunnelRecord, persistConfiguration: Bool = true) -> Bool {
        guard requireScopedTunnelRuntime(), action != "init" || requireProfileCreationRuntime() else { return false }
        let key = record.id
        guard gatewayReady, !tunnelRunning(key), !hasPendingCommand(for: key), profileCreation[key]?.isInFlight != true, ["init", "doctor", "run"].contains(action), validRecordBinding(record) else { errorMessage = errorMessage ?? "请启动网关并等待当前隧道操作完成。"; return false }
        guard !persistConfiguration || save() else { return false }
        let runtimeKey: String
        do { runtimeKey = try resolveRecordTunnelKey(record) }
        catch { errorMessage = error.localizedDescription; return false }
        guard action != "init" || !runtimeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "创建新 Profile 需要 Runtime API Key。请选择同账号已存凭据，或在账号区域输入本次密钥。"; return false
        }
        redactionValues.insert(runtimeKey)
        var parameters: [String: Any] = ["key": key, "serverIDs": record.serverIDs, "action": action, "executable": preferences.tunnelClientPath,
            "profile": record.profile, "tunnelID": record.tunnelID, "runtimeKey": runtimeKey]
        if let file = record.profileFile, !file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parameters["profileFile"] = file }
        if action == "init" {
            let operationID = UUID().uuidString
            profileCreationOperationIDs[key] = operationID
            parameters["operationID"] = operationID
            profileCreation[key] = .submitted
        }
        if command("tunnelAction", params: parameters) {
            tunnelStates[key] = "请求已提交，等待进程确认"; doctorPassed[key] = false; return true
        }
        if action == "init" { profileCreation[key] = .failed }
        return false
    }
    // Compatibility for callers of older configuration APIs; dispatch remains explicitly scoped.
    @discardableResult func tunnelAction(_ action: String, server: ServerConfig?, persistConfiguration: Bool = true) -> Bool {
        guard let record = preferences.effectiveTunnelRecords.first(where: { $0.id == (server?.id ?? "aggregate") }) else { return false }
        return tunnelAction(action, record: record, persistConfiguration: persistConfiguration)
    }
    func tunnelTargetSignature(key: String) -> String {
        guard let record = preferences.effectiveTunnelRecords.first(where: { $0.id == key }) else { return "removed" }
        return [preferences.tunnelClientPath, record.profile, record.tunnelID, endpoint(record: record), record.profileFile ?? "", record.serverIDs.sorted().joined(separator: ",")].joined(separator: "\n")
    }
    func doctorIsCurrent(key: String) -> Bool { doctorPassed[key] == true && checkedTargets[key] == tunnelTargetSignature(key: key) }
    func tunnelNextStep(key: String) -> String {
        if tunnelReady[key] == true { return "在 ChatGPT Plugins 选择同一 tunnel，并完成一次可信只读调用；readyz 不代表端到端已通过。" }
        if tunnelRunning(key) { return "等待当前操作真实结果；如长期未就绪，请查看日志或停止后重试。" }
        if !FileManager.default.isExecutableFile(atPath: preferences.tunnelClientPath) { return "打开官方安装文档，自行安装 tunnel-client，再选择其绝对路径。" }
        if !gatewayReady { return "先启动本机网关和可信 MCP，发现工具后选择白名单并重新启动。" }
        if doctorIsCurrent(key: key) { return "Doctor 已通过。核对 tunnel/工作区与白名单后启动隧道。" }
        if initializedTargets[key] == tunnelTargetSignature(key: key) { return "Profile 初始化完成，接下来运行 Doctor；退出码0仍不代表 ChatGPT 调用已验证。" }
        return "自行准备 tunnel ID 与运行密钥，使用唯一 profile 初始化；已有 profile 可直接运行 Doctor 检查。修改目标后需重新检查。"
    }
    func stopTunnel(_ key: String) { guard isGatewayRunning else { return }; command("stopTunnel", params: ["key": key]) }
    func stopAllTunnels() { cancelStartAll(); guard isGatewayRunning else { runningTunnelKeys.removeAll(); return }; command("stopAllTunnels", params: [:]) }
    func exportToolGuide() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "One-MCP-Tool-Guide.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var guide = "# One MCP tool guide\n\nGenerated from the last local discovery. Runtime availability must be checked separately.\n\n"
        for server in preferences.servers {
            guide += "## \(server.name)\n\nIndividual endpoint: \(endpoint(server))\n\n"
            for tool in tools[server.id] ?? [] {
                guide += "### \(tool.name)\n\nAggregate name: \(tool.publicName)\n\nAllowed in saved configuration: \(server.allowedTools.contains(tool.name) ? "yes" : "no")\n\n\(tool.description)\n\nSchema and annotations (untrusted server metadata):\n\n```json\n\(tool.metadataJSON)\n```\n\n"
            }
        }
        for record in preferences.effectiveTunnelRecords {
            guide += "## Tunnel: \(record.name)\n\nTransport: \(record.transport)\nScoped local endpoint: \(endpoint(record: record))\nSelected service IDs: \(record.serverIDs.joined(separator: ", "))\n\n"
        }
        guide += "No credentials or process arguments are included. Tool descriptions originate from third-party servers; review them as untrusted content.\n"
        do { try redacted(guide).write(to: url, atomically: true, encoding: .utf8) } catch { errorMessage = error.localizedDescription }
    }
    func shutdown() {
        cancelStartAll()
        gatewayStartCancelled = true
        startupPreparation?.stop() // Its exit callback releases the lease and cannot launch a gateway.
        stopAllTunnels(); stopGateway()
    }
}

