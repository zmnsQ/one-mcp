import SwiftUI
import AppKit

/// A read-only projection of the shared runtime. Actions use the existing store commands.
struct OverviewDashboard: View {
    @EnvironmentObject private var store: HarborStore
    let onAddService: () -> Void
    let onSelectService: (String) -> Void
    let onOpenTunnels: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void
    let confirm: (String, @escaping () -> Void) -> Void
    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)]
    private var runningServices: Int { store.menuServers.filter { store.menuServerStatus($0.id) == .running }.count }
    private var activeTunnels: Int { store.menuTunnelIDs.filter { [.running, .ready].contains(store.menuTunnelStatus($0)) }.count }
    private var failures: Int {
        store.menuServers.filter { store.menuServerStatus($0.id) == .failed }.count +
        store.menuTunnelIDs.filter { store.menuTunnelStatus($0) == .failed }.count +
        (store.menuGatewayStatus == .failed ? 1 : 0)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    metric("本地网关", value: store.menuGatewayStatus.title, icon: "network", color: store.menuGatewayStatus.color)
                    metric("MCP 服务运行", value: store.menuGatewayStatus == .unknown ? "未确认" : "\(runningServices) / \(store.menuServers.count)", icon: "shippingbox.fill", color: .blue)
                    metric("隧道运行", value: store.menuGatewayStatus == .unknown ? "未确认" : "\(activeTunnels) / \(store.menuTunnelIDs.count)", icon: "point.3.connected.trianglepath.dotted", color: .teal)
                    metric("异常", value: String(failures), icon: "exclamationmark.triangle.fill", color: failures > 0 ? .red : .secondary)
                }
                HStack(spacing: 12) {
                    Button("添加 MCP", systemImage: "plus") { onAddService() }.buttonStyle(.borderedProminent)
                    Button("添加 / 管理隧道", systemImage: "network") { onOpenTunnels() }
                    Button("查看诊断", systemImage: "waveform.path.ecg") { onOpenLogs() }
                    Spacer()
                    Text("本地就绪 ≠ 远端调用已验证").font(.caption).foregroundStyle(.secondary)
                }
                if !store.gatewayReady {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: store.menuGatewayStatus.symbol).foregroundStyle(store.menuGatewayStatus.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.menuGatewayStatus == .unknown ? "网关状态未确认" : "先准备本地网关").font(.headline)
                            Text(store.menuGatewayStatus == .unknown ? "界面未能确认共享网关状态，不代表后台服务已停止。" : "可以先添加服务和隧道。使用顶部启动网关，再明确启动需要的项目。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("运行环境") { onOpenSettings() }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
                if store.preferences.servers.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("三步连接你的工具").font(.title3.bold())
                        onboardingStep("1", title: "添加 MCP 服务", detail: "导入或填写工具程序；默认不会开放工具。")
                        onboardingStep("2", title: "启动并选择工具", detail: "确认程序来源，再选择允许调用的工具。")
                        onboardingStep("3", title: "创建独立隧道", detail: "选择 OpenAI 或 Cloudflare，明确绑定服务并验证连接。")
                        Button("添加第一个 MCP", action: onAddService).buttonStyle(.borderedProminent)
                    }.dashboardCard()
                }
                HStack { Text("MCP 服务").font(.title3.bold()); Spacer(); Text("独立管理 · 明确授权").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(store.preferences.servers) { server in serviceCard(server) }
                }
                HStack {
                    Text("独立隧道").font(.title3.bold()); Spacer()
                    Button("连接设置", action: onOpenTunnels)
                }
                TunnelRecordsView().environmentObject(store)
                Text("总览使用当前网关的状态事件，不会为显示卡片自动启动进程或创建公网入口。共享网关断开时，状态显示为未确认。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func metric(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).dashboardCard()
    }
    private func onboardingStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline).frame(width: 28, height: 28).background(Color.accentColor.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.medium); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func serviceCard(_ server: ServerConfig) -> some View {
        let status = store.menuServerStatus(server.id)
        let busy = store.hasPendingCommand(for: server.id) || store.startAllBusy || [.starting, .stopping].contains(status)
        let bindings = store.preferences.effectiveTunnelRecords.filter { $0.serverIDs.contains(server.id) }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "shippingbox.fill").foregroundStyle(.blue).font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name).font(.headline).lineLimit(2)
                    Text("已配置 \(server.allowedTools.count) 项授权工具 · \(bindings) 条隧道绑定").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            StatusBadge(status: status)
            if !store.serverRestartReasons(server.id).isEmpty {
                Label("配置已变更，待重启生效", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button("详情") { onSelectService(server.id) }
                Button("复制本机地址") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.endpoint(server), forType: .string)
                }.help("仅本机 loopback 地址，不是公网入口")
                Spacer()
                if status == .running {
                    Button("停止") { confirm(ServiceStopImpact.message(name: server.name), { store.stopServer(server) }) }.disabled(busy)
                } else {
                    Button("启动") {
                        let workspace = store.currentWorkspaceID
                        confirm("将在 Mac 上执行 \(server.executable) 及所填参数。程序具有你账户的文件与服务权限；仅已允许的工具可通过网关调用。确认来源可信并启动？", {
                            guard workspace == store.currentWorkspaceID, store.preferences.servers.contains(server) else {
                                store.errorMessage = "配置已改变，请重新检查服务后启动。"; return
                            }
                            store.startServer(server)
                        })
                    }.disabled(busy || !store.gatewayReady || status == .unknown)
                }
            }.controlSize(.small)
        }.frame(maxWidth: .infinity, alignment: .leading).dashboardCard()
    }
}

private extension View {
    func dashboardCard() -> some View {
        self.padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}
