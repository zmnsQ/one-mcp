import Foundation
import AppKit

@MainActor extension HarborStore {
    func discoverSelectedConfigurations() {
        guard !anyProcessRunning else { errorMessage = "请先停止所有连接再发现和导入配置。"; return }
        let panel = NSOpenPanel()
        panel.title = "选择你允许读取的 MCP 配置文件"
        panel.message = "可多选 Claude Desktop、Cursor、Cline 等 mcpServers JSON，或 VS Code mcp.json。不会扫描其他路径，不会导入 env 值。"
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        guard panel.urls.count <= 32 else { errorMessage = "一次最多选择32个配置文件。"; return }
        var seen = Set(preferences.servers.map(ConfigurationDiscovery.fingerprint))
        var candidates: [ImportCandidate] = []
        for url in panel.urls {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard size.isRegularFile == true, (size.fileSize ?? 0) <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                let found = try ConfigurationDiscovery.candidates(data: data, source: url.path, seen: &seen)
                if found.isEmpty { candidates.append(.init(source: url.path, name: url.lastPathComponent, server: nil, issue: "文件没有服务器条目。", warning: nil)) }
                candidates.append(contentsOf: found)
            } catch {
                candidates.append(.init(source: url.path, name: url.lastPathComponent, server: nil, issue: "读取/解析失败：" + redacted(error.localizedDescription), warning: nil))
            }
        }
        importCandidates = candidates; selectedImportIDs = []; showImportPreview = true
    }
    func cancelImportPreview() { showImportPreview = false; importCandidates = []; selectedImportIDs = [] }
    func mergeSelectedCandidates() {
        guard !anyProcessRunning else { errorMessage = "请先停止所有连接再导入。"; return }
        guard storageReadable else { errorMessage = "现有配置不可读，请先使用恢复导入或创建新工作空间。"; return }
        var seen = Set(preferences.servers.map(ConfigurationDiscovery.fingerprint))
        let selected = importCandidates.filter { $0.canSelect && selectedImportIDs.contains($0.id) }
        var added: [ServerConfig] = []
        for candidate in selected {
            guard var server = candidate.server, seen.insert(ConfigurationDiscovery.fingerprint(server)).inserted else { continue }
            server.allowedTools = []; server.tunnelID = ""; server.profile = ""
            added.append(server)
        }
        guard !added.isEmpty else { errorMessage = "请选择至少一个未重复的候选。"; return }
        guard preferences.servers.count + added.count <= 16 else { errorMessage = "合并后超过16个服务器，请减少选择；现有配置未变更。"; return }
        let previous = preferences, previousSaved = savedPreferences
        preferences.servers.append(contentsOf: added)
        do { try validatePreferences(preferences, requireInstalled: false) }
        catch { preferences = previous; errorMessage = error.localizedDescription; return }
        guard save() else { preferences = previous; savedPreferences = previousSaved; return }
        selectedID = added.first?.id
        cancelImportPreview(); checkSetup()
        notice = "已合并 \(added.count) 个 MCP，原有配置保留。新增白名单为空，env 值未导入，也未启动程序。请核对参数并分别填写会话凭据。"
    }
}
