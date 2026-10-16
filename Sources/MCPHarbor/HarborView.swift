import SwiftUI

struct HarborView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    private enum Section: String, CaseIterable, Identifiable, Hashable {
        case overview, servers, tools, tunnels, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "概览"
            case .servers: "MCP 服务器"
            case .tools: "工具与授权"
            case .tunnels: "隧道连接"
            case .settings: "设置"
            }
        }
        var icon: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .servers: "shippingbox"
            case .tools: "wrench.and.screwdriver"
            case .tunnels: "network"
            case .settings: "gearshape"
            }
        }
        var subtitle: String {
            switch self {
            case .overview: "先启动网关，再连接服务器，最后开放需要的工具。"
            case .servers: "配置与管理本机 MCP 进程。"
            case .tools: "查看工具能力，明确哪些工具可以对外调用。"
            case .tunnels: "将已授权工具连接到 OpenAI 工作区。"
            case .settings: "本机运行环境、工作空间与凭据。"
            }
        }
    }
    @State private var section: Section = .overview
    @State private var showLogs = false
    @State private var toolSearch = ""
    @State private var showWorkspaceSheet = false
    @State private var workspaceName = ""
    private var selectedIndex: Int? { store.preferences.servers.firstIndex { $0.id == store.selectedID } }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.title).foregroundStyle(.cyan)
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
                if let notice = store.notice {
                    HStack { Image(systemName: "info.circle"); Text(notice).font(.caption); Spacer(); Button("关闭") { store.notice = nil } }.padding(12).background(Color.accentColor.opacity(0.08))
                }
                Divider()
                switch section {
                case .overview: overview
                case .servers: serverWorkspace
                case .tools: toolWorkspace
                case .tunnels: tunnelSettings
                case .settings: connectionSettings
                }
                Divider()
                DisclosureGroup(isExpanded: $showLogs) {
                    logPanel
                } label: {
                    HStack {
                        Label("诊断日志", systemImage: "waveform.path").font(.caption.bold())
                        Spacer()
                        Text("\(store.logs.count) 条").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
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
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("从所选配置发现 MCP…") { store.discoverSelectedConfigurations() }.disabled(store.anyProcessRunning)
                    Divider()
                    Button("恢复 / 替换整个配置…") { approve("导入将替换当前工作空间的服务器配置，丢弃 env 值并清空工具白名单；不会运行程序。请先保存需要保留的配置。") { store.importConfiguration() } }.disabled(store.anyProcessRunning)
                    Button("导出配置（不含凭据）") { store.exportConfiguration() }
                    Button("导出脱敏日志") { store.exportLogs() }
                } label: { Label("导入与导出", systemImage: "square.and.arrow.up.on.square") }
            }
            ToolbarItem { Button { store.exportToolGuide() } label: { Label("导出工具说明", systemImage: "doc.text") } }
            ToolbarItem { Button { if store.save() { store.notice = "配置已保存。" } } label: { Label("保存", systemImage: "square.and.arrow.down") } }
            ToolbarItem { Button { store.shutdown() } label: { Label("全部停止", systemImage: "stop.circle") } }
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
            HStack(spacing: 8) { Circle().fill(store.gatewayReady ? Color.green : Color.gray).frame(width: 7, height: 7); Text(store.gatewayState).font(.caption) }
                .padding(.horizontal, 14).padding(.vertical, 10).glassEffect(.regular, in: Capsule())
        }.padding(24)
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
                    VStack(alignment: .leading) { Text(server.name).font(.largeTitle.bold()); Text("STDIO · \(store.states[server.id] ?? "stopped")").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
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
                Button { section = .tools } label: {
                    Label("查看工具与授权（已选 \(server.allowedTools.count) 项）", systemImage: "arrow.right.circle")
                }
                Button("移除服务器配置", role: .destructive) {
                    approve("停止连接并移除已保存的配置？不会删除 MCP 程序或其文件。") { store.removeServer(server) }
                }.disabled(running)
            }.padding(24)
        }
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    summaryCard("服务器", value: "\(store.preferences.servers.count)", icon: "shippingbox", target: .servers)
                    summaryCard("已选工具", value: "\(store.preferences.servers.reduce(0) { $0 + $1.allowedTools.count })", icon: "checkmark.shield", target: .tools)
                    summaryCard("就绪隧道", value: "\(store.tunnelReady.values.filter { $0 }.count)", icon: "network", target: .tunnels)
                }
                GroupBox("连接步骤") {
                    VStack(alignment: .leading, spacing: 20) {
                        nextStep("1", title: "检查本机运行环境", detail: "选择 Node 和网关脚本，确认后启动本机网关。", action: "打开设置", target: .settings)
                        Divider()
                        nextStep("2", title: "添加并发现 MCP 工具", detail: "配置可执行文件及参数，启动服务器后读取工具目录。", action: "管理服务器", target: .servers)
                        Divider()
                        nextStep("3", title: "选择允许使用的工具", detail: "停止服务器后编辑白名单；重新启动后生效。", action: "查看授权", target: .tools)
                        Divider()
                        nextStep("4", title: "连接隧道", detail: "初始化 profile、检查连接，再接入你的 OpenAI 工作区。", action: "配置隧道", target: .tunnels)
                    }.padding(16)
                }
                Label("网关就绪、隧道就绪与 ChatGPT 实际调用成功是不同状态。", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func summaryCard(_ title: String, value: String, icon: String, target: Section) -> some View {
        Button { section = target } label: {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.system(size: 32, weight: .semibold, design: .rounded))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(nsColor: .separatorColor).opacity(0.5)))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
    private func nextStep(_ number: String, title: String, detail: String, action: String, target: Section) -> some View {
        HStack(spacing: 16) {
            Text(number).font(.headline).frame(width: 32, height: 32).background(Color.accentColor.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action) { section = target }
        }
    }
    private var serverPicker: some View {
        Picker("服务器", selection: $store.selectedID) {
            Text("请选择服务器").tag(nil as String?)
            ForEach(store.preferences.servers) { server in
                Text("\(server.name) · \(store.states[server.id] ?? "stopped")").tag(Optional(server.id))
            }
        }.frame(maxWidth: 380)
            .onChange(of: store.selectedID) { _, _ in toolSearch = "" }
    }
    private var serverWorkspace: some View {
        VStack(spacing: 0) {
            HStack {
                serverPicker
                Spacer()
                Button("添加 MCP", systemImage: "plus") { store.addServer() }.buttonStyle(.glassProminent)
                Button("从配置发现…") { store.discoverSelectedConfigurations() }.disabled(store.anyProcessRunning)
            }.padding(20)
            Divider()
            if let index = selectedIndex { serverEditor(index: index) }
            else {
                ContentUnavailableView {
                    Label("添加第一个 MCP", systemImage: "shippingbox")
                } description: {
                    Text("手动配置本机 stdio 程序，或从现有配置中发现。添加不会自动运行程序。")
                } actions: {
                    Button("添加 MCP") { store.addServer() }
                }
            }
        }
    }
    private var toolWorkspace: some View {
        VStack(spacing: 0) {
            HStack { serverPicker; Spacer(); Button("管理此服务器") { section = .servers } }.padding(20)
            Divider()
            if let index = selectedIndex {
                ScrollView { toolEditor(index: index).padding(24) }
            } else {
                ContentUnavailableView("尚无工具目录", systemImage: "wrench.and.screwdriver", description: Text("先添加并启动 MCP 服务器，再来查看工具和编辑授权。"))
            }
        }
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
                    serverPicker
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
                            Button("前往服务器并启动发现") { section = .servers }
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
                EnvironmentDiscoveryView()
                GroupBox("首启检查与恢复") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(store.setupChecks) { result in
                            HStack(alignment: .top) { Image(systemName: result.passed ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(result.passed ? Color.green : Color.orange); VStack(alignment: .leading) { Text(result.label).font(.caption.bold()); Text(result.detail).font(.caption).foregroundStyle(.secondary) } }
                        }
                        HStack { Button("重新检查路径") { store.checkSetup() }; Text("这里只读检查文件；握手与联网操作需单独确认。").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                GroupBox("本机网关") {
                    Form {
                        HStack { TextField("Node 可执行文件", text: $store.preferences.nodePath); Button("选择") { store.choosePath("node") } }
                        HStack { TextField("已构建的网关脚本", text: $store.preferences.gatewayScript); Button("选择") { store.choosePath("gateway") } }
                        DisclosureGroup("高级：本机监听端口") {
                            TextField("本机端口", value: $store.preferences.port, format: .number.grouping(.never))
                        }
                    }.formStyle(.grouped).disabled(store.isGatewayRunning)
                    HStack {
                        Text("仅监听 127.0.0.1。启动网关不会自动启动 MCP。").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("启动网关") { approve("确认运行所选 Node 可执行文件与网关脚本，仅监听 127.0.0.1:\(store.preferences.port)?") { store.startGateway() } }.disabled(store.isGatewayRunning).buttonStyle(.glassProminent)
                        Button("停止") { store.stopGateway() }.disabled(!store.isGatewayRunning)
                    }.padding(10)
                }
                GroupBox("凭据保存：由你选择") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("默认仅存在内存。可明确保存到此 Mac 的 Keychain；不会写入配置或导出文件，不会自动读取。").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("保存当前凭据到 Keychain") { approve("将当前工作空间已输入的环境变量值与隧道运行密钥保存到这台 Mac 的 Keychain？仅保存非空值，未来可手动载入。") { store.saveCredentialsToKeychain() } }
                            Button("从 Keychain 载入") { store.loadCredentialsFromKeychain() }
                            Button("删除已存凭据", role: .destructive) { approve("删除此工作空间全部已存 Keychain 凭据（含已移除服务器）？这不会撤销服务端密钥，也不会停止现有进程。") { store.deleteSavedCredentials() } }
                        }
                    }.padding(12)
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
