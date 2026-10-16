import SwiftUI

struct HarborView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    private enum Section: String, CaseIterable, Identifiable, Hashable {
        case servers, tunnels, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .servers: "MCP 服务"
            case .tunnels: "ChatGPT 连接"
            case .settings: "设置"
            }
        }
        var icon: String {
            switch self {
            case .servers: "shippingbox"
            case .tunnels: "network"
            case .settings: "gearshape"
            }
        }
        var subtitle: String {
            switch self {
            case .servers: "添加你要使用的工具服务。"
            case .tunnels: "将允许使用的工具连接到 ChatGPT。"
            case .settings: "运行环境、凭据与备份。"
            }
        }
    }
    @State private var section: Section = .servers
    @State private var showAddMCP = false
    @State private var importAfterAddDismiss = false
    @State private var showLogs = false
    @State private var toolSearch = ""
    @State private var showWorkspaceSheet = false
    @State private var workspaceName = ""
    private var selectedIndex: Int? { store.preferences.servers.firstIndex { $0.id == store.selectedID } }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    BrandMark().frame(width: 38, height: 38)
                    VStack(alignment: .leading) { Text("One MCP").font(.headline); Text("本机工具，清楚授权。").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal).padding(.top, 18)
                HStack {
                    Picker("工作空间", selection: Binding(get: { store.currentWorkspaceID }, set: { store.switchWorkspace($0) })) {
                        ForEach(store.workspaces) { Text($0.name).tag($0.id) }
                    }.labelsHidden().disabled(store.anyProcessRunning)
                    Button { showWorkspaceSheet = true } label: { Image(systemName: "folder.badge.plus") }.help("新建工作空间").disabled(store.anyProcessRunning)
                }.padding(.horizontal)
                List(selection: Binding<Section?>(get: { section }, set: { if let value = $0 { section = value } })) {
                    ForEach(Section.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(store.gatewayReady ? "网关已就绪" : "网关未就绪", systemImage: store.gatewayReady ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(store.gatewayReady ? Color.green : Color.secondary)
                    Text("仅监听本机 · 工具默认不开放").font(.caption2).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationSplitViewColumnWidth(min: 245, ideal: 265)
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
                if let externalNotice = store.externalConfigurationNotice {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                        Text(externalNotice).font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !store.anyProcessRunning {
                            Button("载入磁盘版本") {
                                approve("载入磁盘中最新的配置？这会丢弃当前工作空间尚未保存的本地修改，以磁盘版本替换界面内容。不会启动或重启服务。") {
                                    store.reloadExternalConfiguration(discardLocalChanges: true)
                                }
                            }.help("确认后放弃本地未保存修改，载入已保存的外部配置")
                        }
                    }.padding(12).background(Color.accentColor.opacity(0.06))
                }
                if let notice = store.notice, section == .settings || !store.preferences.servers.isEmpty {
                    HStack { Image(systemName: "info.circle"); Text(notice).font(.caption); Spacer(); Button("关闭") { store.notice = nil } }.padding(12).background(Color.accentColor.opacity(0.08))
                }
                Divider()
                switch section {
                case .servers: serverWorkspace
                case .tunnels: tunnelSettings
                case .settings: connectionSettings
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1020, minHeight: 700)

        .sheet(isPresented: $showWorkspaceSheet) {
            VStack(alignment: .leading, spacing: 18) {
                Text("新建工作空间").font(.title2.bold())
                Text("各工作空间独立保存 MCP、隧道与 Keychain 命名空间。不会自动启动连接。").font(.caption)
                TextField("名称", text: $workspaceName).textFieldStyle(.roundedBorder)
                HStack { Button("取消") { showWorkspaceSheet = false }; Spacer(); Button("创建") { if store.createWorkspace(name: workspaceName) { workspaceName = ""; showWorkspaceSheet = false } }.buttonStyle(.glassProminent).disabled(workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(24).frame(width: 460)
        }
        .sheet(isPresented: $store.showImportPreview, onDismiss: { store.cancelImportPreview() }) { ImportPreview().environmentObject(store) }
        .alert("确认本机执行", isPresented: $showConfirmation) {
            Button("取消", role: .cancel) { pendingAction = nil }
            Button("继续") { let action = pendingAction; pendingAction = nil; action?() }
        } message: { Text(confirmation) }
        .alert("请留意", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .sheet(isPresented: $showAddMCP, onDismiss: {
            if importAfterAddDismiss {
                importAfterAddDismiss = false
                store.discoverSelectedConfigurations()
            }
        }) {
            VStack(alignment: .leading, spacing: 20) {
                Text("添加 MCP").font(.title2.bold())
                Text("选择一种添加方式。导入后可先核对，不会自动运行程序。")
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    importAfterAddDismiss = true
                    section = .servers
                    showAddMCP = false
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("从已有应用导入…", systemImage: "doc.badge.plus").font(.headline)
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
                        Label("手动添加", systemImage: "plus").font(.headline)
                        Text("填写程序路径和启动参数，适合尚未配置的 MCP。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.buttonStyle(.bordered)
                if store.anyProcessRunning {
                    Text("文件导入前请先停止当前连接。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack { Spacer(); Button("取消", role: .cancel) { showAddMCP = false } }
            }.padding(24).frame(width: 480)
        }
        .onChange(of: section) { _, _ in store.notice = nil }
        .toolbar {
            if section != .servers || !store.preferences.servers.isEmpty {
            ToolbarItem {
                Button { showAddMCP = true } label: { Text("添加 MCP") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .accessibilityLabel("添加 MCP")
                    .help("从已有应用的配置文件导入，或手动添加 MCP")
            }
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
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title).font(.title2.bold())
                Text(section.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if store.hasUnsavedChanges { Label("有未保存修改", systemImage: "circle.fill").font(.caption).foregroundStyle(.orange) }
            if !store.pendingCommands.isEmpty { Text("等待网关确认：\(store.pendingCommands.count)").font(.caption).foregroundStyle(.secondary) }
            if section != .servers || !store.preferences.servers.isEmpty {
                Label(store.gatewayReady ? "已就绪" : (store.isGatewayRunning ? "正在启动" : "未运行"), systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(store.gatewayReady ? Color.green : Color.secondary)
            }
        }.padding(.horizontal, 24).padding(.vertical, 18)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func approve(_ message: String, action: @escaping () -> Void) {
        confirmation = message; pendingAction = action; showConfirmation = true
    }
    private func lines(_ binding: Binding<[String]>) -> Binding<String> {
        Binding(get: { binding.wrappedValue.joined(separator: "\n") }, set: { binding.wrappedValue = $0.components(separatedBy: "\n").filter { !$0.isEmpty } })
    }
    private func serverEditor(index: Int) -> some View {
        let server = store.preferences.servers[index]
        let running = ["running", "starting"].contains(store.states[server.id] ?? "") || store.hasPendingCommand(for: server.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading) { Text(server.name).font(.largeTitle.bold()); Text(serviceStatus(server.id)).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    Spacer()
                    Button("发现工具 / 启动", systemImage: "play.fill") {
                        approve("将在 Mac 上执行 \(server.executable) 及所填参数。MCP 程序具有你账户的文件与服务权限；仅白名单工具可通过网关调用。若选择包管理器，还可能执行下载的程序。确认启动？") { store.startServer(server) }
                    }.buttonStyle(.glassProminent).disabled(running || !store.gatewayReady)
                    Button("停止", systemImage: "stop.fill") { store.stopServer(server) }.buttonStyle(.glass).disabled(!running)
                }
                if !store.gatewayReady {
                    HStack {
                        Label("需要先启动本机网关", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("打开设置") { section = .settings }
                    }
                }
                GroupBox("进程配置") {
                    Form {
                        TextField("名称", text: $store.preferences.servers[index].name)
                        TextField("可执行文件绝对路径", text: $store.preferences.servers[index].executable)
                        VStack(alignment: .leading) { Text("参数：每行一个，不需要 shell 转义").font(.caption); TextEditor(text: lines($store.preferences.servers[index].arguments)).font(.system(.body, design: .monospaced)).frame(height: 65) }
                        DisclosureGroup("高级：工作目录与环境变量") {
                            TextField("工作目录", text: $store.preferences.servers[index].workingDirectory)
                            VStack(alignment: .leading) {
                                Text("环境变量名称：具体值只存在内存").font(.caption)
                                TextEditor(text: lines($store.preferences.servers[index].environmentKeys))
                                    .font(.system(.body, design: .monospaced)).frame(height: 60)
                            }
                        }
                    }.formStyle(.grouped).disabled(running)
                }
                if !server.environmentKeys.isEmpty {
                    GroupBox("仅本次会话使用的环境变量值") {
                        ForEach(server.environmentKeys, id: \.self) { key in
                            SecureField(key, text: Binding(get: { store.runtimeValues[store.credentialKey(serverID: server.id, variable: key)] ?? "" }, set: { store.runtimeValues[store.credentialKey(serverID: server.id, variable: key)] = $0 })).textFieldStyle(.roundedBorder)
                        }
                    }
                }
                DisclosureGroup("允许使用的工具（已选 \(server.allowedTools.count) 项）") {
                    toolEditor(index: index).padding(.top, 12)
                }
                Button("移除服务器配置", role: .destructive) {
                    approve("停止连接并移除已保存的配置？不会删除 MCP 程序或其文件。") { store.removeServer(server) }
                }.disabled(running)
            }.padding(24)
        }
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
    private var serverPicker: some View {
        Picker("服务器", selection: $store.selectedID) {
            Text("请选择服务器").tag(nil as String?)
            ForEach(store.preferences.servers) { server in
                Text("\(server.name) · \(serviceStatus(server.id))").tag(Optional(server.id))
            }
        }.frame(maxWidth: 380)
            .onChange(of: store.selectedID) { _, _ in toolSearch = "" }
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
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(spacing: 0) {
                    List(selection: $store.selectedID) {
                        ForEach(store.preferences.servers) { server in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(server.name).font(.headline)
                                Text(serviceStatus(server.id)).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6).tag(server.id)
                        }
                    }.listStyle(.inset).frame(width: 210)
                    Divider()
                    if let index = selectedIndex {
                        serverEditor(index: index).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        Text("选择左侧服务，查看配置和工具。")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: store.selectedID) { _, _ in toolSearch = "" }
    }
    private var tunnelSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox("出口方式") {
                    Picker("路由模式", selection: $store.preferences.mode) {
                        Text("聚合 · 一个隧道").tag("aggregate")
                        Text("独立 · 每个 MCP 一个隧道").tag("individual")
                    }.pickerStyle(.segmented).padding(10)
                    Text("聚合路由为 /mcp，独立路由为 /servers/{id}/mcp。两组本机路由同时存在；这里选择管理哪组隧道。切换前先停止隧道。").font(.caption).foregroundStyle(.secondary).padding(10)
                }.disabled(store.tunnelStates.keys.contains { store.tunnelRunning($0) })
                if !store.gatewayReady {
                    HStack {
                        Label("初始化、检查及启动隧道都需要本机网关就绪。", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("打开设置") { section = .settings }
                    }
                }
                GroupBox("官方隧道客户端") {
                    Form {
                        HStack { TextField("tunnel-client 绝对路径", text: $store.preferences.tunnelClientPath); Button("选择") { store.choosePath("tunnel") } }
                        SecureField("运行时 API key：仅内存保存", text: $store.tunnelKey)
                    }.formStyle(.grouped)
                    Text("需已有 tunnel、Platform Read + Use 权限及正确的 ChatGPT 工作区关联。密钥和隧道由你自行创建。").font(.caption).foregroundStyle(.secondary).padding(10)
                    HStack { Link("安装官方 tunnel-client", destination: URL(string: "https://github.com/openai/tunnel-client#readme")!); Link("Platform 隧道设置", destination: URL(string: "https://platform.openai.com/settings/organization/tunnels")!); Link("官方配置文档", destination: URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!); Link("ChatGPT Plugins", destination: URL(string: "https://chatgpt.com/plugins")!) }.padding(10)
                }
                if store.preferences.mode == "aggregate" {
                    tunnelPanel(server: nil, index: nil)
                } else {
                    if !store.preferences.servers.isEmpty { serverPicker }
                    if let index = selectedIndex {
                        tunnelPanel(server: store.preferences.servers[index], index: index)
                    } else {
                        ContentUnavailableView("先添加服务器", systemImage: "network", description: Text("独立模式为每个 MCP 配置自己的隧道。"))
                    }
                }
            }.padding(24)
        }
    }
    private func toolEditor(index: Int) -> some View {
        let server = store.preferences.servers[index]
        let running = ["running", "starting"].contains(store.states[server.id] ?? "") || store.hasPendingCommand(for: server.id)
        return VStack(alignment: .leading, spacing: 18) {
            TextField("搜索此服务器的工具名称或说明", text: $toolSearch).textFieldStyle(.roundedBorder)
                if let change = store.toolChanges[server.id] {
                    Label(change, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("刷新工具目录") { store.command("listTools", params: ["serverId": server.id]) }.disabled(store.states[server.id] != "running" || store.hasPendingCommand(for: server.id))
                    Text("刷新只查询已启动的 MCP，不会自动扩大白名单。").font(.caption).foregroundStyle(.secondary)
                }
                GroupBox("工具白名单：默认不开放") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("先发现工具并停止服务器，再勾选允许对外使用的工具，然后重新启动。配置下次启动时生效。").font(.caption).foregroundStyle(.secondary)
                        if (store.tools[server.id] ?? []).isEmpty { VStack(alignment: .leading, spacing: 8) {
                            Text("尚未发现工具。").foregroundStyle(.secondary)
                            Text("使用本页上方的“发现工具 / 启动”读取工具目录。").font(.caption)
                        } }
                        if !toolSearch.isEmpty && !(store.tools[server.id] ?? []).contains(where: { $0.name.localizedCaseInsensitiveContains(toolSearch) || $0.description.localizedCaseInsensitiveContains(toolSearch) }) {
                            Text("没有匹配的工具。试试其他关键词。").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach((store.tools[server.id] ?? []).filter { toolSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(toolSearch) || $0.description.localizedCaseInsensitiveContains(toolSearch) }) { tool in
                            Toggle(isOn: Binding(get: { store.preferences.servers[index].allowedTools.contains(tool.name) }, set: { enabled in
                                if enabled { store.preferences.servers[index].allowedTools.append(tool.name) }
                                else { store.preferences.servers[index].allowedTools.removeAll { $0 == tool.name } }
                            })) {
                                VStack(alignment: .leading) { Text(tool.name).font(.system(.body, design: .monospaced)); Text(tool.publicName).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary); Text(tool.description).font(.caption).foregroundStyle(.secondary) }
                            }.disabled(running)
                            DisclosureGroup("参数 schema 与 annotations（来自服务器）") {
                                Text(tool.metadataJSON).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.font(.caption)
                        }
                        Text("已选： \(server.allowedTools.joined(separator: ", "))").font(.caption).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
        }
    }
    private var connectionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox(store.isAttachedGateway ? "已连接现有网关" : "运行状态") {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(store.gatewayReady ? "可以使用" : (store.isGatewayRunning ? "正在启动" : (store.runtimeFilesReady ? "已准备好，尚未启动" : "需要检查运行环境")),
                              systemImage: store.gatewayReady ? "checkmark.circle.fill" : "desktopcomputer")
                            .font(.headline).foregroundStyle(store.gatewayReady ? Color.green : Color.primary)
                        Text(store.isAttachedGateway ? "与 AI 共用当前网关。这里的操作会作用于同一实例；退出本应用只断开界面连接。" : (store.gatewayReady ? "返回 MCP 服务，添加或启动你需要的工具。" : store.runtimeSetupSummary))
                            .font(.callout).foregroundStyle(.secondary)
                        if store.isAttachedGateway {
                            ForEach(store.sharedRuntimeServers) { server in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.name).font(.subheadline)
                                        Text("当前实例：\(server.running ? "运行中" : "已停止") · 已授权 \(server.allowedTools.count) 个工具").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("停止此服务") {
                                        approve("停止共享实例中的 \(server.name)？使用此服务的 AI 和应用都会受到影响。") {
                                            store.command("stopServer", params: ["serverId": server.id])
                                        }
                                    }.disabled(!server.running)
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            Button(store.discoveryBusy ? "正在检测…" : "自动检查并修复") { store.repairEnvironment() }
                                .disabled(store.anyProcessRunning || store.discoveryBusy)
                                .help("检查已安装组件并修正失效路径；不会安装软件或启动服务")
                            if store.isGatewayRunning {
                                Button("停止服务") { approve("停止此共享网关及其连接？所有连接到该实例的 AI 和应用都会受到影响。") { store.stopGateway() } }
                            } else {
                                Button("启动服务") {
                                    approve("确认运行所选 Node 可执行文件与网关脚本，仅监听 127.0.0.1:\(store.preferences.port)?") { store.startGateway() }
                                }.buttonStyle(.glassProminent).disabled(!store.runtimeFilesReady || store.takeoverBusy)
                            }
                        }
                        Text("启动后只在本机运行；连接 ChatGPT 需另外设置。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                AIManagementAccessView()
                DisclosureGroup("高级设置与检测详情") {
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
                }
                DisclosureGroup("密钥与登录信息") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("默认仅存在内存。可明确保存到此 Mac 的 Keychain；不会写入配置或导出文件，不会自动读取。").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("保存到系统钥匙串") { approve("将当前工作空间已输入的环境变量值与隧道运行密钥保存到这台 Mac 的 Keychain？仅保存非空值，未来可手动载入。") { store.saveCredentialsToKeychain() } }
                            Button("从系统钥匙串载入") { store.loadCredentialsFromKeychain() }
                            Button("删除已存凭据", role: .destructive) { approve("删除此工作空间全部已存 Keychain 凭据（含已移除服务器）？这不会撤销服务端密钥，也不会停止现有进程。") { store.deleteSavedCredentials() } }
                        }
                    }.padding(12)
                }
                DisclosureGroup("备份与恢复") {
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
                }
                DisclosureGroup("诊断与工具说明") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("导出工具说明…") { store.exportToolGuide() }
                            Button("导出脱敏日志…") { store.exportLogs() }
                        }
                        DisclosureGroup("查看运行日志（\(store.logs.count) 条）", isExpanded: $showLogs) { logPanel }
                        Button("停止全部连接", role: .destructive) { approve("停止共享网关及全部连接？所有连接到此实例的客户端都会受到影响。") { store.shutdown() } }
                            .disabled(!store.anyProcessRunning)
                            .help("停止当前网关、MCP 和隧道进程；保留配置")
                    }.padding(.vertical, 10)
                }
            }.padding(24)
        }
    }
    private func tunnelPanel(server: ServerConfig?, index: Int?) -> some View {
        let key = server?.id ?? "aggregate"
        return GroupBox(server == nil ? "聚合隧道" : "独立隧道") {
            VStack(alignment: .leading, spacing: 12) {
                if let index {
                    TextField("Tunnel ID", text: $store.preferences.servers[index].tunnelID).disabled(store.tunnelRunning(key))
                    TextField("唯一的本机 profile 名称", text: $store.preferences.servers[index].profile).disabled(store.tunnelRunning(key))
                } else {
                    TextField("Tunnel ID", text: $store.preferences.aggregateTunnelID).disabled(store.tunnelRunning(key))
                    TextField("唯一的本机 profile 名称", text: $store.preferences.aggregateProfile).disabled(store.tunnelRunning(key))
                }
                Text("下一步：\(store.tunnelNextStep(key: key))").font(.caption).foregroundStyle(.secondary)
                Text(store.endpoint(server)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack { Circle().fill(store.tunnelReady[key] == true ? Color.green : Color.gray).frame(width: 8, height: 8); Text(store.tunnelStates[key] ?? "未运行").font(.caption).foregroundStyle(.secondary) }
                if store.doctorIsCurrent(key: key) { Text("最近一次 doctor 退出码为 0；不等同 ChatGPT 调用已验证。").font(.caption).foregroundStyle(.secondary) }
                if let base = store.tunnelHealthURLs[key] { Link("打开官方本机状态界面", destination: base.appendingPathComponent("ui")) }
                HStack {
                    Button("初始化 profile") { approve("执行官方 tunnel-client init，为 \(store.endpoint(server)) 创建本机 profile？请使用新的唯一名称；若已存在请检查 CLI 输出。此操作不会启动服务。") { store.tunnelAction("init", server: server) } }.disabled(store.tunnelRunning(key) || !store.gatewayReady)
                    Button("Doctor") { approve("执行 tunnel-client doctor？它可能使用本次会话密钥连接 OpenAI，并检查本机 MCP 端点。") { store.tunnelAction("doctor", server: server) } }.disabled(store.tunnelRunning(key) || !store.gatewayReady)
                    Button("启动隧道") { approve("将本机端点接入所填 OpenAI 隧道？运行期间，获授权的 OpenAI 工作区可发现并调用白名单工具，数据与结果会发送到 OpenAI。请先核对工作区和工具白名单。") { store.tunnelAction("run", server: server) } }.buttonStyle(.glassProminent).disabled(store.tunnelRunning(key) || !store.gatewayReady)
                    Button("停止") { store.stopTunnel(key) }.disabled(!store.tunnelRunning(key))
                }
                Text("每个隧道使用系统分配的独立 loopback 管理端口；本界面持续读取 /readyz，只有实际 HTTP 200 才亮绿灯。ChatGPT 调用仍需单独验收。").font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).padding(12)
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
