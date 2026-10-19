import Foundation

struct StartAllStep: Identifiable {
    let id: String
    let title: String
    var detail = "等待启动"
    var status = "waiting"
}

@MainActor extension HarborStore {
    var startAllConfirmation: String {
        let selected = preferences.servers.filter(\.participatesInStartAll).map(\.name).joined(separator: "、")
        let records = preferences.effectiveTunnelRecords.filter(\.participatesInStartAll)
        let targets = records.map(\.name).joined(separator: "、")
        var disclosure = ""
        if records.contains(where: { $0.transport == "openai" }) {
            disclosure += "OpenAI 隧道会将所选 MCP 的白名单工具接入所配置的工作区，数据与结果会发送到 OpenAI。"
        }
        if records.contains(where: { $0.transport == "cloudflare" }) {
            disclosure += "Cloudflare 连接会将所选 MCP 的白名单工具提供给获 OAuth 授权的客户端，数据与结果经过 Cloudflare。"
        }
        return "启动网关、MCP（\(selected.isEmpty ? "无" : selected)）及隧道（\(targets.isEmpty ? "无" : targets)）？MCP 程序具有你账户的文件与服务权限。\(disclosure)已运行项保持原样，待重启配置不会自动应用；不会创建账号、profile、密钥或隧道，也不会修改白名单。"
    }
    func updateStartAll(_ id: String, _ status: String, _ detail: String) {
        guard let index = startAllSteps.firstIndex(where: { $0.id == id }) else { return }
        startAllSteps[index].status = status; startAllSteps[index].detail = detail
    }
    func refreshStartAllTunnel(_ event: [String: Any]) {
        guard let key = event["key"] as? String, event["action"] as? String == "run",
              let index = startAllSteps.firstIndex(where: { $0.id == "tunnel:" + key }),
              !["waiting", "skipped"].contains(startAllSteps[index].status) else { return }
        if let message = event["message"] as? String, event["errorCode"] != nil {
            updateStartAll("tunnel:" + key, "failed", redacted(message))
        } else if event["running"] as? Bool == false {
            updateStartAll("tunnel:" + key, "failed", "隧道已退出；请在连接日志检查原因，修正后可再次全部启动")
        } else if event["ready"] as? Bool == true {
            updateStartAll("tunnel:" + key, "succeeded", preferences.effectiveTunnelRecords.first(where: { $0.id == key })?.transport == "cloudflare" ? "Cloudflare 元数据可达；OAuth 登录和工具调用仍需验证" : "隧道连接已就绪；ChatGPT 端到端调用仍需验证")
        }
    }
    func cancelStartAll() {
        startAllTask?.cancel()
        // Already submitted operations may still finish. Never clear their pending markers.
        for index in startAllSteps.indices where ["waiting", "starting"].contains(startAllSteps[index].status) {
            startAllSteps[index].status = "skipped"
            startAllSteps[index].detail = "已取消后续启动；已提交的操作不回滚，请查看实际状态"
        }
    }
    func startAll(expectedPlan: Preferences? = nil, expectedWorkspace: String? = nil, expectedRevision: String? = nil) {
        guard !startAllBusy, !takeoverBusy else { return }
        guard expectedPlan == nil || expectedPlan == preferences,
              expectedWorkspace == nil || expectedWorkspace == currentWorkspaceID,
              expectedRevision == nil || expectedRevision == savedRevision else {
            errorMessage = "确认期间配置已改变，请重新查看全部启动内容后确认。"; return
        }
        guard initialConfigurationLoaded, storageReadable, !hasUnsavedChanges else {
            errorMessage = "请先保存或载入磁盘配置，再全部启动；不会自动覆盖未保存修改。"; return
        }
        guard configurationRevision() == savedRevision,
              !FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(".configuration-lock").path) else {
            errorMessage = "磁盘配置已更新或正在保存，请先载入最新配置再全部启动。"; return
        }
        let plan = preferences, workspace = currentWorkspaceID
        startAllRevision = savedRevision
        startAllSteps = [.init(id: "gateway", title: "本机网关")]
        startAllSteps += plan.servers.map { .init(id: "server:" + $0.id, title: $0.name) }
        startAllSteps += plan.effectiveTunnelRecords.map { .init(id: "tunnel:" + $0.id, title: $0.name) }
        startAllBusy = true
        startAllTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                for index in self.startAllSteps.indices where self.startAllSteps[index].status == "waiting" {
                    self.startAllSteps[index].status = "skipped"
                    self.startAllSteps[index].detail = "前置条件未完成或配置已变化，未启动"
                }
                self.startAllBusy = false; self.startAllTask = nil; self.startAllRevision = nil
            }
            await self.runStartAll(plan: plan, workspace: workspace)
        }
    }
    private func bulkContextIsCurrent(_ plan: Preferences, _ workspace: String) -> Bool {
        !Task.isCancelled && currentWorkspaceID == workspace && preferences == plan && !hasUnsavedChanges &&
        startAllRevision == configurationRevision() &&
        (configurationLeaseToken != nil || !FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(".configuration-lock").path))
    }
    private func submitBulkCommand(_ plan: Preferences, _ workspace: String, action: () -> Bool) -> Bool {
        let ownedLease = configurationLeaseToken == nil
        if ownedLease { acquireConfigurationLease() }
        guard configurationLeaseToken != nil else { return false }
        defer { if ownedLease { releaseConfigurationLease() } }
        guard bulkContextIsCurrent(plan, workspace) else {
            errorMessage = "配置已改变，未提交后续启动。请载入并核对后重试。"; return false
        }
        return action()
    }
    private func waitForBulk(_ plan: Preferences, _ workspace: String, timeout: TimeInterval = 75,
                             until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard bulkContextIsCurrent(plan, workspace) else { return false }
            if condition() { return true }
            if gatewayState == "Disconnected" || gatewayState.hasPrefix("Stopped") { return false }
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return false }
        }
        return false
    }
    private func runStartAll(plan: Preferences, workspace: String) async {
        guard bulkContextIsCurrent(plan, workspace) else { return }
        updateStartAll("gateway", "starting", "正在启动或连接网关")
        if !gatewayReady && !isGatewayRunning && !gatewayStartBusy { startGateway(persistConfiguration: false) }
        guard await waitForBulk(plan, workspace, until: { self.gatewayReady }) else {
            updateStartAll("gateway", "failed", errorMessage ?? "网关未就绪或配置已变化，后续项未启动"); return
        }
        updateStartAll("gateway", "succeeded", gatewayRestartReasons.isEmpty ? "网关已就绪" : "使用现有网关；已保存修改仍待重启")
        for server in plan.servers {
            let key = "server:" + server.id
            guard bulkContextIsCurrent(plan, workspace), gatewayReady else { return }
            guard server.participatesInStartAll else { updateStartAll(key, "skipped", "未参与全部启动"); continue }
            if states[server.id] == "running" { updateStartAll(key, "skipped", "已运行，保持当前配置"); continue }
            if hasPendingCommand(for: server.id) || states[server.id] == "starting" {
                updateStartAll(key, "skipped", "已有启动或操作待确认，未重复提交"); continue
            }
            updateStartAll(key, "starting", "正在启动 MCP")
            let before = Set(pendingCommands.keys)
            guard submitBulkCommand(plan, workspace, action: { self.startServer(server, persistConfiguration: false) }), let request = Set(pendingCommands.keys).subtracting(before).first else {
                updateStartAll(key, "failed", errorMessage ?? "启动请求未提交"); continue
            }
            let finished = await waitForBulk(plan, workspace, until: {
                self.commandResults[request] != nil && (self.commandResults[request] != "ok" || self.states[server.id] == "running")
            })
            guard !Task.isCancelled else { return }
            let result = commandResults.removeValue(forKey: request)
            updateStartAll(key, finished && result == "ok" ? "succeeded" : "failed",
                           finished && result == "ok" ? "MCP 已运行" : (result.flatMap { $0 == "ok" ? nil : $0 } ?? "未确认启动结果；不自动重发，请查看实际状态"))
        }
        guard bulkContextIsCurrent(plan, workspace), gatewayReady else { return }
        for record in plan.effectiveTunnelRecords {
            guard bulkContextIsCurrent(plan, workspace), gatewayReady else { return }
            let target = record.id, key = "tunnel:" + target
            guard record.participatesInStartAll else { updateStartAll(key, "skipped", "未参与全部启动"); continue }
            if tunnelRunning(target) || hasPendingCommand(for: target) {
                updateStartAll(key, "skipped", "隧道已运行或有操作待确认，未重复提交"); continue
            }
            let configuredServerIDs = Set(plan.servers.map(\.id))
            guard !record.serverIDs.isEmpty,
                  record.serverIDs.allSatisfy({ configuredServerIDs.contains($0) && states[$0] == "running" }) else {
                updateStartAll(key, "skipped", "所选 MCP 为空、已移除或尚未全部运行，未启动隧道"); continue
            }
            guard ["openai", "cloudflare"].contains(record.transport) else {
                updateStartAll(key, "failed", "不支持的隧道传输方式，请检查配置"); continue
            }
            let isCloudflare = record.transport == "cloudflare"
            if !isCloudflare, let reason = bulkTunnelPreflight(record, plan: plan) {
                updateStartAll(key, "failed", reason + "；请在 ChatGPT 连接中配置后重试"); continue
            }
            updateStartAll(key, "starting", isCloudflare ? "正在检查 OAuth 并启动已有 Cloudflare 配置" : "正在启动已有隧道配置")
            let before = Set(pendingCommands.keys)
            guard submitBulkCommand(plan, workspace, action: {
                if isCloudflare { return self.cloudflareAction("run", record: record, persistConfiguration: false) }
                return self.tunnelAction("run", record: record, persistConfiguration: false)
            }), let request = Set(pendingCommands.keys).subtracting(before).first else {
                updateStartAll(key, "failed", errorMessage ?? "隧道请求未提交"); continue
            }
            let finished = await waitForBulk(plan, workspace, until: {
                self.commandResults[request] != nil && (self.commandResults[request] != "ok" || self.tunnelRunning(target) || self.startAllSteps.first(where: { $0.id == key })?.status == "failed")
            })
            guard !Task.isCancelled else { return }
            let result = commandResults.removeValue(forKey: request)
            if startAllSteps.first(where: { $0.id == key })?.status == "failed" { continue }
            let successDetail = isCloudflare ? "Cloudflare 进程已启动；公网元数据、OAuth 登录和工具调用请分别验收" :
                (tunnelReady[target] == true ? "隧道连接已就绪；ChatGPT 调用仍需验证" : "隧道进程已启动；连接尚未就绪，请查看连接状态")
            updateStartAll(key, finished && result == "ok" ? "succeeded" : "failed",
                           finished && result == "ok" ? successDetail : (result.flatMap { $0 == "ok" ? nil : $0 } ?? "未确认隧道启动结果；不自动重发"))
        }
    }
    private func bulkTunnelPreflight(_ record: TunnelRecord, plan: Preferences) -> String? {
        let tunnel = record.tunnelID
        guard tunnel.range(of: "^tunnel_[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return "缺少有效 Tunnel ID" }
        guard FileManager.default.isExecutableFile(atPath: plan.tunnelClientPath) else { return "未找到可执行 tunnel-client" }
        if let file = record.profileFile, !file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard file.hasPrefix("/"), RuntimeEnvironment.readableFile(file) else { return "Profile 文件不可读取" }
        } else {
            let profile = record.profile
            guard profile.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return "缺少有效 Profile 名称" }
        }
        return nil
    }
}

