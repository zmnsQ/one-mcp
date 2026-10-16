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
