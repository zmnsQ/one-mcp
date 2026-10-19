import SwiftUI
import AppKit

struct RemoteConnectionSettingsView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false

    private var oauth: OAuthSettings { store.preferences.remoteConnection?.oauth ?? OAuthSettings() }
    private func oauthBinding<Value>(_ path: WritableKeyPath<OAuthSettings, Value>) -> Binding<Value> {
        Binding(get: { oauth[keyPath: path] }, set: { value in
            var remote = store.preferences.remoteConnection ?? RemoteConnectionSettings()
            var settings = remote.oauth ?? OAuthSettings(); settings[keyPath: path] = value
            remote.oauth = settings; store.preferences.remoteConnection = remote
        })
    }
    var body: some View {
        DisclosureGroup("共享 OAuth 认证设置（作用于整个网关）") {
            VStack(alignment: .leading, spacing: 18) {
                Text("所有隧道共用以下 issuer、JWKS 和 scope。每条隧道独立选择 OpenAI 或 Cloudflare，并仅公开所选服务。OAuth 修改需要保存并重启网关。")
                    .font(.callout).foregroundStyle(.secondary)
                oauthPanel
            }.padding(.top, 12)
        }
    }
    private var oauthPanel: some View {
        GroupBox("A · 先准备外部 OAuth 授权服务") {
            VStack(alignment: .leading, spacing: 12) {
                Text("由你的身份提供方处理登录、用户同意、客户端注册和 PKCE。OneMCP 作为资源服务器校验访问令牌，不提供登录账号或授权服务器。")
                    .font(.callout)
                Text("在身份提供方配置 MCP 资源的 audience、JWT access token（RFC 9068）和所需 scope，并按 ChatGPT 指南配置客户端与回调。请从该提供方的官方元数据复制 issuer 和 JWKS 地址。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("查看 OAuth 与客户端配置要求", destination: TunnelHelp.oauth)
                labeledField("MCP 公开地址（完整端点）", placeholder: "https://mcp.example.com/mcp", text: oauthBinding(\.publicURL))
                labeledField("授权服务 issuer", placeholder: "https://identity.example.com", text: oauthBinding(\.issuer))
                labeledField("签名公钥 JWKS URL", placeholder: "https://identity.example.com/.well-known/jwks.json", text: oauthBinding(\.jwksURL))
                labeledField("要求的 scope（多个用空格分隔）", placeholder: "mcp:tools", text: oauthBinding(\.scope))
                Toggle("启用 OAuth 令牌校验（保存并重启网关后生效）", isOn: oauthBinding(\.enabled))
                if store.isGatewayRunning, store.appliedGatewayFingerprints["oauthEnabled"] == nil {
                    Text("当前网关未提供 OAuth 生效证据。请使用支持此功能的网关版本，并重启后核对。")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !store.gatewayRestartReasons.filter({ $0.hasPrefix("OAuth") }).isEmpty {
                    Label("OAuth 已保存修改，待明确重启网关后生效", systemImage: "arrow.clockwise.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("支持签名 JWT access token；不接受 ID token 或不透明 token。这里仅保存公开元数据和权限名称。不要粘贴 client secret、访问令牌或私钥。启用后也需要在 ChatGPT 完成登录并实际调用工具，才能验证授权。")
                    .font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).padding(12)
        }
    }
    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).accessibilityLabel(title)
        }
    }
}
