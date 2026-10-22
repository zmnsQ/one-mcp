import Foundation

/// Deliberately stores only locally generated summaries of recognized events.
/// Never persists upstream stdout/stderr, arguments, results, credentials or URLs.
struct ServiceLogEntry: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let level: String
    let text: String
}

struct ServiceLogBuffer {
    static let defaultLimit = 300
    private(set) var entries: [String: [ServiceLogEntry]] = [:]
    private var snapshotCursors: [String: Int] = [:]
    private var snapshotInstances: [String] = []
    let limit: Int
    init(limit: Int = ServiceLogBuffer.defaultLimit) { self.limit = max(1, min(limit, 1000)) }
    func lines(for serverID: String) -> [ServiceLogEntry] { entries[serverID] ?? [] }
    mutating func clear(serverID: String) { entries[serverID] = nil }
    mutating func retain(serverIDs: Set<String>) { entries = entries.filter { serverIDs.contains($0.key) } }

    /// Require exact stable IDs, never display-name or substring matching.
    mutating func ingest(_ event: [String: Any], knownServerIDs: Set<String>, now: Date = Date()) {
        guard let id = event["serverId"] as? String, knownServerIDs.contains(id),
              let summary = Self.summary(event) else { return }
        guard entries[id] != nil || entries.count < 32 else { return }
        var lines = entries[id] ?? []
        lines.append(ServiceLogEntry(time: now, level: summary.0, text: summary.1))
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        entries[id] = lines
    }

    /// Independent from the connection cursor: reconnecting or clearing visible logs
    /// must not replay the same events. Limit retained gateway identities as well.
    mutating func ingestSnapshot(_ event: [String: Any], instanceID: String, sequence: Int,
                                 knownServerIDs: Set<String>, now: Date = Date()) {
        guard !instanceID.isEmpty, instanceID.utf8.count <= 128, sequence > 0,
              sequence > (snapshotCursors[instanceID] ?? 0) else { return }
        if snapshotCursors[instanceID] == nil {
            snapshotInstances.append(instanceID)
            if snapshotInstances.count > 8 {
                snapshotCursors.removeValue(forKey: snapshotInstances.removeFirst())
            }
        }
        snapshotCursors[instanceID] = sequence
        ingest(event, knownServerIDs: knownServerIDs, now: now)
    }

    static func summary(_ event: [String: Any]) -> (String, String)? {
        switch event["type"] as? String {
        case "serverStatus":
            switch event["status"] as? String {
            case "starting": return ("状态", "正在启动服务并连接 MCP。")
            case "running": return ("状态", "服务运行中，MCP 已连接。")
            case "stopping": return ("状态", "正在停止服务。")
            case "stopped": return ("状态", "服务已停止。")
            case "error", "failed":
                if event["message"] as? String == "MCP process or connection closed" { return ("错误", "MCP 进程退出或连接意外关闭。") }
                return ("错误", "服务启动或连接失败。")
            default: return nil
            }
        case "serviceCall":
            switch event["outcome"] as? String {
            case "started": return ("调用", "开始调用已授权工具。")
            case "succeeded": return ("调用", "工具调用完成。")
            case "failed":
                switch event["reason"] as? String {
                case "timeout": return ("错误", "工具调用超时。")
                case "cancelled": return ("错误", "工具调用已取消（客户端断开或服务停止）。")
                case "tool_error": return ("错误", "工具返回失败结果。")
                default: return ("错误", "上游工具调用发生错误。")
                }
            default: return nil
            }
        case "log":
            switch event["message"] as? String {
            case "Upstream stderr received; hidden to protect credentials":
                return ("诊断", "收到服务标准错误输出；原文已隐藏，避免泄露凭据与私密数据。")
            case "Upstream protocol error; payload hidden to protect private data":
                return ("错误", "MCP 协议错误；原始消息已隐藏。")
            case "Tool catalogue refresh failed; tools hidden until discovery succeeds":
                return ("错误", "工具目录刷新失败；发现成功前暂停公开工具。")
            default: return nil // Arbitrary text can contain secrets, even after regex redaction.
            }
        default: return nil
        }
    }
}
