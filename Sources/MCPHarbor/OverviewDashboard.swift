import SwiftUI
import AppKit

/// A read-only projection of the shared runtime. Actions use the existing store commands.
struct OverviewDashboard: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logServer: ServerConfig?
    @State private var serviceQuery = ""
    @State private var copiedServerID: String?
    private var filteredServices: [ServerConfig] {
        let query = serviceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.preferences.servers.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.id.localizedStandardContains(query) }
    }
    let onAddService: () -> Void
    let onSelectService: (String) -> Void
    let onOpenTunnels: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void
    let confirm: (String, @escaping () -> Void) -> Void
    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)]
    private var runningServices: Int { store.menuServers.filter { store.menuServerStatus($0.id) == .running }.count }
    private var activeTunnels: Int { store.menuTunnelIDs.filter { [.running, .ready].contains(store.menuTunnelStatus($0)) }.count }
    private var hasUnknownStates: Bool {
        store.menuGatewayStatus == .unknown ||
        store.menuServers.contains { store.menuServerStatus($0.id) == .unknown } ||
        store.menuTunnelIDs.contains { store.menuTunnelStatus($0) == .unknown }
    }
    private var failures: Int {
        store.menuServers.filter { store.menuServerStatus($0.id) == .failed }.count +
        store.menuTunnelIDs.filter { store.menuTunnelStatus($0) == .failed }.count +
        (store.menuGatewayStatus == .failed ? 1 : 0)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 16) {
                    metric("本地网关", value: store.menuGatewayStatus.title, icon: "network", color: store.menuGatewayStatus.color)
                    metric("MCP 服务运行", value: store.menuGatewayStatus == .unknown ? "未确认" : "\(runningServices) / \(store.menuServers.count)", icon: "shippingbox.fill", color: .blue)
                    metric("隧道运行", value: store.menuGatewayStatus == .unknown ? "未确认" : "\(activeTunnels) / \(store.menuTunnelIDs.count)", icon: "point.3.connected.trianglepath.dotted", color: .teal)
                    metric("异常", value: failures == 0 && hasUnknownStates ? "待确认" : String(failures), icon: "exclamationmark.triangle.fill", color: failures > 0 ? .red : .secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { dashboardActions }
                    VStack(alignment: .leading, spacing: 12) { dashboardActions }
                }
                /* Primary actions use the same order at narrow widths. */
                if !store.gatewayReady {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: store.menuGatewayStatus.symbol).foregroundStyle(store.menuGatewayStatus.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.menuGatewayStatus == .unknown ? "网关状态未确认" : "先准备本地网关").font(.headline)
                            Text(store.menuGatewayStatus == .unknown ? "请重新连接网关以获取最新状态。" : "可以先添加服务和隧道。使用左侧启动网关，再启动需要的项目。")
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
                        onboardingStep("3", title: "创建隧道", detail: "选择 OpenAI 或 Cloudflare，明确绑定服务并验证连接。")
                        Button("添加第一个 MCP", action: onAddService).buttonStyle(HarborPrimaryButtonStyle())
                    }.harborSurface()
                }
                HStack {
                    Text("MCP 服务").font(.title3.bold())
                    Text("\(store.preferences.servers.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    TextField("筛选服务名称", text: $serviceQuery)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        .accessibilityLabel("筛选 MCP 服务，不影响运行状态")
                }
                if !store.preferences.servers.isEmpty && filteredServices.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的服务", systemImage: "magnifyingglass")
                    } description: { Text("更换关键词或清除筛选；不会改变服务配置。")
                    } actions: { Button("清除筛选") { serviceQuery = "" } }
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(filteredServices) { server in serviceCard(server) }
                }
                TunnelRecordsView().environmentObject(store)
            }.padding(24)
        }
        .onChange(of: store.currentWorkspaceID) { _, _ in serviceQuery = ""; copiedServerID = nil }
        .sheet(item: $logServer) { server in
            ServiceLogView(server: server).environmentObject(store)
        }
    }
    @ViewBuilder private var dashboardActions: some View {
        Button("添加 MCP", systemImage: "plus", action: onAddService).buttonStyle(HarborPrimaryButtonStyle())
        Button("管理隧道", systemImage: "network", action: onOpenTunnels)
        Button("查看诊断", systemImage: "waveform.path.ecg", action: onOpenLogs)
    }
    private func metric(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title3.weight(.medium)).foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: value)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).harborSurface()
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
                Image(systemName: "shippingbox.fill").foregroundStyle(.blue).font(.title3)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name).font(.headline).lineLimit(2).help(server.name)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    Text("已配置 \(server.allowedTools.count) 项授权工具 · \(bindings) 条隧道绑定").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            StatusBadge(status: status)
            if !store.serverRestartReasons(server.id).isEmpty {
                Label("配置已变更，待重启生效", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.orange)
            }
            if status == .failed || status == .unknown {
                Label(status == .failed ? "运行异常，请查看服务日志" : "状态未确认，请先检查网关连接", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if !store.gatewayReady && !busy {
                Text("先启动左侧本地网关，再启动服务").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 8) {
                Button("详情") { onSelectService(server.id) }
                Button("日志", systemImage: "text.alignleft") { logServer = server }
                Menu {
                    Button("复制本机地址") {
                        NSPasteboard.general.clearContents()
                        if NSPasteboard.general.setString(store.endpoint(server), forType: .string) { copiedServerID = server.id }
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("\(server.name) 的更多操作")
                .help("复制本机 loopback 地址，不是公网入口")
                Spacer()
                if status == .running {
                    Button { confirm(ServiceStopImpact.message(name: server.name), { store.stopServer(server) }) } label: {
                        RuntimeActionLabel(title: busy ? "处理中" : "停止", busy: busy)
                    }.disabled(busy).accessibilityLabel("停止 \(server.name)")
                } else {
                    Button {
                        let workspace = store.currentWorkspaceID
                        confirm("将在 Mac 上执行 \(server.executable) 及所填参数。程序具有你账户的文件与服务权限；仅已允许的工具可通过网关调用。确认来源可信并启动？", {
                            guard workspace == store.currentWorkspaceID, store.preferences.servers.contains(server) else {
                                store.errorMessage = "配置已改变，请重新检查服务后启动。"; return
                            }
                            store.startServer(server)
                        })
                    } label: {
                        RuntimeActionLabel(title: busy ? "处理中" : "启动", busy: busy)
                    }.buttonStyle(HarborPrimaryButtonStyle())
                    .disabled(busy || !store.gatewayReady || status == .unknown)
                    .accessibilityLabel("启动 \(server.name)")
                }
            }.controlSize(.small)
            if copiedServerID == server.id {
                Label("本机地址已复制", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).harborSurface()
    }
}
