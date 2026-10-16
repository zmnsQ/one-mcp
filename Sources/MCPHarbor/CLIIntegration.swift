import Foundation
import Darwin
import CryptoKit

struct DiscoveredClient: Codable, Identifiable { let id: String; let path: String; let source: String; let version: String? }
struct DiscoveredProfile: Codable, Identifiable { let id: String; let path: String; let name: String; let tunnelID: String?; let endpoint: String?; let source: String }
struct EnvironmentDiscovery: Codable { let clients: [DiscoveredClient]; let profiles: [DiscoveredProfile]; let warnings: [String] }

@MainActor extension HarborStore {
    var controlSocketURL: URL { storageRoot.appendingPathComponent("Runtime/control.sock") }
    func acquireConfigurationLease() {
        do {
            try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let attributes = try FileManager.default.attributesOfItem(atPath: storageRoot.path)
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else { throw CocoaError(.fileWriteNoPermission) }
            let lock = storageRoot.appendingPathComponent(".configuration-lock")
            guard mkdir(lock.path, 0o700) == 0 else { throw NSError(domain: "OneMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "配置正被另一进程使用。关闭另一窗口或 CLI 后重新打开；崩溃残留锁请用 CLI 检查后恢复。"] ) }
            let token = UUID().uuidString
            do {
                let data = try JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "token": token])
                try data.write(to: lock.appendingPathComponent("owner.json"), options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.appendingPathComponent("owner.json").path)
                configurationLeaseToken = token
            } catch { try? FileManager.default.removeItem(at: lock); throw error }
        } catch { errorMessage = error.localizedDescription }
    }
    func releaseConfigurationLease() {
        guard let token = configurationLeaseToken else { return }
        let lock = storageRoot.appendingPathComponent(".configuration-lock")
        if let data = try? Data(contentsOf: lock.appendingPathComponent("owner.json")),
           let owner = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], owner["token"] as? String == token {
            try? FileManager.default.removeItem(at: lock.appendingPathComponent("owner.json"))
            _ = rmdir(lock.path)
        }
        configurationLeaseToken = nil
    }
    func configurationRevision() -> String {
        guard let data = try? Data(contentsOf: activeConfigurationURL) else { return "missing" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func detectEnvironment() {
        guard !discoveryBusy else { return }
        resolveRuntimePaths()
        checkSetup()
        guard runtimeFilesReady else { discoveryError = runtimeSetupSummary; return }
        let script = URL(fileURLWithPath: preferences.gatewayScript).deletingLastPathComponent().appendingPathComponent("cli.js")
        guard FileManager.default.isReadableFile(atPath: script.path) else { discoveryError = "应用的环境检测组件缺失，请重新构建完整应用。"; return }
        discoveryBusy = true; discoveryError = nil
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("onemcp-discovery-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let output = try? FileHandle(forWritingTo: outputURL) else { discoveryBusy = false; discoveryError = "无法准备检测结果文件。"; return }
        process.executableURL = URL(fileURLWithPath: preferences.nodePath)
        process.arguments = [script.path, "environment", "inspect", "--json"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            try? output.close()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            try? FileManager.default.removeItem(at: outputURL)
            Task { @MainActor in
                guard let self else { return }
                self.discoveryBusy = false
                guard process.terminationStatus == 0, data.count <= 1_048_576,
                      let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let result = envelope["result"], let body = try? JSONSerialization.data(withJSONObject: result),
                      let discovery = try? JSONDecoder().decode(EnvironmentDiscovery.self, from: body) else {
                    self.discoveryError = "环境检测未完成；请检查 Node、网关构建和配置。"; return
                }
                self.environmentDiscovery = discovery
            }
        }
        do { try process.run() } catch { try? output.close(); try? FileManager.default.removeItem(at: outputURL); discoveryBusy = false; discoveryError = "无法启动检测程序。"; return }
        Task { try? await Task.sleep(nanoseconds: 15_000_000_000); if process.isRunning { process.terminate() } }
    }
    func applyDiscoveredClient(_ client: DiscoveredClient) {
        guard !anyProcessRunning else { return }
        preferences.tunnelClientPath = client.path
        notice = "已填入客户端路径，请核对后保存。未运行该程序。"
    }
    func applyDiscoveredProfile(_ profile: DiscoveredProfile) {
        guard !anyProcessRunning, let id = profile.tunnelID, !id.isEmpty else { return }
        preferences.aggregateProfile = profile.name
        preferences.aggregateProfileFile = profile.path
        preferences.aggregateTunnelID = id
        notice = "已填入聚合出口名称和 ID，请核对后保存。现有认证仍留在原位置。"
    }
}
