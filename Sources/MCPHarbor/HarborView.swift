import SwiftUI

struct HarborView: View {
    @EnvironmentObject private var store: HarborStore
    @ObservedObject private var navigationRouter = HarborNavigationRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    private enum Section: String, CaseIterable, Identifiable, Hashable {
        case dashboard, servers, tunnels, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: "总览"
            case .servers: "MCP 服务"
            case .tunnels: "隧道"
            case .settings: "设置"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .servers: "shippingbox"
            case .tunnels: "network"
            case .settings: "gearshape"
            }
        }
        var shortcut: KeyEquivalent {
            switch self {
            case .dashboard: "1"
            case .servers: "2"
            case .tunnels: "3"
            case .settings: "4"
            }
        }
        var subtitle: String {
            switch self {
            case .dashboard: "服务、隧道与待处理状态，一眼看清。"
            case .servers: "添加你要使用的工具服务。"
            case .tunnels: "独立管理 OpenAI 与 Cloudflare 入口。"
            case .settings: "运行环境、凭据与备份。"
            }
        }
    }
    @State private var section: Section = .dashboard
    @State private var showAddMCP = false
    @State private var importAfterAddDismiss = false
    @State private var showLogs = false
    @State private var serviceLogServer: ServerConfig?
    @State private var showDiagnostics = false
    @State private var showRuntimeInstances = false
    @State private var showWorkspaceSheet = false
    @State private var workspaceName = ""
    @State private var servicePane = "使用与授权"
    @State private var serviceFilter = ""
    @State private var settingsWide = false
    private var selectedIndex: Int? { store.preferences.servers.firstIndex { $0.id == store.selectedID } }
    var body: some View {
        NavigationSplitView {
            workspaceSidebar
        } detail: {
            VStack(spacing: 0) {
                header
                if store.legacyCandidateJSON != nil {
                    HStack {
                        Text("发现同一工作空间的旧版网关（PID \(store.legacyGatewayPID)），可停止后由新版接管。").font(.caption)
                        Spacer()
                        Button(store.takeoverBusy ? "正在停止并接管…" : "停止旧网关并接管") {
                            approve("停止旧网关（PID \(store.legacyGatewayPID)）及其 MCP、隧道连接，然后启动新版网关？所有使用旧实例的 AI 和应用都会暂时断开。配置会先保存；工具与隧道需要之后明确启动。") {
                                store.takeOverLegacyGateway()
                            }
                        }.disabled(store.takeoverBusy)
                    }.padding(12).background(Color.orange.opacity(0.08))
                }
                if !store.configurationApplicationNotices.isEmpty {
                    DisclosureGroup("已保存配置：\(store.configurationApplicationNotices.count) 项运行状态待处理") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(store.configurationApplicationNotices) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label(item.title, systemImage: "arrow.clockwise.circle").font(.caption.bold()).foregroundStyle(.orange)
                                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if item.id.hasPrefix("removed:") {
                                            Button("停止已移除服务") {
                                                let id = String(item.id.dropFirst("removed:".count))
                                                approve(ServiceStopImpact.message(name: "已移除的服务")) {
                                                    store.command("stopServer", params: ["serverId": id])
                                                }
                                            }
                                        } else if item.id.hasPrefix("tunnel:") {
                                            Button("停止此隧道") {
                                                let key = String(item.id.dropFirst("tunnel:".count))
                                                approve("停止这条运行中的隧道？使用此隧道的客户端会断开。") { store.stopTunnel(key) }
                                            }
                                        }
                                    }
                                }
                                Text("进程与隧道配置需明确停止、再启动相关项目后生效。工具选择可在服务页单独保存并应用；请以各项运行状态为准。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 160)
                    }.padding(12).background(Color.orange.opacity(0.06))
                }
                Group {
                switch section {
                case .dashboard:
                    OverviewDashboard(onAddService: { showAddMCP = true }, onSelectService: { id in store.selectedID = id; section = .servers }, onOpenTunnels: { section = .tunnels }, onOpenSettings: { section = .settings }, onOpenLogs: { section = .settings; showDiagnostics = true; showLogs = true }, confirm: { message, action in approve(message, action: action) })
                case .servers: serverWorkspace
                case .tunnels: tunnelSettings
                case .settings: connectionSettings
                }
                }
                .id(section)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: section)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: section)
            .background { HarborCanvas().ignoresSafeArea(.container, edges: .top) }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .containerBackground(Color(nsColor: HarborPalette.canvas), for: .window)
        .background { HarborWindowChrome().frame(width: 0, height: 0) }
        .frame(minWidth: 1020, minHeight: 700)

        .sheet(item: $serviceLogServer) { server in ServiceLogView(server: server).environmentObject(store) }
        .sheet(isPresented: $showWorkspaceSheet) {
            VStack(alignment: .leading, spacing: 18) {
                HarborSheetHeader(title: "新建工作空间", subtitle: "为一组工具创建独立的连接环境。", symbol: "square.stack.3d.up.badge.plus")
                HarborNotice(title: "独立配置，不自动启动", detail: "各空间独立保存 MCP、隧道与 Keychain 命名空间。创建不会启动连接。", symbol: "lock.shield")
                Text("工作空间名称").font(.subheadline.weight(.medium))
                TextField("名称", text: $workspaceName).textFieldStyle(.roundedBorder)
                HStack { Button("取消") { showWorkspaceSheet = false }; Spacer(); Button("创建") { if store.createWorkspace(name: workspaceName) { workspaceName = ""; showWorkspaceSheet = false } }.buttonStyle(.glassProminent).disabled(workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(18).frame(width: 520).background { HarborCanvas() }
        }
        .sheet(isPresented: $store.showImportPreview, onDismiss: { store.cancelImportPreview() }) { ImportPreview().environmentObject(store) }
        .sheet(isPresented: $showConfirmation, onDismiss: { pendingAction = nil }) {
            HarborConfirmationSheet(message: confirmation, onCancel: { pendingAction = nil; showConfirmation = false }, onContinue: {
                let action = pendingAction; pendingAction = nil; showConfirmation = false; action?()
            })
        }
        .alert("请留意", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .sheet(isPresented: $showAddMCP, onDismiss: {
            if importAfterAddDismiss {
                importAfterAddDismiss = false
                store.discoverSelectedConfigurations()
            }
        }) {
            VStack(alignment: .leading, spacing: 20) {
                HarborSheetHeader(title: "连接你的工具", subtitle: "选择添加方式，下一步再核对程序与开放范围。", symbol: "shippingbox.fill")
                Button {
                    importAfterAddDismiss = true
                    section = .servers
                    showAddMCP = false
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("从已有应用导入…", systemImage: "doc.badge.plus").font(.title3.weight(.semibold))
                        Text("选择 Claude、Cursor 等应用的 MCP 配置文件，再勾选要添加的项目。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.buttonStyle(.bordered).disabled(store.anyProcessRunning)
                Button {
                    showAddMCP = false
                    section = .servers
                    store.addServer()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("手动添加", systemImage: "plus.circle.fill").font(.title3.weight(.semibold))
                        Text("填写程序路径和启动参数，适合尚未配置的 MCP。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.buttonStyle(.bordered)
                if store.anyProcessRunning {
                    Text("文件导入前请先停止当前连接。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack { Spacer(); Button("取消", role: .cancel) { showAddMCP = false } }
            }.padding(18).frame(width: 560).background { HarborCanvas() }
        }
        .onReceive(navigationRouter.$destination) { destination in
            guard let destination, let requested = Section(rawValue: destination) else { return }
            section = requested
            navigationRouter.destination = nil
        }
        .onChange(of: store.selectedID) { _, _ in servicePane = "使用与授权" }
        .onChange(of: store.currentWorkspaceID) { _, _ in serviceFilter = ""; servicePane = "使用与授权" }
        .task(id: store.currentWorkspaceID) { store.autofillRememberedTunnelKey() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(Section.allCases) { item in
                        Button { section = item } label: { Label(item.title, systemImage: item.icon) }
                            .keyboardShortcut(item.shortcut, modifiers: .command)
                    }
                } label: { Label("前往", systemImage: "rectangle.split.2x1") }
                .help("切换页面：⌘1 总览 · ⌘2 服务 · ⌘3 隧道 · ⌘4 设置")
            }
            if store.hasUnsavedChanges {
                ToolbarItem {
                    Button { if store.save() { store.notice = "配置已保存。" } } label: { Text("保存修改") }
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityLabel("保存修改")
                        .help("保存当前工作空间配置，不会自动启动连接")
                }
            }
        }
        .disclosureGroupStyle(FullRowDisclosureStyle())
    }

    private var workspaceSidebar: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        BrandMark().frame(width: 46, height: 46)
                            .padding(6).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One MCP").font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("你的工具连接中心").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前工作空间").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.accentColor)
                            Picker("工作空间", selection: Binding(get: { store.currentWorkspaceID }, set: { store.switchWorkspace($0) })) {
                                ForEach(store.workspaces) { Text($0.name).tag($0.id) }
                            }.labelsHidden().disabled(store.anyProcessRunning)
                            Button { showWorkspaceSheet = true } label: { Image(systemName: "plus") }
                                .buttonStyle(.plain).help("新建工作空间").accessibilityLabel("新建工作空间").disabled(store.anyProcessRunning)
                        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("工作空间").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 6)
                        ForEach([Section.dashboard, .servers, .tunnels]) { item in
                            HarborNavigationRow(title: item.title, subtitle: item.subtitle, symbol: item.icon, selected: section == item) { section = item }
                        }
                        Text("管理").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 6)
                        HarborNavigationRow(title: Section.settings.title, subtitle: "运行环境 · 安全 · 数据", symbol: Section.settings.icon, selected: section == .settings) { section = .settings }
                    }.padding(.horizontal, 12)
                }.frame(minHeight: 220).layoutPriority(1)
                SidebarRuntimeControls(confirm: { message, action in approve(message, action: action) })
            }
            .background {
                HarborCanvas().ignoresSafeArea(.container, edges: .top)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: section.icon)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(section == .dashboard ? "工作台" : section.title).font(.system(size: 25, weight: .bold))
                Text(section.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if store.hasUnsavedChanges { Label("有未保存修改", systemImage: "circle.fill").font(.caption).foregroundStyle(.orange) }
            if !store.pendingCommands.isEmpty { RuntimeActionLabel(title: "等待确认：\(store.pendingCommands.count)", busy: true).font(.caption).foregroundStyle(.secondary) }

        }.padding(.horizontal, 18).padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)

    }
    private func approve(_ message: String, action: @escaping () -> Void) {
        let workspace = store.currentWorkspaceID
        let gateway = store.gateway
        let bridge = store.runtimeBridge
        confirmation = message
        pendingAction = {
            guard workspace == store.currentWorkspaceID, gateway === store.gateway, bridge === store.runtimeBridge else {
                store.errorMessage = "工作空间或网关连接已改变，请重新核对后操作。"; return
            }
            action()
        }
        showConfirmation = true
    }
    private func serverEditor(index: Int) -> some View {
        let server = store.preferences.servers[index]
        let running = ["running", "starting", "stopping"].contains(store.states[server.id] ?? "") || store.hasPendingCommand(for: server.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HarborSheetHeader(title: server.name, subtitle: server.isCLI ? "将命令行能力连接给 AI，按工具控制可用范围。" : "把本机工具连接给 AI，只开放你明确选择的能力。", symbol: server.isCLI ? "terminal.fill" : "shippingbox.fill")
                    HStack {
                        StatusBadge(status: store.menuServerStatus(server.id))
                        Text("已选 \(Set(server.allowedTools).count) 项工具 · " + toolLiveCount(server.id)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                    Button(server.isCLI ? "启动服务" : "启动并发现工具", systemImage: "play.fill") {
                        approve("将在 Mac 上执行 \(server.executable) 及所填参数。程序具有你账户的文件与服务权限，不是沙箱；仅白名单工具可通过网关调用。若选择包管理器，还可能执行下载的程序。确认启动？") { store.startServer(server) }
                    }.buttonStyle(.glassProminent).disabled(running || !store.gatewayReady || store.startAllBusy)
                    Button("停止", systemImage: "stop.fill") { approve(ServiceStopImpact.message(name: server.name)) { store.stopServer(server) } }.buttonStyle(.glass).disabled(!running)
                    Button("服务日志", systemImage: "doc.text.magnifyingglass") { serviceLogServer = server }.buttonStyle(.glass)
                    }
                }
                if !store.serverRestartReasons(server.id).isEmpty {
                    Label("已保存修改，待重启此 MCP 生效：" + store.serverRestartReasons(server.id).joined(separator: "、"), systemImage: "arrow.clockwise.circle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if !store.gatewayReady {
                    HStack {
                        Label("需要先启动本机网关", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text("点击左侧“启动网关”继续").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("服务页面", selection: $servicePane) {
                    Text("使用与授权").tag("使用与授权")
                    Text("程序配置").tag("程序配置")
                }.pickerStyle(.segmented)
                if servicePane == "使用与授权" {
                    HarborNotice(title: "下一步", detail: serviceNextStep(server), symbol: "arrow.right.circle.fill")
                    if server.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("填写程序配置") { servicePane = "程序配置" }.buttonStyle(.borderedProminent)
                    }
                    ToolSelectionView(server: $store.preferences.servers[index], confirm: { message, action in
                        approve(message, action: action)
                    }).id(server.id)
                } else {
                Toggle("参与全部启动", isOn: Binding(get: { store.preferences.servers[index].participatesInStartAll },
                    set: { store.preferences.servers[index].startWithAll = $0 }))
                    .help("取消后仅从全部启动中排除，不会停止正在运行的服务，也不影响手动启动")
                    .disabled(store.startAllBusy)
                ProcessConfigurationView(server: $store.preferences.servers[index], locked: running || store.startAllBusy)
                if server.isCLI {
                    CLIServiceEditor(configuration: Binding(get: { store.preferences.servers[index].cli ?? CLIServiceConfiguration() }, set: { store.preferences.servers[index].cli = $0 }), allowedTools: $store.preferences.servers[index].allowedTools)
                        .disabled(running || store.startAllBusy)
                    if let issue = CLIConfigurationValidation.issue(server) { Text(issue).font(.caption).foregroundStyle(.orange) }
                }
                if !server.environmentKeys.isEmpty {
                    GroupBox("仅本次会话使用的环境变量值") {
                        ForEach(server.environmentKeys, id: \.self) { key in
                            SecureField(key, text: Binding(get: { store.runtimeValues[store.credentialKey(serverID: server.id, variable: key)] ?? "" }, set: { store.runtimeValues[store.credentialKey(serverID: server.id, variable: key)] = $0 })).textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Button("移除服务器配置", role: .destructive) {
                    approve("停止连接并移除已保存的配置？不会删除 MCP 程序或其文件。") { store.removeServer(server) }
                }.disabled(running)
                }
            }.padding(18)
        }
    }
    private func serviceNextStep(_ server: ServerConfig) -> String {
        if server.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "先在“程序配置”填写工具程序，再回来启动和选择能力。" }
        if !store.gatewayReady { return "先启动左侧本地网关，再启动这个服务；不会自动开放任何工具。" }
        switch store.menuServerStatus(server.id) {
        case .running: return server.allowedTools.isEmpty ? "服务已运行。选择下方需要开放的工具，再保存并应用授权。" : "核对下方工具范围；需要从远端使用时，前往“隧道”绑定这个服务。"
        case .failed: return "启动出现异常。先查看服务日志，再到“程序配置”核对路径和参数。"
        case .unknown: return "尚未确认运行状态，请先检查网关连接。不要重复提交启动。"
        case .starting, .checking, .stopping: return "操作进行中，请等待网关返回实际状态。"
        default: return "确认程序来源后启动服务，随后选择允许 AI 调用的工具。"
        }
    }
    private func toolLiveCount(_ id: String) -> String {
        guard let runtime = store.sharedRuntimeServers.first(where: { $0.id == id && $0.running }) else {
            return store.states[id] == "running" ? "生效待核对" : "未运行"
        }
        return runtime.permissionsKnown ? "生效 \(Set(runtime.allowedTools).count)" : "生效待核对"
    }
    private func serviceStatus(_ id: String) -> String {
        switch store.states[id] ?? "stopped" {
        case "running": "运行中"
        case "starting": "正在启动"
        case "stopping": "正在停止"
        case "stopped": "未运行"
        case "failed", "error": "启动失败"
        default: "需要检查"
        }
    }
    private var serverWorkspace: some View {
        Group {
            if store.preferences.servers.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "shippingbox").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("添加你的第一个 MCP").font(.title3.bold())
                    Text("从现有应用导入，或手动添加。添加后再选择要开放的工具。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("添加 MCP") { showAddMCP = true }.buttonStyle(.glassProminent)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .help("从配置文件导入，或手动添加")
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                    Button("添加 MCP", systemImage: "plus") { showAddMCP = true }
                        .keyboardShortcut("n", modifiers: [.command, .shift]).padding(.horizontal, 12).padding(.top, 12)
                    TextField("查找服务", text: $serviceFilter).textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                    if !serviceFilter.isEmpty && !store.preferences.servers.contains(where: { $0.name.localizedStandardContains(serviceFilter) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("没有匹配的服务", systemImage: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                            Button("清除筛选") { serviceFilter = "" }.font(.caption)
                        }.padding(12)
                    }
                    List(selection: $store.selectedID) {
                        ForEach(store.preferences.servers.filter { serviceFilter.isEmpty || $0.name.localizedStandardContains(serviceFilter) }) { server in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(server.name).font(.headline)
                                Label(store.menuServerStatus(server.id).title, systemImage: store.menuServerStatus(server.id).symbol).font(.caption).foregroundStyle(store.menuServerStatus(server.id).color)
                                Text("已选 \(Set(server.allowedTools).count) · " + toolLiveCount(server.id))
                                    .font(.caption2).foregroundStyle(.secondary)
                                if !store.serverRestartReasons(server.id).isEmpty {
                                    Text("待重启生效").font(.caption).foregroundStyle(.orange)
                                }
                            }.padding(.vertical, 6).tag(server.id)
                        }
                    }.listStyle(.inset).scrollContentBackground(.hidden)
                    }.frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
                        .background(Color.blue.opacity(0.025))
                    Divider()
                    if let index = selectedIndex {
                        VStack(spacing: 0) {
                            if !serviceFilter.isEmpty && !store.preferences.servers[index].name.localizedStandardContains(serviceFilter) {
                                HStack {
                                    Label("当前打开的服务不在筛选结果中", systemImage: "line.3.horizontal.decrease.circle").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("清除筛选") { serviceFilter = "" }.font(.caption)
                                }.padding(12).background(.thinMaterial)
                            }
                            serverEditor(index: index)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ContentUnavailableView("选择一个服务", systemImage: "cursorarrow.click.2", description: Text("先看工具能力与运行状态，再按需打开程序配置。"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
    private var tunnelSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TunnelRecordsView().environmentObject(store)
                if !store.gatewayReady {
                    Label("启动网关后即可启动隧道；现在也可以添加或编辑记录。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SettingsSurface {
                DisclosureGroup {
                DisclosureGroup("首次连接与客户端设置") {
                    VStack(alignment: .leading, spacing: 16) {
                        TunnelOnboardingGuide().environmentObject(store)
                        TunnelAccountGuide()
                        Link("安装官方 tunnel-client", destination: TunnelHelp.installation)
                        HStack {
                            TextField("tunnel-client 绝对路径", text: $store.preferences.tunnelClientPath)
                            Button("选择") { store.choosePath("tunnel") }
                        }.textFieldStyle(.roundedBorder)
                        Text("客户端路径为工作空间共享设置，修改后使用顶部保存配置。")
                            .font(.caption).foregroundStyle(.secondary)
                        TunnelVerificationGuide()
                    }.padding(.top, 12)
                }
                RemoteConnectionSettingsView().environmentObject(store)
                DisclosureGroup("连接日志与请求观测") {
                    MCPRequestTracePanel().environmentObject(store)
                }
                } label: {
                    SettingsSectionLabel(title: "连接帮助与高级维护", subtitle: "首次安装、共享认证与连接诊断，按需展开。", symbol: "wrench.and.screwdriver")
                }
                }
            }.padding(18)
        }
    }
    private var connectionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HarborNotice(title: "管理当前工作空间", detail: "日常启停在左侧；这里管理运行环境、安全与数据。修改配置后使用顶部保存，不会自动重启。", symbol: "gearshape.2.fill")
                settingsLayout {
                    settingsConnectionColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                    settingsSafetyColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }.onGeometryChange(for: Bool.self) { geometry in
                geometry.size.width >= 720
            } action: { settingsWide = $0 }
            .padding(18)
        }
    }
    private var settingsLayout: AnyLayout {
        settingsWide ? AnyLayout(HStackLayout(alignment: .top, spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
    }
    private var settingsConnectionColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("连接与运行", systemImage: "network").font(.headline).foregroundStyle(.secondary)
            runtimeSettingsCard
            advancedSettingsCard
            diagnosticSettingsCard
        }
    }
    private var settingsSafetyColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("安全与数据", systemImage: "lock.shield").font(.headline).foregroundStyle(.secondary)
            aiManagementSettingsCard
            credentialSettingsCard
            backupSettingsCard
        }
    }

    private var runtimeSettingsCard: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionLabel(title: store.isAttachedGateway ? "共享网关与运行环境" : "运行环境",
                    subtitle: "检查组件与运行状态；全局启停在左侧。", symbol: "desktopcomputer")
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    Label(store.gatewayReady ? "本地网关运行中，ChatGPT 未验证" : (store.gatewayStartBusy ? "正在检查网关" : (store.gatewayState == "Disconnected" ? "共享连接已断开，网关状态未确认" : (store.isGatewayRunning ? "正在启动" : (store.runtimeFilesReady ? "已准备好，尚未启动" : "需要检查运行环境")))),
                          systemImage: store.gatewayReady ? "checkmark.circle.fill" : "desktopcomputer")
                        .font(.headline).foregroundStyle(.primary)
                    Text(store.isAttachedGateway ? "与 AI 共用当前网关。这里的操作会作用于同一实例；退出本应用只断开界面连接。" : (store.gatewayReady ? "返回 MCP 服务，添加或启动你需要的工具。" : store.runtimeSetupSummary))
                        .font(.callout).foregroundStyle(.secondary)
                    if store.runtimeComparisonUnavailable {
                        Text("当前网关版本尚未提供完整逐项配置对比。已保存配置会正常同步；无法确认的项目不会被标为已生效。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if !store.sharedRuntimeServers.isEmpty || !store.runningTunnelKeys.isEmpty {
                        DisclosureGroup("已连接实例与单独停止", isExpanded: $showRuntimeInstances) {
                            if !store.sharedRuntimeServers.isEmpty {
                                ForEach(store.sharedRuntimeServers) { server in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(server.name).font(.subheadline)
                                            Text("当前实例：\(server.running ? "运行中" : "已停止") · " + (server.permissionsKnown ? "已授权 \(server.allowedTools.count) 个工具" : "工具授权待核对")).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("停止此服务") {
                                            approve(ServiceStopImpact.message(name: server.name)) {
                                                store.command("stopServer", params: ["serverId": server.id])
                                            }
                                        }.disabled(!server.running)
                                    }
                                }
                            }
                            ForEach(Array(store.runningTunnelKeys).sorted(), id: \.self) { key in
                                HStack {
                                    Text((store.preferences.effectiveTunnelRecords.first(where: { $0.id == key })?.name ?? key) + " · 运行中").font(.caption)
                                    Spacer()
                                    Button("停止此隧道") {
                                        approve("停止这条运行中的隧道？使用此隧道的客户端会断开。") { store.stopTunnel(key) }
                                    }
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button(store.discoveryBusy ? "正在检测…" : "自动检查并修复") { store.repairEnvironment() }
                            .disabled(store.anyProcessRunning || store.discoveryBusy)
                            .help("检查已安装组件并修正失效路径；不会安装软件或启动服务")

                    }
                    Text("启动后只在本机运行；连接 ChatGPT 需另外设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var aiManagementSettingsCard: some View {
        SettingsSurface { AIManagementAccessView() }
    }

    private var advancedSettingsCard: some View {
        SettingsSurface {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 18) {
                    Text("通常无需修改。自定义安装位置或排查问题时再展开使用。")
                        .font(.caption).foregroundStyle(.secondary)
                    GroupBox("组件路径") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Node 可执行文件").font(.caption).foregroundStyle(.secondary)
                            HStack { TextField("绝对路径", text: $store.preferences.nodePath); Button("选择…") { store.choosePath("node") } }
                            Text("网关脚本").font(.caption).foregroundStyle(.secondary)
                            HStack { TextField("绝对路径", text: $store.preferences.gatewayScript); Button("选择…") { store.choosePath("gateway") } }
                            TextField("本机监听端口", value: $store.preferences.port, format: .number.grouping(.never))
                        }.textFieldStyle(.roundedBorder).padding(12).disabled(store.isGatewayRunning)
                    }
                    DisclosureGroup("逐项检测结果") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.setupChecks) { result in
                                HStack(alignment: .top) {
                                    Image(systemName: result.passed ? "checkmark.circle" : "exclamationmark.circle")
                                        .foregroundStyle(result.passed ? Color.green : Color.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.label).font(.caption.bold())
                                        Text(result.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                            }
                            Button("重新检查，不修改配置") { store.checkSetup() }
                        }.padding(.vertical, 10)
                    }
                    EnvironmentDiscoveryView()
                }.padding(.vertical, 12)
            } label: {
                SettingsSectionLabel(title: "组件与高级设置", subtitle: "Node、网关路径、端口与环境检测。", symbol: "slider.horizontal.3")
            }
        }
    }

    private var credentialSettingsCard: some View {
        SettingsSurface {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("默认仅存在内存。可明确保存到此 Mac 的 Keychain；不会写入配置或导出文件。隧道密钥自动填入需在连接页单独启用。").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Button("保存到系统钥匙串") { approve("将当前工作空间已输入的环境变量值与隧道运行密钥保存到这台 Mac 的 Keychain？仅保存非空值，未来可手动载入。") { store.saveCredentialsToKeychain() } }
                        Button("从系统钥匙串载入") { store.loadCredentialsFromKeychain() }
                        Button("删除已存凭据", role: .destructive) { approve("删除此工作空间全部已存 Keychain 凭据（含已移除服务器）？这不会撤销服务端密钥，也不会停止现有进程。") { store.deleteSavedCredentials() } }
                    }
                }.padding(12)
            } label: {
                SettingsSectionLabel(title: "密钥与登录信息", subtitle: "凭据仅在明确保存后存入系统钥匙串。", symbol: "key")
            }
        }
    }

    private var backupSettingsCard: some View {
        SettingsSurface {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("备份保存当前工作空间配置，不包含凭据。恢复会替换当前配置。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("备份当前配置…") { store.exportConfiguration() }
                            .help("导出配置文件，不包含凭据")
                        Button("从备份恢复…", role: .destructive) {
                            approve("恢复备份将替换当前工作空间的服务器配置，丢弃 env 值并清空工具白名单；不会运行程序。请先备份需要保留的配置。") { store.importConfiguration() }
                        }.disabled(store.anyProcessRunning)
                    }
                }.padding(.vertical, 10)
            } label: {
                SettingsSectionLabel(title: "备份与恢复", subtitle: "导出或恢复当前工作空间配置，不包含凭据。", symbol: "externaldrive")
            }
        }
    }

    private var diagnosticSettingsCard: some View {
        SettingsSurface {
            DisclosureGroup(isExpanded: $showDiagnostics) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button("导出工具说明…") { store.exportToolGuide() }
                        Button("导出脱敏日志…") { store.exportLogs() }
                    }
                    DisclosureGroup("查看运行日志（\(store.logs.count) 条）", isExpanded: $showLogs) { logPanel }
                }.padding(.vertical, 10)
            } label: {
                SettingsSectionLabel(title: "诊断与工具说明", subtitle: "查看运行日志、导出脱敏诊断与工具说明。", symbol: "stethoscope")
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Label("实时日志", systemImage: "waveform.path").font(.caption.bold()); Spacer(); Text("仅内存 · 最近 1,000 行").font(.caption).foregroundStyle(.secondary); Button("清空") { store.logs.removeAll() }.controlSize(.small) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.logs) { line in
                        Text("\(line.time.formatted(date: .omitted, time: .standard))  [\(line.source)] \(line.text)").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(height: 120)
        }.padding(14).background(.background.secondary)
    }
}

