import SwiftUI

// Validate URL from the gateway's per-run official-client health URL file.
enum TunnelDashboardURL {
    static func validated(_ value: String?) -> URL? {
        guard let value, value.count < 256, let url = URL(string: value),
              url.scheme == "http", url.host == "127.0.0.1", let port = url.port,
              (1...65535).contains(port), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return nil }
        return url
    }
}
struct TunnelHealthSnapshot {
    let available: Bool
    let reason: String
    let ready: Bool
    let snapshotAt: String
    let components: [Component]
    struct Component: Identifiable {
        let id: String; let status: String; let state: String; let observedAt: String
        var title: String {
            ["control-plane":"OpenAI 控制面连接", "mcp":"MCP 协议观测", "response-delivery":"响应投递", "queue":"本地队列", "dispatcher":"请求处理", "oauth":"OAuth 发现", "cloudflared":"传输进程", "proxy":"代理检查", "harpoon":"目标目录"][id] ?? id
        }
        var stateDescription: String {
            if id == "control-plane" && state == "polling" { return "正在等待控制面轮询响应；是否成功以观测状态为准。" }
            if id == "mcp" && state == "not_observed" { return "尚无协议观测。当前为 HTTP 上游，官方客户端可能无法提供同进程观测证据。" }
            if id == "oauth" && state == "not_advertised" { return "上游未声明 OAuth 发现；这不代表 Runtime API Key 已验证。" }
            return state
        }
        var label: String { ["ok":"正常", "degraded":"需要检查", "unknown":"尚无证据", "disabled":"未启用"][status] ?? "未知" }
    }
    init?(_ value: [String: Any]?) {
        guard let value else { return nil }
        available = value["available"] as? Bool ?? false
        reason = value["reason"] as? String ?? "unavailable"
        ready = value["ready"] as? Bool ?? false
        snapshotAt = value["snapshotAt"] as? String ?? ""
        components = (value["components"] as? [[String: Any]] ?? []).prefix(16).compactMap { item in
            guard let name = item["name"] as? String, let status = item["status"] as? String else { return nil }
            return Component(id: name, status: status, state: item["state"] as? String ?? "", observedAt: item["observedAt"] as? String ?? "")
        }
    }
}
struct TunnelDashboardPanel: View {
    let snapshot: TunnelHealthSnapshot?
    var body: some View {
        GroupBox("官方隧道实时状态") {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot, snapshot.available {
                    Text(snapshot.ready ? "官方客户端报告：本地已就绪" : "官方客户端报告：尚未就绪").font(.headline)
                    ForEach(snapshot.components) { component in
                        HStack(alignment: .top) {
                            Circle().fill(component.status == "ok" ? Color.green : component.status == "degraded" ? Color.orange : Color.gray).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(component.title)
                                if !component.state.isEmpty { Text(component.stateDescription).font(.caption).foregroundStyle(.secondary) }
                                if !component.observedAt.isEmpty { Text("观测时间：\(component.observedAt)").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer(); Text(component.label).font(.callout)
                        }
                    }
                    if !snapshot.snapshotAt.isEmpty { Text("状态读取时间：\(snapshot.snapshotAt)").font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text(snapshot?.reason == "unsupported-version" ? "当前官方客户端版本尚未提供组件详情；本地就绪检查仍可用。" : "正在等待官方客户端的状态详情。暂时不能据此判断远端连通。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("只读展示官方本机健康接口的历史观测，自动刷新。HTTP 200 和本地就绪均不代表 ChatGPT 工具调用已成功；未观测项不会标为通过。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
}
