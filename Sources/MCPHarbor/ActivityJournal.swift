import Foundation

@MainActor extension HarborStore {
    func recordActivity(id: String = UUID().uuidString, source: ActivitySource, action: String,
                        object: String, outcome: ActivityOutcome, details: [String] = []) {
        ActivityPolicy.append(ActivityRecord(id: id, time: Date(), source: source, action: action,
            object: ActivityPolicy.label(redacted(object), fallback: "配置项目"), outcome: outcome, details: details), to: &activities)
    }
    func recordConfigurationActivity(from old: Preferences, to new: Preferences, source: ActivitySource, revision: String) {
        for (index, change) in ActivityPolicy.configurationChanges(from: old, to: new).enumerated() {
            recordActivity(id: "configuration:\(currentWorkspaceID):\(revision):\(index)", source: source,
                action: change.0, object: change.1, outcome: .saved, details: change.2)
        }
    }
    func recordObservedServerActivity(serverID: String, previous: String?, status: String?) {
        guard let status, previous != status, ["running", "stopped", "error"].contains(status) else { return }
        let object = preferences.servers.first(where: { $0.id == serverID })?.name ?? "MCP 服务"
        recordActivity(source: .system, action: status == "running" ? "服务已启动" : status == "stopped" ? "服务已停止" : "服务运行异常",
            object: object, outcome: status == "error" ? .failed : .applied,
            details: ["来自网关状态事件；不推断操作发起者。"])
    }
    /// Runtime acknowledgements are not attributed to AI unless a trusted transport proves that source.
    func recordCommandActivity(requestID: String, method: String, serverID: String?, succeeded: Bool) {
        let actions = ["updateAllowedTools": "应用工具选择", "startServer": "启动服务", "stopServer": "停止服务",
            "startTunnel": "连接隧道", "stopTunnel": "停止隧道", "startCloudflare": "连接隧道", "stopCloudflare": "停止隧道"]
        guard let action = actions[method] else { return }
        let object = preferences.servers.first(where: { $0.id == serverID })?.name
            ?? preferences.effectiveTunnelRecords.first(where: { $0.id == serverID })?.name ?? "本地网关"
        recordActivity(id: "command:\(requestID)", source: .user, action: action, object: object,
            outcome: succeeded ? (method == "updateAllowedTools" || method.hasPrefix("stop") ? .applied : .pending) : .failed,
            details: [succeeded ? "网关已确认此操作；当前连接状态请查看运行状态。" : "网关未确认成功，未将保存状态当作运行生效。请查看运行状态后重试。"])
    }
}
