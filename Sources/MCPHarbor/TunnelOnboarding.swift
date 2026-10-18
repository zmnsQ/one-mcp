import Foundation

/// Public documentation only. Never construct help URLs from configuration or credentials.
enum TunnelHelp {
    static let setup = URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!
    static let installation = URL(string: "https://github.com/openai/tunnel-client#readme")!
    static let tunnels = URL(string: "https://platform.openai.com/settings/organization/tunnels")!
    static let runtimeKeys = URL(string: "https://platform.openai.com/settings/organization/api-keys")!
    static let permissions = URL(string: "https://github.com/openai/tunnel-client/blob/master/docs/permissions.md")!
    static let plugins = URL(string: "https://chatgpt.com/plugins")!
    static let oauth = URL(string: "https://developers.openai.com/plugins/build/auth")!
    static let cloudflare = URL(string: "https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/create-local-tunnel/")!
    static let cloudflareInstall = URL(string: "https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/")!
}

/// Presence is a setup hint, never evidence that a credential was accepted remotely.
enum TunnelSetupHints {
    static func credential(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "尚未输入；已有 Profile 提供凭据时可留空"
            : "已输入本次会话密钥，权限尚待检查"
    }
    static func tunnel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "等待在 Platform 创建或选择 Tunnel"
            : "已填写 Tunnel ID，工作区关联尚待核对"
    }
}
