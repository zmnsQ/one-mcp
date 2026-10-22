import Foundation

/// Only semantic facts belong here: never raw command arguments, error payloads or configuration values.
enum ActivitySource: String { case user = "用户", ai = "AI", system = "系统", external = "外部更新（来源未确认）" }
enum ActivityOutcome: String { case saved = "草稿已保存", pending = "待应用", applied = "已生效", failed = "失败" }
struct ActivityRecord: Identifiable, Equatable {
    let id: String
    let time: Date
    let source: ActivitySource
    let action: String
    let object: String
    let outcome: ActivityOutcome
    let details: [String]
    var summary: String { action + " · " + object }
}

enum ActivityPolicy {
    static let limit = 80
    /// Known app-authored notices are safe verbatim; unknown transport text is not echoed.
    static func noticeDetail(_ value: String) -> String {
        let known: Set<String> = [
            "工具选择已保存，服务下次启动时生效。",
            "工具选择已保存，正在等待运行组件确认；其他进程配置未应用。",
            "工具选择已保存，但运行状态未确认；请核对当前已生效的工具后重试。",
            "配置已保存。",
            "已修复运行组件位置。没有安装软件或启动服务。",
            "已填入客户端路径，请核对后保存。未运行该程序。",
            "已添加使用此 Profile 的隧道记录。请选择要绑定的 MCP 服务，再核对并保存；凭据仍留在原位置。",
            "共享网关连接已结束。可点击启动服务重新连接，不会自动重发操作。",
            "工具目录较大，界面已省略部分元数据或目录。运行中的工具及白名单未改变；请勿依据不完整目录重新设置权限。",
            "旧网关退出未确认，未启动新实例。可重新连接检查。",
            "旧网关已停止，但配置在等待期间发生变化。请核对后启动服务。",
            "旧网关已安全退出，正在启动新版网关。原有 MCP 和隧道不会自动重启。",
            "已创建工作空间。",
            "已删除此工作空间的全部 Keychain 凭据（含已移除服务器引用）。",
            "配置已导入；env 值已丢弃、白名单已清空，没有启动任何程序。请核查参数中是否含秘密。",
            "已导出配置，不含 env 值或 Keychain。参数已尽力脱敏，请在分享前检查。",
            "配置已保存；运行中的服务不变。工具选择可单独应用，进程与连接配置需重启相关服务后生效。",
            "工具选择已在网关生效，无需停止服务；在途调用继续完成。客户端需刷新工具列表，未刷新的客户端请重新连接。其他进程配置未应用。",
        ]
        if known.contains(value) { return value }
        let countedPatterns = [
            #"^已明确保存 [0-9]{1,5} 项凭据到此工作空间的 macOS Keychain。$"#,
            #"^已从此工作空间 Keychain 载入 [0-9]{1,5} 项凭据。环境变量按服务器隔离；旧版共享变量凭据不会自动复用，请重新输入并明确保存。$"#,
            #"^已合并 [0-9]{1,5} 个 MCP，原有配置保留。新增白名单为空，env 值未导入，也未启动程序。请核对参数并分别填写会话凭据。$"#
        ]
        if countedPatterns.contains(where: { value.range(of: $0, options: .regularExpression) != nil }) { return value }
        return "运行连接有更新。请查看运行状态；未展示外部消息中的原始命令或敏感内容。"
    }

    /// Labels are untrusted configuration, too. Reject command-like, path, URL and secret-looking labels.
    static func label(_ value: String, fallback: String) -> String {
        guard !value.isEmpty, value.count <= 96,
              value.range(of: #"(?i)(bearer|token|secret|password|api.?key|sk-|https?://|[/\\=;$`<>]|--|[\r\n])"#, options: .regularExpression) == nil,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return fallback }
        return value
    }
    static func append(_ item: ActivityRecord, to records: inout [ActivityRecord]) {
        guard !records.contains(where: { $0.id == item.id }) else { return }
        records.insert(item, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
    }
    static func configurationChanges(from old: Preferences, to new: Preferences) -> [(String, String, [String])] {
        var changes: [(String, String, [String])] = []
        for server in new.servers {
            let name = label(server.name, fallback: "MCP 服务")
            guard let previous = old.servers.first(where: { $0.id == server.id }) else {
                changes.append(("添加服务", name, ["配置已保存，没有自动启动服务。"])); continue
            }
            if previous.allowedTools != server.allowedTools {
                let before = Set(previous.allowedTools), after = Set(server.allowedTools)
                changes.append(("修改工具选择", name, ["新增开放 \(after.subtracting(before).count) 项，取消开放 \(before.subtracting(after).count) 项。", "仅保存选择；运行权限以网关确认结果为准。"] ))
            }
            var fields: [String] = []
            if previous.name != server.name { fields.append("显示名称") }
            if previous.executable != server.executable || previous.arguments != server.arguments || previous.workingDirectory != server.workingDirectory || previous.cli != server.cli || previous.kind != server.kind { fields.append("启动配置") }
            if previous.environmentKeys != server.environmentKeys { fields.append("环境变量引用") }
            if previous.startWithAll != server.startWithAll { fields.append("全部启动参与设置") }
            if previous.tunnelID != server.tunnelID || previous.profile != server.profile { fields.append("隧道关联") }
            if !fields.isEmpty { changes.append(("修改服务配置", name, ["变更项目：" + fields.joined(separator: "、") + "。", "没有自动启动或重启服务。"] )) }
        }
        for server in old.servers where !new.servers.contains(where: { $0.id == server.id }) {
            changes.append(("移除服务配置", label(server.name, fallback: "MCP 服务"), ["配置中已移除；运行状态需另行核对。"] ))
        }
        for record in new.effectiveTunnelRecords {
            let previous = old.effectiveTunnelRecords.first(where: { $0.id == record.id })
            if previous != record { changes.append((previous == nil ? "添加隧道配置" : "修改隧道配置", label(record.name, fallback: "隧道"), ["关联、连接或参与设置已保存；没有自动连接或重启隧道。"] )) }
        }
        for record in old.effectiveTunnelRecords where !new.effectiveTunnelRecords.contains(where: { $0.id == record.id }) {
            changes.append(("移除隧道配置", label(record.name, fallback: "隧道"), ["已从保存的配置移除。"] ))
        }
        if old.port != new.port || old.nodePath != new.nodePath || old.gatewayScript != new.gatewayScript || old.tunnelClientPath != new.tunnelClientPath || old.remoteConnection != new.remoteConnection || old.mode != new.mode {
            changes.append(("修改网关配置", "本地网关", ["网络、连接或运行配置已保存；没有自动重启网关。"] ))
        }
        return changes
    }
}
