import SwiftUI
import AppKit

struct RemoteConnectionSettingsView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false

    private var oauth: OAuthSettings { store.preferences.remoteConnection?.oauth ?? OAuthSettings() }
    private var cloudflare: CloudflareSettings { store.preferences.remoteConnection?.cloudflare ?? CloudflareSettings() }
    private var busy: Bool { store.startAllBusy || store.hasPendingCommand(for: "transport:cloudflare") }
    private func oauthBinding<Value>(_ path: WritableKeyPath<OAuthSettings, Value>) -> Binding<Value> {
        Binding(get: { oauth[keyPath: path] }, set: { value in
            var remote = store.preferences.remoteConnection ?? RemoteConnectionSettings()
            var settings = remote.oauth ?? OAuthSettings(); settings[keyPath: path] = value
            remote.oauth = settings; store.preferences.remoteConnection = remote
        })
    }
    private func cloudflareBinding<Value>(_ path: WritableKeyPath<CloudflareSettings, Value>) -> Binding<Value> {
        Binding(get: { cloudflare[keyPath: path] }, set: { value in
            var remote = store.preferences.remoteConnection ?? RemoteConnectionSettings()
            var settings = remote.cloudflare ?? CloudflareSettings(); settings[keyPath: path] = value
            remote.cloudflare = settings; store.preferences.remoteConnection = remote
        })
    }
    private func approve(_ message: String, action: @escaping () -> Void) {
        confirmation = message; pendingAction = action; showConfirmation = true
    }
    private func confirmCloudflare(_ action: String, message: String) {
        let plan = store.preferences, workspace = store.currentWorkspaceID, revision = store.savedRevision
        approve(message) {
            guard store.preferences == plan, store.currentWorkspaceID == workspace, store.savedRevision == revision else {
                store.errorMessage = "确认期间配置已改变，请核对后重新确认 Cloudflare 操作。"; return
            }
            store.cloudflareAction(action)
        }
    }
    var body: some View {
        DisclosureGroup("可选 · OAuth 与 Cloudflare 公网连接") {
            VStack(alignment: .leading, spacing: 18) {
                Text("OpenAI 私有隧道按上方步骤设置。需要用户登录，或改用 Cloudflare 公网入口时，再配置这里。保存配置不会创建授权服务、安装程序或发布公网地址。")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("顶部“全部启动”使用的连接", selection: Binding(get: {
                    store.preferences.remoteConnection?.preferredTransport ?? "openai"
                }, set: { value in
                    var remote = store.preferences.remoteConnection ?? RemoteConnectionSettings()
                    remote.preferredTransport = value; store.preferences.remoteConnection = remote
                })) {
                    Text("OpenAI 私有隧道").tag("openai")
                    Text("Cloudflare 公网入口").tag("cloudflare")
                }.pickerStyle(.segmented)
                oauthPanel
                cloudflarePanel
                if let issue = RemoteConnectionValidation.issue(store.preferences.remoteConnection) {
                    Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Text("这些设置与 AI 共用同一工作空间。保存后，OAuth 修改需明确停止并重新启动网关；Cloudflare 修改需明确重启对应连接。顶部“全部启动”仅启动上方选中的连接方式，并在启动前确认。选择方式不会停止已有连接。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 12)
        }
        .alert("确认公开连接", isPresented: $showConfirmation) {
            Button("取消", role: .cancel) { pendingAction = nil }
            Button("继续") { let action = pendingAction; pendingAction = nil; action?() }
        } message: { Text(confirmation) }
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
    private var cloudflarePanel: some View {
        GroupBox("B · Cloudflare HTTPS 入口") {
            VStack(alignment: .leading, spacing: 12) {
                Text("会把此网关的 MCP 入口提供给公网。先配置 OAuth，再在 Cloudflare 创建你拥有的域名与隧道映射；只有通过授权且在白名单中的工具才应可调用。")
                    .font(.callout)
                HStack {
                    Link("安装 cloudflared", destination: TunnelHelp.cloudflareInstall)
                    Link("创建本机管理的隧道", destination: TunnelHelp.cloudflare)
                }
                Picker("部署方式", selection: cloudflareBinding(\.mode)) {
                    Text("固定域名 · Named tunnel").tag("named")
                    Text("临时测试 · Quick tunnel").tag("quick")
                }.pickerStyle(.segmented)
                HStack {
                    labeledField("cloudflared 程序", placeholder: "/opt/homebrew/bin/cloudflared", text: cloudflareBinding(\.executable))
                    Button("选择…") { selectFile(for: \.executable, title: "选择已安装的 cloudflared 程序") }.padding(.top, 16)
                }
                if cloudflare.mode == "named" {
                    labeledField("Cloudflare Tunnel UUID", placeholder: "从 Cloudflare 复制完整 UUID", text: cloudflareBinding(\.tunnelID))
                    HStack {
                        labeledField("本机隧道凭据 JSON 文件", placeholder: "/绝对路径/tunnel-credentials.json", text: cloudflareBinding(\.credentialsFile))
                        Button("选择…") { selectFile(for: \.credentialsFile, title: "选择已创建的 Cloudflare 隧道凭据 JSON") }.padding(.top, 16)
                    }
                    Text("使用本机管理的隧道凭据文件；这里保存文件路径，不读取或导出凭据内容。Dashboard 提供的 token 不能粘贴进这些字段。")
                        .font(.caption).foregroundStyle(.secondary)
                    labeledField("固定 HTTPS 域名（不含 /mcp）", placeholder: "https://mcp.example.com", text: cloudflareBinding(\.publicURL))
                } else {
                    Text("Quick tunnel 只用于短期测试，地址每次可能改变，不支持 SSE。启动后还需在身份提供方把 audience 配成实际 MCP 地址，并重新连接 ChatGPT。正式使用请选择固定域名。")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let url = store.cloudflarePublicURL {
                    Text("本次公网入口：\(url)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Label(store.isGatewayRunning ? (store.tunnelStates["transport:cloudflare"] ?? "尚未启动 Cloudflare 连接") : "网关未连接，Cloudflare 状态待确认", systemImage: store.tunnelRunning("transport:cloudflare") ? "network" : "circle")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.tunnelRestartReasons("transport:cloudflare").isEmpty {
                    Label("已保存修改，待重启 Cloudflare：" + store.tunnelRestartReasons("transport:cloudflare").joined(separator: "、"), systemImage: "arrow.clockwise.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("检查 cloudflared") {
                        confirmCloudflare("doctor", message: "执行所选 cloudflared 的版本和配置检查？不会创建隧道、授权账号或发布公网入口。")
                    }.disabled(busy || store.tunnelRunning("transport:cloudflare") || !store.gatewayReady)
                    Button("启动公开连接") {
                        confirmCloudflare("run", message: "通过 Cloudflare 将此网关的 MCP 入口提供给公网？获授权客户端可调用白名单工具，数据与结果会经过 Cloudflare。请确认外部 OAuth、域名和工具权限已准备好；这不会创建账号或授予 Cloudflare 新权限。")
                    }.buttonStyle(.glassProminent).disabled(busy || store.tunnelRunning("transport:cloudflare") || !store.gatewayReady || !oauth.enabled)
                    Button("停止公开连接") {
                        approve("停止 Cloudflare 公开连接？通过此入口连接的客户端会断开，本机 MCP 和 OpenAI 隧道保留。") { store.stopTunnel("transport:cloudflare") }
                    }.disabled(!store.tunnelRunning("transport:cloudflare"))
                }
                Text("进程启动、取得网址或元数据可达，都不代表 OAuth 登录或工具调用成功。在 ChatGPT 添加 HTTPS MCP 地址，完成登录，再测试一次可信只读调用。")
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
    private func selectFile(for key: WritableKeyPath<CloudflareSettings, String>, title: String) {
        let panel = NSOpenPanel()
        panel.title = title; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cloudflareBinding(key).wrappedValue = url.path
    }
}
