import Foundation

@MainActor extension HarborStore {
    var supportsLiveToolSelection: Bool {
        appliedGatewayFingerprints["liveToolSelectionVersion"] == ConfigurationFingerprint.scalar("1")
    }

    /// Persist only this allowlist, leaving unrelated configuration drafts untouched.
    @discardableResult func saveToolSelection(_ serverID: String) -> Bool {
        guard let draft = preferences.servers.first(where: { $0.id == serverID }),
              let index = savedPreferences.servers.firstIndex(where: { $0.id == serverID }) else {
            errorMessage = "请先保存新增的服务配置，再应用工具选择。"; return false
        }
        let drafts = preferences
        var selectionOnly = savedPreferences
        selectionOnly.servers[index].allowedTools = draft.allowedTools
        preferences = selectionOnly
        defer { preferences = drafts }
        return save()
    }

    func applyToolSelection(_ serverID: String) {
        guard !startAllBusy, !hasPendingCommand(for: serverID) else { return }
        let state = states[serverID] ?? "stopped"
        guard !["starting", "stopping", "unknown"].contains(state) else {
            errorMessage = "服务状态尚未稳定，请稍后再应用工具选择。"; return
        }
        if state != "running" {
            guard saveToolSelection(serverID) else { return }
            notice = "工具选择已保存，服务下次启动时生效。"; return
        }
        guard gatewayReady, supportsLiveToolSelection else {
            errorMessage = "当前运行组件尚不支持工具热更新。更新组件并重启网关一次后，即可在运行中更改工具选择；当前权限未改变。"; return
        }
        guard let live = sharedRuntimeServers.first(where: { $0.id == serverID && $0.running && $0.permissionsKnown }) else {
            errorMessage = "暂时无法确认当前工具权限，未应用更改。请先重新连接网关核对状态。"; return
        }
        guard saveToolSelection(serverID), let saved = savedPreferences.servers.first(where: { $0.id == serverID }) else { return }
        if command("updateAllowedTools", params: ["serverId": serverID, "allowedTools": saved.allowedTools, "expectedAllowedTools": live.allowedTools]) {
            notice = "工具选择已保存，正在等待运行组件确认；其他进程配置未应用。"
        } else {
            notice = "工具选择已保存，但运行状态未确认；请核对当前已生效的工具后重试。"
        }
    }
}
