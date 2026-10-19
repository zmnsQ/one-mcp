import SwiftUI

struct TunnelOnboardingGuide: View {
    @EnvironmentObject private var store: HarborStore
    var body: some View {
        GroupBox("1 · 准备好本机工具与 OpenAI 工作区") {
            VStack(alignment: .leading, spacing: 14) {
                Text("先在本机选好工具，再为每条隧道选择要公开的 MCP 服务。已有 Tunnel 或 Profile 可以直接复用。")
                    .font(.callout).foregroundStyle(.secondary)
                Label(store.gatewayReady ? "本机网关已就绪" : "点击顶部“启动网关”准备本机入口", systemImage: store.gatewayReady ? "checkmark.circle" : "1.circle")
                Label(store.preferences.servers.contains(where: { !$0.allowedTools.isEmpty }) ? "已选择工具白名单；请核对运行中的权限" : "在“MCP 服务”添加可信服务，发现工具并选择白名单", systemImage: "list.bullet.clipboard")
                Text("创建 Tunnel 需要 Platform 组织的 Tunnels Read + Manage；运行客户端和选择 Tunnel 需要 Read + Use。还需 ChatGPT 工作区允许添加和使用自定义 MCP。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("查看权限要求", destination: TunnelHelp.permissions)
                    Link("完整设置指南", destination: TunnelHelp.setup)
                }.font(.callout)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}

struct TunnelAccountGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没有 Tunnel ID 或密钥？")
                .font(.headline)
            Text("① 打开 Platform 隧道设置，确认右上方是目标组织。创建或选择一个 Tunnel，把要使用它的 ChatGPT 工作区加入关联，再复制完整 Tunnel ID。")
                .font(.callout)
            Link("打开 Platform 隧道设置", destination: TunnelHelp.tunnels)
            Text("② 打开同一组织的 Runtime API keys，创建专用运行密钥。使用受限权限，并确认密钥所属身份有 Tunnels Read + Use。只把运行密钥粘贴到对应隧道记录的安全输入框。")
                .font(.callout)
            Link("创建 Runtime API Key", destination: TunnelHelp.runtimeKeys)
            Text("管理密钥用于创建和管理隧道，不能代替这里的运行密钥。不要把密钥放进 Tunnel ID、Profile 名称、URL 或日志。若页面没有所需权限，请联系组织管理员。")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TunnelVerificationGuide: View {
    var body: some View {
        GroupBox("4 · 在 ChatGPT 完成一次真实调用") {
            VStack(alignment: .leading, spacing: 12) {
                Text("保持隧道运行。在 ChatGPT Plugins 添加自定义 MCP，Connection 选择 Tunnel，选中相同的 Tunnel ID，然后按服务要求设置认证。")
                    .font(.callout)
                Link("打开 ChatGPT Plugins", destination: TunnelHelp.plugins)
                Text("先测试一个可信的只读工具。只有 ChatGPT 实际返回了正确结果，才算整条连接完成；本机网关、Doctor 和 readyz 的通过只是各自的检查结果。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("分清三个不同的设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Runtime API Key：让官方客户端连接 OpenAI 隧道控制面。")
                        Text("OAuth：让使用 MCP 的人登录并授权，由 MCP 资源服务器和外部授权服务共同校验。")
                        Text("Cloudflare：为服务提供公网 HTTPS 入口；Cloudflare 连接凭据不等于 OAuth 用户授权。")
                        Text("OpenAI 私有隧道可转发上游 OAuth 发现，但不会自动创建授权服务器。浏览器登录的授权地址必须可达。")
                        Link("OAuth 官方指南", destination: TunnelHelp.oauth)
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}
