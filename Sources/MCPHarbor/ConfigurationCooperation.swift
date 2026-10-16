import Foundation
import CryptoKit

enum ConfigurationReloadDecision: Equatable {
    case unchanged, reload, preserveEdits, deferUntilStopped
    static func decide(saved: String, disk: String, dirty: Bool, running: Bool) -> Self {
        if saved == disk { return .unchanged }
        if dirty { return .preserveEdits }
        return running ? .deferUntilStopped : .reload
    }
}

@MainActor extension HarborStore {
    func loadInitialConfiguration() {
        initialReadAttempts += 1
        storageReadable = false
        let indexURL = storageRoot.appendingPathComponent("workspaces.json")
        do {
            func bytes(_ url: URL) throws -> Data? {
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let data = try Data(contentsOf: url)
                guard data.count <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
                return data
            }
            let indexData = try bytes(indexURL)
            let index = try indexData.map { try JSONDecoder().decode(WorkspaceIndex.self, from: $0) }
                ?? WorkspaceIndex(activeID: "default", workspaces: [.init(id: "default", name: "默认工作空间")])
            guard !index.workspaces.isEmpty,
                  Set(index.workspaces.map(\.id)).count == index.workspaces.count,
                  index.workspaces.allSatisfy({ $0.id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil && !$0.name.isEmpty }),
                  index.workspaces.contains(where: { $0.id == index.activeID }) else { throw CocoaError(.fileReadCorruptFile) }
            let configURL = index.activeID == "default" ? fileURL : workspaceDirectory.appendingPathComponent(index.activeID + ".json")
            let configData = try bytes(configURL)
            guard configData != nil || index.activeID == "default" else { throw CocoaError(.fileNoSuchFile) }
            let loaded = try configData.map { try JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
            try validatePreferences(loaded, requireInstalled: false)
            // Read both files twice. A concurrent writer never gives this editor a newer
            // revision paired with older decoded bytes. Retry from the watcher if changed.
            guard indexData == (try bytes(indexURL)), configData == (try bytes(configURL)) else {
                externalConfigurationNotice = "配置正在更新，稍后自动载入。"; return
            }
            workspaces = index.workspaces; currentWorkspaceID = index.activeID
            preferences = loaded
            savedRevision = configData.map { revision(of: $0) } ?? "missing"
            savedIndexRevision = indexData.map { revision(of: $0) } ?? "missing"
            resolveRuntimePaths() // Memory-only; persisted on the next explicit save/start.
            savedPreferences = preferences
            selectedID = preferences.servers.first?.id
            storageReadable = true; initialConfigurationLoaded = true
            externalConfigurationNotice = nil
        } catch {
            storageReadable = false
            externalConfigurationNotice = "配置暂时无法读取，原文件未改动。可稍后点击载入磁盘版本重试。"
        }
    }
    func revision(of data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func diskRevision(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "missing" }
        return revision(of: data)
    }
    func releaseGatewayStartupLease() {
        guard let token = gatewayStartupLeaseToken else { return }
        if configurationLeaseToken == token { releaseConfigurationLease() }
        gatewayStartupLeaseToken = nil
    }
    func startConfigurationWatch() {
        configurationWatchTask?.cancel()
        configurationWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                self?.reloadExternalConfiguration()
            }
        }
    }
    func reloadExternalConfiguration(discardLocalChanges: Bool = false) {
        if !initialConfigurationLoaded {
            if discardLocalChanges { initialReadAttempts = 0; preferences = savedPreferences }
            guard !hasUnsavedChanges else {
                externalConfigurationNotice = "初次载入未完成，你的修改已保留。请确认后重新载入磁盘版本。"; return
            }
            guard initialReadAttempts < 5 else { return }
            loadInitialConfiguration(); checkSetup(); return
        }
        // No locks are held while waiting; a writer publishes a complete atomic snapshot.
        guard configurationLeaseToken == nil,
              !FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(".configuration-lock").path) else { return }
        guard let data = try? Data(contentsOf: activeConfigurationURL), data.count <= 1_048_576 else { return }
        let latest = revision(of: data)
        let decision = ConfigurationReloadDecision.decide(saved: savedRevision, disk: latest,
                                                          dirty: hasUnsavedChanges && !discardLocalChanges, running: anyProcessRunning)
        switch decision {
        case .unchanged: return
        case .preserveEdits:
            externalConfigurationNotice = "AI 已更新磁盘配置。你的未保存修改仍保留，请核对后选择是否载入磁盘版本。"
            return
        case .deferUntilStopped:
            externalConfigurationNotice = "AI 已保存新配置，运行中的服务保持原样。停止本应用服务后将载入新配置；不会自动重启。"
            return
        case .reload: break
        }
        do {
            let loaded = try JSONDecoder().decode(Preferences.self, from: data)
            try validatePreferences(loaded, requireInstalled: false)
            preferences = loaded; savedPreferences = loaded; savedRevision = latest; storageReadable = true
            if !preferences.servers.contains(where: { $0.id == selectedID }) { selectedID = preferences.servers.first?.id }
            externalConfigurationNotice = nil
            notice = "已同步 AI 或另一窗口保存的配置。没有启动或重启服务。"
            checkSetup()
        } catch { externalConfigurationNotice = "外部配置未通过校验，当前界面内容已保留。" }
    }
    func requireCurrentWorkspaceIndex() throws {
        guard savedIndexRevision == diskRevision(storageRoot.appendingPathComponent("workspaces.json")) else {
            throw NSError(domain: "OneMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "工作空间目录已被另一窗口更新，请重新打开应用后选择。当前配置不会被覆盖。"])
        }
    }
}
