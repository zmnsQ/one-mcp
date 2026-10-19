import Foundation

// No secrets in defaults. The service/account remains the legacy stable Keychain
// identity so rebuilding into a timestamped app directory does not change it.
struct TunnelCredentialPolicy {
    static func account(workspace: String) -> String { workspace + ":__tunnel_key" }
    static func preference(workspace: String) -> String { "OneMCP.autofillTunnelKey.v1." + workspace }
    static func shouldAutofill(enabled: Bool, current: String) -> Bool { enabled && current.isEmpty }
}

@MainActor extension HarborStore {
    var remembersTunnelKey: Bool { UserDefaults.standard.bool(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID)) }
    func saveAndRememberTunnelKey() {
        guard !tunnelKey.isEmpty else { tunnelCredentialStatus = "请先输入要保存的 Runtime API Key。"; return }
        do {
            try SecretVault.write(tunnelKey, account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID))
            UserDefaults.standard.set(true, forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID))
            tunnelCredentialStatus = "已保存到此 Mac 钥匙串；本工作空间下次打开会自动填入。"
        } catch { tunnelCredentialStatus = "未能保存到钥匙串。请检查系统授权后重试。" }
    }
    func autofillRememberedTunnelKey() {
        for record in preferences.effectiveTunnelRecords { loadRecordTunnelKey(record.id, allowInteraction: false) }
        tunnelCredentialStatus = remembersTunnelKey ? "已启用本工作空间自动填入。" : "仅本次会话使用。"
        guard TunnelCredentialPolicy.shouldAutofill(enabled: remembersTunnelKey, current: tunnelKey) else { return }
        do {
            if let value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID), allowInteraction: false) {
                tunnelKey = value; tunnelCredentialStatus = "已从本机钥匙串自动填入。"
            } else { tunnelCredentialStatus = "钥匙串中未找到已保存的密钥，请重新输入并保存。" }
        } catch { tunnelCredentialStatus = "钥匙串尚未允许当前版本读取。点击“从钥匙串载入”，按 macOS 提示授权。" }
    }
    func loadRememberedTunnelKey() {
        do {
            if let value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID)) {
                tunnelKey = value; tunnelCredentialStatus = "已从本机钥匙串载入。"
            } else { tunnelCredentialStatus = "本工作空间尚未保存 Runtime API Key。" }
        } catch { tunnelCredentialStatus = "钥匙串载入未完成，当前会话值保持不变。" }
    }
    func forgetRememberedTunnelKey() {
        do {
            try SecretVault.delete(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID))
            UserDefaults.standard.removeObject(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID))
            tunnelKey = ""; tunnelCredentialStatus = "已忘记本工作空间的已存密钥。正在运行的隧道不受影响；服务端密钥未撤销。"
        } catch { tunnelCredentialStatus = "钥匙串删除未完成，自动填入设置保持不变。" }
    }
}

extension TunnelCredentialPolicy {
    static func account(workspace: String, record: String) -> String { workspace + ":__tunnel_record:" + record }
    static func preference(workspace: String, record: String) -> String { "OneMCP.autofillTunnelRecord.v1." + workspace + "." + record }
}

@MainActor extension HarborStore {
    func saveRecordTunnelKey(_ id: String) {
        guard let value = recordTunnelKeys[id], !value.isEmpty else { return }
        do {
            try SecretVault.write(value, account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: id))
            UserDefaults.standard.set(true, forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id))
            UserDefaults.standard.removeObject(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id) + ".ignoreLegacy")
            tunnelCredentialStatus = "此隧道密钥已保存到本机钥匙串。"
        } catch { tunnelCredentialStatus = "未能保存到钥匙串。" }
    }
    func loadRecordTunnelKey(_ id: String, allowInteraction: Bool = true) {
        let enabled = UserDefaults.standard.bool(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id))
        let legacy = !UserDefaults.standard.bool(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id) + ".ignoreLegacy") && (id == "aggregate" || preferences.servers.contains(where: { $0.id == id }))
        guard allowInteraction || ((enabled || (legacy && remembersTunnelKey)) && (recordTunnelKeys[id] ?? "").isEmpty) else { return }
        do {
            var value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: id), allowInteraction: allowInteraction)
            // Legacy entries are read only, never moved or deleted during migration.
            if value == nil && legacy {
                value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID), allowInteraction: allowInteraction)
            }
            if let value { recordTunnelKeys[id] = value; tunnelCredentialStatus = "已从本机钥匙串载入。" }
        } catch { tunnelCredentialStatus = "钥匙串读取未完成；可点击载入并按 macOS 提示授权。" }
    }
    func forgetRecordTunnelKey(_ id: String) {
        do {
            try SecretVault.delete(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: id))
            UserDefaults.standard.removeObject(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id))
            UserDefaults.standard.set(true, forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id) + ".ignoreLegacy")
            recordTunnelKeys[id] = ""
            tunnelCredentialStatus = "已删除此隧道的新格式密钥；旧版工作空间密钥保留，服务端密钥未撤销。"
        } catch { tunnelCredentialStatus = "钥匙串删除未完成。" }
    }
}
