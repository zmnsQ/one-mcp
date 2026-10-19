import Foundation

enum TunnelRecordPresentation {
    static func bindingSummary(_ record: TunnelRecord, servers: [ServerConfig]) -> String {
        guard !record.serverIDs.isEmpty else { return "尚未绑定 MCP 服务" }
        let names = record.serverIDs.map { id in servers.first(where: { $0.id == id })?.name ?? "已移除的服务" }
        let preview = names.prefix(2).joined(separator: "、")
        return names.count > 2 ? "\(preview) 等 \(names.count) 个 MCP" : preview
    }
    /// Apply the editor's draft atomically. The view separately checks workspace/revision
    /// and persists once; closing/cancelling the sheet never modifies preferences.
    static func applying(_ draft: TunnelRecord, isNew: Bool, to preferences: Preferences) throws -> Preferences {
        var record = draft
        record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !record.name.isEmpty, !record.serverIDs.isEmpty,
              Set(record.serverIDs).count == record.serverIDs.count,
              record.serverIDs.allSatisfy({ id in preferences.servers.contains(where: { $0.id == id }) }) else {
            throw NSError(domain: "OneMCP", code: 30, userInfo: [NSLocalizedDescriptionKey: "请填写名称，并选择有效的 MCP 服务。"])
        }
        var records = preferences.effectiveTunnelRecords
        if isNew {
            guard records.count < 32, !records.contains(where: { $0.id == record.id }) else {
                throw NSError(domain: "OneMCP", code: 31, userInfo: [NSLocalizedDescriptionKey: "隧道数量已达上限或记录已存在。"])
            }
            records.append(record)
        } else {
            guard let index = records.firstIndex(where: { $0.id == record.id }) else {
                throw NSError(domain: "OneMCP", code: 32, userInfo: [NSLocalizedDescriptionKey: "此隧道已被移除，请重新打开列表。"])
            }
            records[index] = record
        }
        var result = preferences; result.tunnelRecords = records
        return result
    }
}
