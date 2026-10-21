import Foundation
import Security
import AppKit

struct WorkspaceRecord: Codable, Identifiable {
    var id: String
    var name: String
}
struct WorkspaceIndex: Codable {
    var activeID: String
    var workspaces: [WorkspaceRecord]
}
struct CheckResult: Identifiable {
    let id = UUID()
    let label: String
    let passed: Bool
    let detail: String
}

enum SecretVault {
    private static let service = "local.mcpharbor.runtime"
    static func write(_ value: String, account: String) throws {
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = key.merging(attributes) { _, value in value }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw vaultError(status) }
    }
    static func read(account: String, allowInteraction: Bool = true) throws -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw vaultError(status) }
        return String(data: data, encoding: .utf8)
    }
    static func delete(account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw vaultError(status) }
    }
    static func accounts(prefix: String) throws -> [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw vaultError(status) }
        return (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
    }
    private static func vaultError(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain 错误 \(status)"])
    }
}

/// Explicitly rejects redirects so health checks cannot leave the local endpoint.
final class LocalOnlySessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor extension HarborStore {
    var storageRoot: URL { fileURL.deletingLastPathComponent() }
    var workspaceDirectory: URL { storageRoot.appendingPathComponent("Workspaces", isDirectory: true) }
    var activeConfigurationURL: URL { currentWorkspaceID == "default" ? fileURL : workspaceDirectory.appendingPathComponent(currentWorkspaceID + ".json") }
    var anyProcessRunning: Bool { isGatewayRunning || startAllBusy || gatewayStartBusy || !runningTunnelKeys.isEmpty || takeoverBusy }
    func bootstrapWorkspaces() {
        let indexURL = storageRoot.appendingPathComponent("workspaces.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let index = try JSONDecoder().decode(WorkspaceIndex.self, from: Data(contentsOf: indexURL))
                guard !index.workspaces.isEmpty,
                      Set(index.workspaces.map(\.id)).count == index.workspaces.count,
                      index.workspaces.allSatisfy({ $0.id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil && !$0.name.isEmpty }),
                      index.workspaces.contains(where: { $0.id == index.activeID }) else { throw CocoaError(.fileReadCorruptFile) }
                workspaces = index.workspaces
                currentWorkspaceID = index.activeID
            } catch {
                errorMessage = "工作空间索引损坏；已保留原文件。请导入有效配置恢复。"
                storageReadable = false
            }
        }
        if workspaces.isEmpty { workspaces = [.init(id: "default", name: "默认工作空间")] }
        if currentWorkspaceID != "default" {
            do { preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: activeConfigurationURL)); storageReadable = true }
            catch { errorMessage = "工作空间配置无法读取，已保留原文件。"; storageReadable = false }
        }
        selectedID = preferences.servers.first?.id
        savedRevision = configurationRevision()
        checkSetup()
    }
    func backupBeforeRecovery() throws {
        let folder = storageRoot.appendingPathComponent("Recovery-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for path in Set([fileURL, activeConfigurationURL, storageRoot.appendingPathComponent("workspaces.json")]) where FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.copyItem(at: path, to: folder.appendingPathComponent(path.lastPathComponent))
        }
    }
    func persistWorkspaceIndex(activeID: String? = nil) throws {
        guard configurationLeaseToken != nil else { throw CocoaError(.fileWriteNoPermission) }
        try requireCurrentWorkspaceIndex()
        let data = try JSONEncoder().encode(WorkspaceIndex(activeID: activeID ?? currentWorkspaceID, workspaces: workspaces))
        try data.write(to: storageRoot.appendingPathComponent("workspaces.json"), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageRoot.appendingPathComponent("workspaces.json").path)
        savedIndexRevision = revision(of: data)
    }
    @discardableResult func createWorkspace(name: String) -> Bool {
        guard !anyProcessRunning else { errorMessage = "请先停止所有进程，再创建或切换工作空间。"; return false }
        guard !FileManager.default.fileExists(atPath: controlSocketURL.path) else { errorMessage = "请先停止使用此目录的网关，再创建工作空间。"; return false }
        acquireConfigurationLease()
        guard configurationLeaseToken != nil else { return false }
        defer { releaseConfigurationLease() }
        guard !FileManager.default.fileExists(atPath: controlSocketURL.path) else { errorMessage = "网关已启动，请先停止后再创建工作空间。"; return false }
        do { try requireCurrentWorkspaceIndex() } catch { errorMessage = error.localizedDescription; return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if storageReadable && !save() { return false }
        if !storageReadable { do { try backupBeforeRecovery() } catch { errorMessage = error.localizedDescription; return false } }
        let oldPreferences = preferences, oldSaved = savedPreferences
        let oldID = currentWorkspaceID, oldWorkspaces = workspaces, oldReadable = storageReadable, oldRevision = savedRevision
        let record = WorkspaceRecord(id: UUID().uuidString.lowercased(), name: name)
        workspaces.append(record); currentWorkspaceID = record.id
        preferences.servers = []; preferences.tunnelRecords = []; preferences.aggregateTunnelID = ""; preferences.aggregateProfileFile = nil; preferences.remoteConnection = nil
        preferences.aggregateProfile = "mcpharbor-" + String(record.id.prefix(8))
        storageReadable = true
        savedRevision = configurationRevision()
        guard save() else {
            preferences = oldPreferences; savedPreferences = oldSaved; currentWorkspaceID = oldID; savedRevision = oldRevision
            workspaces = oldWorkspaces; storageReadable = oldReadable
            return false
        }
        do { try persistWorkspaceIndex() } catch {
            preferences = oldPreferences; savedPreferences = oldSaved; currentWorkspaceID = oldID; savedRevision = oldRevision
            workspaces = oldWorkspaces; storageReadable = oldReadable
            errorMessage = "工作空间索引未保存，新配置文件已保留但未启用：\(error.localizedDescription)"; return false
        }
        clearRuntimeState(); checkSetup()
        notice = "已创建工作空间。"
        return true
    }
    func switchWorkspace(_ id: String) {
        guard id != currentWorkspaceID else { return }
        guard !anyProcessRunning else { errorMessage = "请先停止所有进程，再切换工作空间。"; return }
        guard workspaces.contains(where: { $0.id == id }) else { return }
        guard !FileManager.default.fileExists(atPath: controlSocketURL.path) else { errorMessage = "请先停止使用此目录的网关，再切换工作空间。"; return }
        acquireConfigurationLease()
        guard configurationLeaseToken != nil else { return }
        defer { releaseConfigurationLease() }
        let target = id == "default" ? fileURL : workspaceDirectory.appendingPathComponent(id + ".json")
        do {
            guard !FileManager.default.fileExists(atPath: controlSocketURL.path) else { errorMessage = "网关已启动，请先停止后再切换工作空间。"; return }
            try requireCurrentWorkspaceIndex()
            if storageReadable && !save() { return }
            let data = try Data(contentsOf: target)
            let loaded = try JSONDecoder().decode(Preferences.self, from: data)
            try validatePreferences(loaded, requireInstalled: false)
            try persistWorkspaceIndex(activeID: id)
            currentWorkspaceID = id; preferences = loaded; resolveRuntimePaths(); savedPreferences = preferences; storageReadable = true; savedRevision = revision(of: data)
            clearRuntimeState(); selectedID = preferences.servers.first?.id; checkSetup()
        } catch { errorMessage = "工作空间未切换：\(error.localizedDescription)" }
    }
    func clearRuntimeState() {
        healthTasks.values.forEach { $0.cancel() }; healthTasks = [:]; tunnelHealthURLs = [:]; tunnelHealthSnapshots = [:]; cloudflarePublicURL = nil; recordCloudflarePublicURLs = [:]; requestTraces = []; connectionEvents = []
        clearPendingCommands(); gateway = nil; tunnels = [:]; gatewayState = "Stopped"
        runtimeValues = [:]; tunnelKey = ""; recordTunnelKeys = [:]; recordTunnelKeyAccountIDs = [:]; redactionValues = []; tools = [:]; states = [:]; tunnelStates = [:]; tunnelMenuStates = [:]
        logs = []; notice = nil; toolChanges = [:]; selectedID = nil; doctorPassed = [:]; tunnelReady = [:]; initializedTargets = [:]; checkedTargets = [:]; profileCreation = [:]; profileCreationOperationIDs = [:]
    }
    private var vaultAccounts: [String] {
        preferences.servers.flatMap { server in server.environmentKeys.map { credentialKey(serverID: server.id, variable: $0) } } + ["__tunnel_key"] + preferences.effectiveTunnelRecords.map { "__tunnel_record:" + $0.id }
    }
    func saveCredentialsToKeychain() {
        do {
            try validatePreferences(preferences, requireInstalled: false)
            var count = 0
            for key in vaultAccounts {
                if key.hasPrefix("__tunnel_record:") {
                    let id = String(key.dropFirst("__tunnel_record:".count))
                    guard preferences.effectiveTunnelRecords.first(where: { $0.id == id })?.credentialSourceRecordID == nil,
                          !(recordTunnelKeys[id] ?? "").isEmpty else { continue }
                    guard saveRecordTunnelKey(id, remember: false) else {
                        throw NSError(domain: "MCPHarbor", code: 12, userInfo: [NSLocalizedDescriptionKey: tunnelCredentialStatus])
                    }
                    count += 1; continue
                }
                let value = key == "__tunnel_key" ? tunnelKey : (runtimeValues[key] ?? "")
                if !value.isEmpty {
                    try SecretVault.write(value, account: currentWorkspaceID + ":" + key)
                    if key == "__tunnel_key" { invalidateLegacyRecordCredentialAssociations() }
                    count += 1
                }
            }
            notice = "已明确保存 \(count) 项凭据到此工作空间的 macOS Keychain。"
        } catch { errorMessage = error.localizedDescription }
    }
    func loadCredentialsFromKeychain() {
        do {
            var count = 0
            for key in vaultAccounts {
                if key.hasPrefix("__tunnel_record:") {
                    if loadRecordTunnelKey(String(key.dropFirst("__tunnel_record:".count))) { count += 1 }
                    continue
                }
                if let value = try SecretVault.read(account: currentWorkspaceID + ":" + key) {
                    if key == "__tunnel_key" { tunnelKey = value }
                    else { runtimeValues[key] = value }; count += 1
                }
            }
            notice = "已从此工作空间 Keychain 载入 \(count) 项凭据。环境变量按服务器隔离；旧版共享变量凭据不会自动复用，请重新输入并明确保存。"
        } catch { errorMessage = error.localizedDescription }
    }
    func deleteSavedCredentials() {
        do {
            for key in try SecretVault.accounts(prefix: currentWorkspaceID + ":") { try SecretVault.delete(account: key) }
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("OneMCP.autofillTunnelRecord.v1." + currentWorkspaceID + ".") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.removeObject(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID))
            tunnelCredentialStatus = "已关闭自动填入并删除已存密钥。"
            notice = "已删除此工作空间的全部 Keychain 凭据（含已移除服务器引用）。"
        } catch { errorMessage = error.localizedDescription }
    }
    func validatePreferences(_ value: Preferences, requireInstalled: Bool = true) throws {
        func invalid(_ text: String) -> Error { NSError(domain: "MCPHarbor", code: 12, userInfo: [NSLocalizedDescriptionKey: text]) }
        if let issue = RemoteConnectionValidation.issue(value.remoteConnection) { throw invalid(issue) }
        let records = value.effectiveTunnelRecords
        guard records.count <= 32, Set(records.map(\.id)).count == records.count else { throw invalid("隧道最多32个，ID不可重复。") }
        for record in records {
            guard record.id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
                  !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, record.name.count <= 100,
                  ["openai", "cloudflare"].contains(record.transport), record.serverIDs.count <= 16,
                  Set(record.serverIDs).count == record.serverIDs.count,
                  record.serverIDs.allSatisfy({ id in value.servers.contains { $0.id == id } }) else { throw invalid("隧道名称、ID、连接方式或服务绑定无效。") }
            if let account = record.accountID {
                guard TunnelCredentialReferencePolicy.normalizedAccountID(account) != nil,
                      account.utf16.count <= 100 else { throw invalid("账号标识须为 1–100 个字符，不得为空白或包含空字符。") }
            }
            if let source = record.credentialSourceRecordID {
                guard source.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
                    throw invalid("密钥来源记录 ID 无效。")
                }
            }
            if let issue = RemoteConnectionValidation.issue(RemoteConnectionSettings(cloudflare: record.cloudflare)) { throw invalid(issue) }
        }
        guard (1024...65535).contains(value.port), value.servers.count <= 16 else { throw invalid("端口应为1024–65535，服务器最多16个。") }
        guard Set(value.servers.map(\.id)).count == value.servers.count else { throw invalid("服务器ID重复。") }
        for server in value.servers {
            if let issue = CLIConfigurationValidation.issue(server, requireTools: requireInstalled) { throw invalid(issue) }
            guard server.id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw invalid("服务器ID无效。") }
            guard server.allowedTools.count <= 500, Set(server.allowedTools).count == server.allowedTools.count, server.allowedTools.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 && $0 != "*" }) else { throw invalid("工具白名单包含重复、空名称或过多条目。") }
            guard !server.name.isEmpty, server.name.count <= 100 else { throw invalid("服务器名称须为1–100字。") }
            guard server.arguments.count <= 128, server.arguments.allSatisfy({ $0.utf8.count < 8192 }) else { throw invalid("命令参数过多或过长。") }
            guard Set(server.environmentKeys).count == server.environmentKeys.count,
                  server.environmentKeys.allSatisfy({ $0 != "__tunnel_key" && $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil }) else { throw invalid("环境变量名称重复或无效。") }
            if requireInstalled {
                guard server.executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: server.executable) else { throw invalid("\(server.name)：请选择已安装可执行文件的绝对路径。") }
                if !server.workingDirectory.isEmpty {
                    var isDirectory: ObjCBool = false
                    guard server.workingDirectory.hasPrefix("/"), FileManager.default.fileExists(atPath: server.workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else { throw invalid("\(server.name)：工作目录不存在。") }
                }
            }
        }
    }
    func checkSetup() {
        var results: [CheckResult] = []
        for (name, path) in [("Node", preferences.nodePath), ("官方 tunnel-client", preferences.tunnelClientPath)] {
            let valid = path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path)
            results.append(.init(label: name, passed: valid, detail: valid ? "找到可执行文件；版本尚未运行检查" : "请选择已安装程序的绝对路径"))
        }
        let script = preferences.gatewayScript
        let missing = RuntimeEnvironment.missingFiles(for: script)
        results.append(.init(label: "应用运行组件", passed: missing.isEmpty, detail: missing.isEmpty ? "网关、检测程序及依赖完整" : "缺少组件：" + missing.joined(separator: "、")))
        results.append(.init(label: "本机端口", passed: (1024...65535).contains(preferences.port), detail: "\(preferences.port) · 是否被占用以启动结果为准"))
        for server in preferences.servers {
            let good = server.executable.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: server.executable)
            results.append(.init(label: server.name, passed: good, detail: good ? "可执行路径有效；MCP握手需单独启动" : "可执行路径无效"))
        }
        setupChecks = results
    }
    func choosePath(_ key: String) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch key { case "node": preferences.nodePath = url.path; case "gateway": preferences.gatewayScript = url.path; case "profile": preferences.aggregateProfileFile = url.path; default: preferences.tunnelClientPath = url.path }
        checkSetup()
    }
    func importConfiguration() {
        guard !anyProcessRunning else { errorMessage = "请先停止所有连接再导入。"; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: url)
            guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            var candidate = preferences
            if let native = try? JSONDecoder().decode(Preferences.self, from: data) {
                candidate = native
                // Imported exposures are never implicitly authorized.
                for i in candidate.servers.indices { candidate.servers[i].allowedTools = [] }
            } else {
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let servers = root["mcpServers"] as? [String: [String: Any]] else {
                    throw NSError(domain: "MCPHarbor", code: 10, userInfo: [NSLocalizedDescriptionKey: "支持 One MCP 配置或含 mcpServers 的 stdio JSON。"])
                }
                var imported: [ServerConfig] = []
                for (name, object) in servers.sorted(by: { $0.key < $1.key }) {
                    guard let command = object["command"] as? String else { continue }
                    var server = ServerConfig(); server.name = name; server.executable = command
                    server.arguments = object["args"] as? [String] ?? []
                    server.workingDirectory = object["cwd"] as? String ?? ""
                    server.environmentKeys = Array((object["env"] as? [String: Any] ?? [:]).keys).sorted()
                    imported.append(server)
                }
                guard !imported.isEmpty else { throw NSError(domain: "MCPHarbor", code: 11, userInfo: [NSLocalizedDescriptionKey: "未找到 stdio MCP。远程URL配置不会自动导入。"]) }
                candidate.servers = imported
            }
            for server in candidate.servers {
                guard ConfigurationDiscovery.redactCredentialArguments(server.arguments) == server.arguments,
                      ConfigurationDiscovery.redactText(server.executable) == server.executable,
                      ConfigurationDiscovery.redactText(server.workingDirectory) == server.workingDirectory else {
                    throw NSError(domain: "OneMCP.Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "配置中的命令/参数/路径疑似包含凭据。请在源文件改用环境变量后重新导入；未复制这些凭据。"])
                }
            }
            try validatePreferences(candidate, requireInstalled: false)
            if !storageReadable { try backupBeforeRecovery() }
            let previous = preferences, previousSaved = savedPreferences, previousReadable = storageReadable
            preferences = candidate; storageReadable = true
            guard save() else { preferences = previous; savedPreferences = previousSaved; storageReadable = previousReadable; return }
            clearRuntimeState(); selectedID = preferences.servers.first?.id; checkSetup()
            notice = "配置已导入；env 值已丢弃、白名单已清空，没有启动任何程序。请核查参数中是否含秘密。"
        } catch { errorMessage = "导入失败：\(error.localizedDescription)" }
    }
    func scrubArguments(_ arguments: [String]) -> [String] {
        var hideNext = false
        return arguments.map { argument in
            if hideNext { hideNext = false; return "[REDACTED: use an environment variable]" }
            if argument.range(of: "(?i)^--?(api[-_]?key|token|secret|password|credential|authorization)$", options: .regularExpression) != nil { hideNext = true }
            var text = redacted(argument)
            if let regex = try? NSRegularExpression(pattern: "(?i)(--?(?:api[-_]?key|token|secret|password|credential)=)[^\\s]+") {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1[REDACTED]")
            }
            return text
        }
    }
    func exportConfiguration() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "One-MCP-Configuration.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var safe = preferences
            for i in safe.servers.indices { safe.servers[i].arguments = scrubArguments(safe.servers[i].arguments) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(safe).write(to: url, options: .atomic)
            notice = "已导出配置，不含 env 值或 Keychain。参数已尽力脱敏，请在分享前检查。"
        } catch { errorMessage = error.localizedDescription }
    }
    func exportLogs() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "One-MCP-Activity.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = logs.map { "\($0.time.ISO8601Format()) [\($0.source)] \(redacted($0.text))" }.joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { errorMessage = error.localizedDescription }
    }
}

