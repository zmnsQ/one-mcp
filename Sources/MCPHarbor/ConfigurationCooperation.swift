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
