import SwiftUI
import AppKit

/// A read-only projection of the shared runtime. Actions use the existing store commands.
struct OverviewDashboard: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logServer: ServerConfig?
    @State private var serviceQuery = ""
    @State private var copiedServerID: String?
    @State private var contentWidth: CGFloat = 0
    private var wideDashboard: Bool { contentWidth >= 880 }
    private var dashboardLayout: AnyLayout {
        wideDashboard ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
    }
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
    private var columns: [GridItem] {
        wideDashboard
            ? Array(repeating: GridItem(.flexible(minimum: 250), spacing: 12, alignment: .top), count: 2)
            : [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)]
    }
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
            VStack(alignment: .leading, spacing: 12) {
                workspaceHero
                dashboardLayout {
                    serviceCollection
                        .frame(width: wideDashboard ? (contentWidth - 12) * 0.66 : nil, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 12) {
                        tunnelSummary
                        recentActivity
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            .padding(16)
        }
        .onChange(of: store.currentWorkspaceID) { _, _ in serviceQuery = ""; copiedServerID = nil }
        .sheet(item: $logServer) { server in
            ServiceLogView(server: server).environmentObject(store)
        }
    }
    private var serviceCollection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MCP 服务").font(.headline)
                Text("\(store.preferences.servers.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("添加", systemImage: "plus", action: onAddService).buttonStyle(.borderedProminent).controlSize(.small)
                TextField("筛选服务", text: $serviceQuery)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                    .accessibilityLabel("筛选 MCP 服务，不影响运行状态")
            }
            if store.preferences.servers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("三步连接你的工具").font(.headline)
                    onboardingStep("1", title: "添加 MCP 服务", detail: "导入或填写工具程序，默认不开放工具。")
                    onboardingStep("2", title: "启动并选择工具", detail: "先确认来源，再选择允许调用的工具。")
                    onboardingStep("3", title: "按需创建隧道", detail: "仅本机使用时无需创建；远端需绑定并验证。")
                    Button("添加第一个 MCP", action: onAddService).buttonStyle(.borderedProminent)
                }.harborSurface()
            } else if filteredServices.isEmpty {
                ContentUnavailableView {
                    Label("没有匹配的服务", systemImage: "magnifyingglass")
                } description: { Text("更换关键词或清除筛选；不会改变服务配置。")
                } actions: { Button("清除筛选") { serviceQuery = "" } }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(filteredServices) { server in serviceCard(server) }
            }
        }
    }
    private var tunnelSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("隧道连接", systemImage: "network").font(.headline)
                Spacer(minLength: 4)
                Button("管理", action: onOpenTunnels).buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.blue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(activeTunnels) / \(store.menuTunnelIDs.count) 已确认运行").font(.subheadline.weight(.semibold))
                    Text(hasUnknownStates ? "部分状态待确认" : "绑定服务后对外连接").font(.caption).foregroundStyle(.secondary)
                }
            }.accessibilityElement(children: .combine)
            if store.menuTunnelIDs.isEmpty {
                Text("尚未配置隧道。本机工具可先独立使用；需要远端接入时再创建。").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.menuTunnelIDs.prefix(3)), id: \.self) { id in
                    MenuStatusRow(name: store.menuTunnelName(id), status: store.menuTunnelStatus(id))
                }
                if store.menuTunnelIDs.count > 3 {
                    Button("查看全部 \(store.menuTunnelIDs.count) 条隧道", action: onOpenTunnels).font(.caption)
                }
            }
            Divider()
            Button("运行环境与连接配置", systemImage: "gearshape", action: onOpenSettings).font(.caption)
            Text("管理隧道 → 选择入口 → 绑定 MCP → 验证连接")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.harborSurface()
    }
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最近活动", systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
                Text("本次会话").font(.caption2).foregroundStyle(.secondary)
            }
            if store.activities.isEmpty {
                Text("暂无操作记录；实际发生的配置与运行事件会显示在这里。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(store.activities.prefix(3))) { record in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: record.outcome == .failed ? "exclamationmark.circle" : "clock")
                        .foregroundStyle(record.outcome == .failed ? Color.orange : Color.blue)
                        .frame(width: 24, height: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.summary).font(.caption.weight(.medium)).lineLimit(2).help(record.summary)
                        Text(record.source.rawValue + " · " + record.outcome.rawValue).font(.caption2).foregroundStyle(.secondary)
                        Text(record.time, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
            }
            Text("完整操作动态可在左侧展开查看").font(.caption2).foregroundStyle(.secondary)
            Button("查看诊断", systemImage: "waveform.path.ecg", action: onOpenLogs).font(.caption)
        }.harborSurface()
    }
    private var heroTitle: String {
        if failures > 0 { return "有连接需要处理" }
        if hasUnknownStates { return "连接状态待确认" }
        if store.gatewayReady { return "本地网关已就绪" }
        if store.menuGatewayStatus == .starting || store.menuGatewayStatus == .checking { return "正在准备连接" }
        if store.menuGatewayStatus == .stopping { return "正在停止连接" }
        return "准备连接你的工具"
    }
    private var heroDetail: String {
        if failures > 0 { return "先查看异常项目和诊断，再决定是否重新启动。" }
        if hasUnknownStates { return "尚不能确认全部连接状态；下方仅展示已观察到的运行信息。" }
        if store.gatewayReady { return "管理本机工具与隧道，按需启动、明确授权。远端调用需单独验证。" }
        return "先添加工具，再从左侧启动网关与需要的连接。"
    }
    private var workspaceHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: store.menuGatewayStatus.symbol)
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(store.menuGatewayStatus.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTitle).font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(heroDetail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                metric("服务", value: "\(runningServices) / \(store.menuServers.count)")
                metric("隧道", value: "\(activeTunnels) / \(store.menuTunnelIDs.count)")
                heroRuntimeActions
            }
        }.harborSurface()
    }
    private var heroRuntimeActions: some View {
        HStack(spacing: 8) {
            Button {
                let plan = store.preferences, workspace = store.currentWorkspaceID, revision = store.savedRevision
                confirm(store.startAllConfirmation) {
                    store.startAll(expectedPlan: plan, expectedWorkspace: workspace, expectedRevision: revision)
                }
            } label: {
                heroActionLabel(store.startAllBusy ? "启动中" : "全部启动", symbol: store.startAllBusy ? "hourglass" : "play.fill")
            }.buttonStyle(TrayActionStyle(tint: .blue))
                .disabled(store.startAllBusy || store.gatewayStartBusy || store.menuGatewayStatus == .stopping || store.takeoverBusy || store.hasUnsavedChanges)
                .help(store.hasUnsavedChanges ? "请先保存修改" : "确认后依次启动当前工作空间的连接")
            Button {
                confirm("停止共享网关及全部连接？所有连接到此实例的 AI 和应用都会受到影响。将取消后续启动并请求停止当前进程；配置会保留。") { store.shutdown() }
            } label: {
                heroActionLabel(store.menuGatewayStatus == .stopping ? "停止中" : "全部停止", symbol: store.menuGatewayStatus == .stopping ? "hourglass" : "stop.fill")
            }.buttonStyle(TrayActionStyle(tint: .red))
                .disabled(store.menuGatewayStatus == .stopping || (!store.anyProcessRunning && !store.startAllBusy && !store.gatewayStartBusy) || store.takeoverBusy)
        }
    }
    private func heroActionLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).accessibilityHidden(true)
            Text(title).font(.system(size: 11, weight: .semibold))
        }.frame(width: 68, height: 56)
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.blue).fixedSize()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: value)
            Text(title + "已确认运行").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
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
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "shippingbox.fill").foregroundStyle(.blue).font(.system(size: 22, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [Color.blue.opacity(0.16), Color.cyan.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name).font(.system(size: 15, weight: .semibold)).lineLimit(2).help(server.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("MCP 工具服务 · 按授权开放").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 10) {
                StatusBadge(status: status)
                Spacer(minLength: 0)
                Label("\(bindings) 条绑定", systemImage: "link")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("已配置 \(server.allowedTools.count) 项授权工具")
                .font(.caption).foregroundStyle(.secondary)
            if !store.serverRestartReasons(server.id).isEmpty {
                Label("配置已变更，待重启生效", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.orange)
            }
            if status == .failed || status == .unknown {
                Label(status == .failed ? "运行异常，请查看服务日志" : "状态未确认，请先检查网关连接", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if !store.gatewayReady && !busy {
                Text("先启动左侧本地网关，再启动服务").font(.caption).foregroundStyle(.secondary)
            }
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
