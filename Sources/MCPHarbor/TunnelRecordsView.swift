import SwiftUI
import AppKit

private struct TunnelEditSession: Identifiable {
    let id = UUID()
    let record: TunnelRecord
    let isNew: Bool
    let preferences: Preferences
    let workspace: String
    let revision: String
    let runtimeKey: String
}

struct TunnelRecordsView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var editing: TunnelEditSession?
    @State private var startRecord: TunnelRecord?
    @State private var startPlan: Preferences?
    @State private var startWorkspace = ""
    @State private var startRevision = ""
    @State private var showStart = false

    private func edit(_ record: TunnelRecord, isNew: Bool = false) {
        editing = TunnelEditSession(record: record, isNew: isNew, preferences: store.preferences,
                                    workspace: store.currentWorkspaceID, revision: store.savedRevision, runtimeKey: store.recordTunnelKeys[record.id] ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("隧道").font(.title2.bold())
                Spacer()
                Button("添加隧道", systemImage: "plus") {
                    var record = TunnelRecord()
                    record.name = "隧道 \(store.preferences.effectiveTunnelRecords.count + 1)"
                    record.profile = "onemcp-" + String(record.id.prefix(12))
                    edit(record, isNew: true)
                }.disabled(store.startAllBusy || store.preferences.effectiveTunnelRecords.count >= 32)
            }
            if store.preferences.effectiveTunnelRecords.isEmpty {
                ContentUnavailableView("还没有隧道", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("添加一条隧道，选择要连接的 MCP 服务。"))
            }
            ForEach(store.preferences.effectiveTunnelRecords) { record in
                HStack(spacing: 12) {
                    Image(systemName: "network").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.name).font(.headline).lineLimit(1)
                            Label(store.menuTunnelStatus(record.id).title, systemImage: store.menuTunnelStatus(record.id).symbol)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(TunnelRecordPresentation.bindingSummary(record, servers: store.preferences.servers))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    if store.tunnelRunning(record.id) {
                        Button("停止", systemImage: "stop.fill") { store.stopTunnel(record.id) }
                            .disabled(store.hasPendingCommand(for: record.id))
                    } else {
                        Button("启动", systemImage: "play.fill") {
                            startRecord = record; startPlan = store.preferences; startWorkspace = store.currentWorkspaceID
                            startRevision = store.savedRevision; showStart = true
                        }.disabled(store.startAllBusy || !store.gatewayReady || store.hasPendingCommand(for: record.id) || record.serverIDs.isEmpty)
                    }
                    Button("编辑", systemImage: "slider.horizontal.3") { edit(record) }
                }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $editing) { session in
            TunnelRecordEditor(session: session).environmentObject(store)
        }
        .alert("启动隧道？", isPresented: $showStart) {
            Button("取消", role: .cancel) { startRecord = nil }
            Button("启动") {
                guard let record = startRecord, startPlan == store.preferences,
                      startWorkspace == store.currentWorkspaceID, startRevision == store.savedRevision else {
                    store.errorMessage = "配置已改变，请重新核对后启动。"; return
                }
                if record.transport == "openai" { store.tunnelAction("run", record: record) }
                else { store.cloudflareAction("run", record: record) }
                startRecord = nil
            }
        } message: {
            if let record = startRecord {
                Text("将公开“\(record.name)”绑定的 \(record.serverIDs.count) 个 MCP 的白名单工具。数据与结果经过 \(record.transport == "openai" ? "OpenAI 工作区" : "Cloudflare 公网入口（要求 OAuth 授权）")，请确认服务、权限和目标账号。")
            }
        }
    }
}

private struct TunnelRecordEditor: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let session: TunnelEditSession
    @State private var record: TunnelRecord
    @State private var saveError: String?
    @State private var runtimeKey: String
    @State private var committedRuntimeKey: String
    init(session: TunnelEditSession) {
        self.session = session
        _record = State(initialValue: session.record)
        _runtimeKey = State(initialValue: session.runtimeKey)
        _committedRuntimeKey = State(initialValue: session.runtimeKey)
    }
    private var recordID: String { record.id }
    private var unsaved: Bool { session.isNew || record != session.record || runtimeKey != committedRuntimeKey }
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    private var busy: Bool { store.startAllBusy || store.tunnelRunning(recordID) || store.hasPendingCommand(for: recordID) }
    private var contextChanged: Bool {
        session.workspace != store.currentWorkspaceID || session.preferences != store.preferences || session.revision != store.savedRevision
    }
    private func binding<Value>(_ key: WritableKeyPath<TunnelRecord, Value>) -> Binding<Value> {
        Binding(get: { record[keyPath: key] }, set: { record[keyPath: key] = $0 })
    }
    private func save() {
        guard !busy, !contextChanged else { saveError = "配置或运行状态已改变，请取消并重新打开编辑。"; return }
        do {
            let updated = try TunnelRecordPresentation.applying(record, isNew: session.isNew, to: store.preferences)
            let previous = store.preferences
            store.preferences = updated
            if store.save() { store.recordTunnelKeys[recordID] = runtimeKey; dismiss() }
            else { store.preferences = previous; saveError = store.errorMessage ?? "保存失败，草稿已保留。" }
        } catch { saveError = error.localizedDescription }
    }
    private func cloudflare<Value>(_ key: WritableKeyPath<CloudflareSettings, Value>) -> Binding<Value> {
        Binding(get: { (record.cloudflare ?? CloudflareSettings())[keyPath: key] }, set: { value in
            var settings = record.cloudflare ?? CloudflareSettings(); settings[keyPath: key] = value
            binding(\.cloudflare).wrappedValue = settings
        })
    }
    private func approve(_ text: String, action: @escaping () -> Void) {
        let plan = store.preferences, workspace = store.currentWorkspaceID, revision = store.savedRevision
        confirmation = text
        pendingAction = {
            guard !busy, !contextChanged, !unsaved, plan == store.preferences, workspace == store.currentWorkspaceID, revision == store.savedRevision else {
                store.errorMessage = "确认期间配置已改变，请重新核对后确认。"; return
            }
            action()
        }
        showConfirmation = true
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.isNew ? "添加隧道" : "编辑隧道").font(.title2.bold())
                    Text("选择 MCP 服务，再设置连接方式。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    configuration.disabled(busy || contextChanged)
                    if busy { Label("隧道运行或操作中，停止后可修改配置。", systemImage: "info.circle").font(.caption) }
                    if contextChanged { Text("配置已在其他位置改变，请取消后重新打开。").foregroundStyle(.orange) }
                    if !session.isNew {
                        DisclosureGroup("地址与运行详情") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.endpoint(record: session.record)).textSelection(.enabled)
                                if let url = store.recordCloudflarePublicURLs[recordID] { Text(url).textSelection(.enabled) }
                                Text(store.tunnelStates[recordID] ?? "未运行")
                                if !store.tunnelRestartReasons(recordID).isEmpty {
                                    Text("待重启：" + store.tunnelRestartReasons(recordID).joined(separator: "、"))
                                }
                                if store.tunnelRunning(recordID), store.tunnelHealthURLs[recordID] != nil {
                                    TunnelDashboardPanel(snapshot: store.tunnelHealthSnapshots[recordID])
                                }
                                Text("就绪不代表远端工具调用已验证。")
                            }.font(.caption).padding(.top, 8)
                        }
                        DisclosureGroup("认证与维护") {
                            VStack(alignment: .leading, spacing: 12) {
                                if unsaved { Text("先保存配置，再进行认证和连接检查。").font(.caption) }
                                if record.transport == "openai" { credentials }
                                actions.disabled(unsaved)
                            }.padding(.top, 8).disabled(contextChanged)
                        }
                    } else {
                        Text("保存后可在编辑中配置密钥、创建 Profile 或检查连接；保存不会自动启动。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let saveError { Text(saveError).foregroundStyle(.red).font(.callout) }
                }.padding(20)
            }
            Divider()
            HStack {
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(session.isNew ? "添加" : "保存") { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(busy || contextChanged || record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || record.serverIDs.isEmpty)
            }.padding(20)
        }.frame(width: 600, height: 640).textFieldStyle(.roundedBorder)
        .interactiveDismissDisabled(unsaved)
        .alert("确认隧道操作", isPresented: $showConfirmation) {
            Button("取消", role: .cancel) { pendingAction = nil }
            Button("继续") { let action = pendingAction; pendingAction = nil; action?() }
        } message: { Text(confirmation) }
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("隧道名称", text: binding(\.name))

            Text("绑定的 MCP 服务（至少选择一个）").font(.headline)
            if store.preferences.servers.isEmpty { Text("请先在 MCP 服务页面添加一个服务。").font(.caption).foregroundStyle(.secondary) }
            ForEach(store.preferences.servers) { server in
                Toggle(server.name, isOn: Binding(get: { record.serverIDs.contains(server.id) }, set: { selected in
                    var ids = record.serverIDs.filter { $0 != server.id }
                    if selected { ids.append(server.id) }
                    binding(\.serverIDs).wrappedValue = ids
                }))
            }
            ForEach(record.serverIDs.filter { id in !store.preferences.servers.contains(where: { $0.id == id }) }, id: \.self) { id in
                HStack {
                    Text("已移除服务：\(id)").foregroundStyle(.orange)
                    Button("移除绑定") { binding(\.serverIDs).wrappedValue = record.serverIDs.filter { $0 != id } }
                }
            }
            Picker("连接方式", selection: binding(\.transport)) {
                Text("OpenAI").tag("openai")
                Text("Cloudflare").tag("cloudflare")
            }.pickerStyle(.segmented)
            if record.transport == "openai" { openAIConfiguration } else { cloudflareConfiguration }
            DisclosureGroup("高级设置") {
                Toggle("参与全部启动", isOn: Binding(get: { record.participatesInStartAll }, set: { binding(\.startWithAll).wrappedValue = $0 })).padding(.top, 8)
            }
        }
    }
    private var openAIConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("OpenAI Tunnel ID", text: binding(\.tunnelID))
            DisclosureGroup("已有 Profile 或自定义名称") {
            VStack(alignment: .leading, spacing: 8) {
            TextField("Profile 名称", text: binding(\.profile))
            Text(TunnelSetupHints.tunnel(record.tunnelID)).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("可选：已有 Profile 文件绝对路径", text: Binding(get: { record.profileFile ?? "" }, set: { binding(\.profileFile).wrappedValue = $0.isEmpty ? nil : $0 }))
                Button("选择文件") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { binding(\.profileFile).wrappedValue = url.path }
                }
            }
            if let location = store.tunnelProfileLocations[recordID] { Text(location).font(.caption).textSelection(.enabled) }
            }.padding(.top, 8)
            }
        }
    }
    private var cloudflareConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cloudflare 仅公开此记录选择的服务；共享 OAuth 认证必须先配置并重启网关生效。")
                .font(.caption).foregroundStyle(.secondary)
            Link("安装 cloudflared", destination: TunnelHelp.cloudflareInstall)
            TextField("cloudflared 可执行文件绝对路径", text: cloudflare(\.executable))
            Picker("部署方式", selection: cloudflare(\.mode)) {
                Text("固定域名 Named").tag("named"); Text("临时测试 Quick").tag("quick")
            }
            if (record.cloudflare ?? CloudflareSettings()).mode == "named" {
                TextField("Cloudflare Tunnel UUID", text: cloudflare(\.tunnelID))
                TextField("凭据 JSON 文件绝对路径（不填文件内容）", text: cloudflare(\.credentialsFile))
                TextField("固定 HTTPS 域名，不含路径", text: cloudflare(\.publicURL))
            } else {
                Text("Quick 地址可能改变，只用于短期测试；OAuth audience 仍须与实际公开地址匹配。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private var credentials: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("此隧道 Runtime API Key（已有 Profile 凭据可留空）", text: $runtimeKey)
            HStack {
                Button("保存密钥并自动填入") { approve("将此隧道的 Runtime API Key 保存到本机钥匙串，并允许以后自动填入？不会写入配置或导出文件。") { store.saveRecordTunnelKey(recordID) } }
                    .disabled(unsaved || (store.recordTunnelKeys[recordID] ?? "").isEmpty)
                Button("从钥匙串载入") { store.loadRecordTunnelKey(recordID); runtimeKey = store.recordTunnelKeys[recordID] ?? ""; committedRuntimeKey = runtimeKey }.disabled(unsaved)
                Button("忘记此隧道密钥") { approve("删除此隧道的新格式已存密钥？旧版工作空间密钥保留，服务端密钥不会撤销。") { store.forgetRecordTunnelKey(recordID); runtimeKey = store.recordTunnelKeys[recordID] ?? ""; committedRuntimeKey = runtimeKey } }.disabled(unsaved)
            }
            Text(store.tunnelCredentialStatus).font(.caption).foregroundStyle(.secondary)
        }.disabled(busy)
    }
    private var actions: some View {
        HStack {
            if record.transport == "openai" {
                Button("创建 Profile") { approve("为 \(record.name) 创建本机 OpenAI Profile？使用唯一名称；这不会启动隧道。") { store.tunnelAction("init", record: record) } }
                    .disabled(busy || !store.gatewayReady || !(record.profileFile ?? "").isEmpty)
            }
            Button("检查连接") { approve("检查 \(record.name) 的连接配置？OpenAI 检查可能连接 OpenAI；Cloudflare 检查不发布公网入口。") {
                if record.transport == "openai" { store.tunnelAction("doctor", record: record) } else { store.cloudflareAction("doctor", record: record) }
            } }.disabled(busy || !store.gatewayReady || record.serverIDs.isEmpty)
            Spacer()
            Button("删除记录", role: .destructive) { approve("删除隧道记录 \(record.name)？本机 Profile 和钥匙串凭据保留。") {
                let previous = store.preferences
                store.preferences.tunnelRecords = store.preferences.effectiveTunnelRecords.filter { $0.id != recordID }
                if store.save() { dismiss() } else { store.preferences = previous; saveError = store.errorMessage }
            } }.disabled(busy)
        }
    }
}
