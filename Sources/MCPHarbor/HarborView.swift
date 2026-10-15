import SwiftUI

struct HarborView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    @State private var tab = "Servers"
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
                Picker("Workspace", selection: $tab) { Text("服务器").tag("Servers"); Text("连接设置").tag("Connection") }.pickerStyle(.segmented).padding(.horizontal)
                List(selection: $store.selectedID) {
                    Section("本机 MCP") {
                        ForEach(store.preferences.servers) { server in
                            HStack {
                                Image(systemName: "shippingbox").foregroundStyle(.secondary)
                                VStack(alignment: .leading) { Text(server.name); Text(store.states[server.id] ?? "stopped").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Circle().fill(store.states[server.id] == "running" ? Color.green : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            }.tag(server.id)
                        }
                    }
                }.listStyle(.sidebar)
                Button { store.addServer(); tab = "Servers" } label: { Label("添加 MCP", systemImage: "plus") }.buttonStyle(.glass).padding()
            }
            .navigationSplitViewColumnWidth(min: 245, ideal: 265)
        } detail: {
            VStack(spacing: 0) {
                header
                if let notice = store.notice {
                    HStack { Image(systemName: "info.circle"); Text(notice).font(.caption); Spacer(); Button("关闭") { store.notice = nil } }.padding(12).background(Color.accentColor.opacity(0.08))
                }
                Divider()
                if tab == "Connection" { connectionSettings }
                else if let index = selectedIndex { serverEditor(index: index) }
                else {
                    ContentUnavailableView("尚未添加 MCP", systemImage: "shippingbox", description: Text("添加本机 stdio MCP。启动进程和对外连接都需要你确认。"))
                }
                Divider()
                logPanel
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1020, minHeight: 700)
        .onAppear { if store.preferences.gatewayScript.isEmpty { tab = "Connection" } }
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
                Text(tab == "Connection" ? "本机服务，私有通道" : "管理本机 MCP").font(.title2.bold())
                Text("OpenAI Secure MCP Tunnel · 不监听公网").font(.subheadline).foregroundStyle(.secondary)
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
                    VStack(alignment: .leading) { Text(server.name).font(.largeTitle.bold()); Text("STDIO 本机进程").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    Spacer()
                    Button("发现工具 / 启动", systemImage: "play.fill") {
                        approve("将在 Mac 上执行 \(server.executable) 及所填参数。MCP 程序具有你账户的文件与服务权限；仅白名单工具可通过网关调用。若选择包管理器，还可能执行下载的程序。确认启动？") { store.startServer(server) }
                    }.buttonStyle(.glassProminent).disabled(running || !store.gatewayReady)
                    Button("停止", systemImage: "stop.fill") { store.stopServer(server) }.buttonStyle(.glass).disabled(!running)
                }
                GroupBox("进程配置") {
                    Form {
                        TextField("名称", text: $store.preferences.servers[index].name)
                        TextField("可执行文件绝对路径", text: $store.preferences.servers[index].executable)
                        TextField("工作目录", text: $store.preferences.servers[index].workingDirectory)
                        VStack(alignment: .leading) { Text("参数：每行一个，不需要 shell 转义").font(.caption); TextEditor(text: lines($store.preferences.servers[index].arguments)).font(.system(.body, design: .monospaced)).frame(height: 65) }
                        VStack(alignment: .leading) { Text("环境变量名称：具体值只存在内存").font(.caption); TextEditor(text: lines($store.preferences.servers[index].environmentKeys)).font(.system(.body, design: .monospaced)).frame(height: 44) }
                    }.formStyle(.grouped).disabled(running)
                }
                if !server.environmentKeys.isEmpty {
                    GroupBox("仅本次会话使用的环境变量值") {
                        ForEach(server.environmentKeys, id: \.self) { key in
                            SecureField(key, text: Binding(get: { store.runtimeValues[store.credentialKey(serverID: server.id, variable: key)] ?? "" }, set: { store.runtimeValues[store.credentialKey(serverID: server.id, variable: key)] = $0 })).textFieldStyle(.roundedBorder)
                        }
                    }
                }
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
                        if (store.tools[server.id] ?? []).isEmpty { Text("尚未发现工具。").foregroundStyle(.secondary) }
                        ForEach(store.tools[server.id] ?? []) { tool in
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
                if store.preferences.mode == "individual" { tunnelPanel(server: server, index: index) }
                Button("移除服务器配置", role: .destructive) {
                    approve("停止连接并移除已保存的配置？不会删除 MCP 程序或其文件。") { store.removeServer(server) }
                }.disabled(running)
            }.padding(24)
        }
    }
    private var connectionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox("首启检查与恢复") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(store.setupChecks) { result in
                            HStack(alignment: .top) { Image(systemName: result.passed ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(result.passed ? Color.green : Color.orange); VStack(alignment: .leading) { Text(result.label).font(.caption.bold()); Text(result.detail).font(.caption).foregroundStyle(.secondary) } }
                        }
                        HStack { Button("重新检查路径") { store.checkSetup() }; Text("这里只读检查文件；握手与联网操作需单独确认。").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                GroupBox("1 · 本机网关") {
                    Form {
                        HStack { TextField("Node 可执行文件", text: $store.preferences.nodePath); Button("选择") { store.choosePath("node") } }
                        HStack { TextField("已构建的网关脚本", text: $store.preferences.gatewayScript); Button("选择") { store.choosePath("gateway") } }
                        TextField("本机端口", value: $store.preferences.port, format: .number.grouping(.never))
                    }.formStyle(.grouped).disabled(store.isGatewayRunning)
                    HStack {
                        Text("仅监听 127.0.0.1。启动网关不会自动启动 MCP。").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("启动网关") { approve("确认运行所选 Node 可执行文件与网关脚本，仅监听 127.0.0.1:\(store.preferences.port)?") { store.startGateway() } }.disabled(store.isGatewayRunning).buttonStyle(.glassProminent)
                        Button("停止") { store.stopGateway() }.disabled(!store.isGatewayRunning)
                    }.padding(10)
                }
                GroupBox("2 · 出口模式") {
                    Picker("路由模式", selection: $store.preferences.mode) {
                        Text("聚合 · 一个隧道").tag("aggregate")
                        Text("独立 · 每个 MCP 一个隧道").tag("individual")
                    }.pickerStyle(.segmented).padding(10)
                    Text("聚合路由为 /mcp，独立路由为 /servers/{id}/mcp。两组本机路由同时存在；这里选择管理哪组隧道。切换前先停止隧道。").font(.caption).foregroundStyle(.secondary).padding(10)
                }.disabled(store.tunnelStates.keys.contains { store.tunnelRunning($0) })
                GroupBox("3 · 官方 OpenAI 隧道客户端") {
                    Form {
                        HStack { TextField("tunnel-client 绝对路径", text: $store.preferences.tunnelClientPath); Button("选择") { store.choosePath("tunnel") } }
                        SecureField("运行时 API key：仅内存保存", text: $store.tunnelKey)
                    }.formStyle(.grouped)
                    Text("需已有 tunnel、Platform Read + Use 权限及正确的 ChatGPT 工作区关联。密钥和隧道由你自行创建。").font(.caption).foregroundStyle(.secondary).padding(10)
                    HStack { Link("安装官方 tunnel-client", destination: URL(string: "https://github.com/openai/tunnel-client#readme")!); Link("Platform 隧道设置", destination: URL(string: "https://platform.openai.com/settings/organization/tunnels")!); Link("官方配置文档", destination: URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!); Link("ChatGPT Plugins", destination: URL(string: "https://chatgpt.com/plugins")!) }.padding(10)
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
                if store.preferences.mode == "aggregate" { tunnelPanel(server: nil, index: nil) }
                else { Text("请从侧栏选择服务器，配置其独立隧道。").foregroundStyle(.secondary) }
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
                    Button("初始化 profile") { approve("执行官方 tunnel-client init，为 \(store.endpoint(server)) 创建本机 profile？请使用新的唯一名称；若已存在请检查 CLI 输出。此操作不会启动服务。") { store.tunnelAction("init", server: server) } }.disabled(store.tunnelRunning(key))
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
