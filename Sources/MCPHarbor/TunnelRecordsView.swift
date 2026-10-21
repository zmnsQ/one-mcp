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

private struct TunnelDetailSession: Identifiable {
    let id: String
    let workspace: String
}

struct TunnelRecordsView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var editing: TunnelEditSession?
    @State private var inspecting: TunnelDetailSession?
    @State private var startRecord: TunnelRecord?
    @State private var startPlan: Preferences?
    @State private var startWorkspace = ""
    @State private var startRevision = ""
    @State private var showStart = false

    private func edit(_ record: TunnelRecord, isNew: Bool = false) {
        editing = TunnelEditSession(record: record, isNew: isNew, preferences: store.preferences,
                                    workspace: store.currentWorkspaceID, revision: store.savedRevision, runtimeKey: store.recordTunnelKeyForEditing(record.id))
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(store.preferences.effectiveTunnelRecords) { record in
                    tunnelCard(record)
                }
            }
        }
        .sheet(item: $inspecting) { session in
            TunnelRecordDetails(session: session).environmentObject(store)
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
    private func tunnelCard(_ record: TunnelRecord) -> some View {
        let status = store.menuTunnelStatus(record.id)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: record.transport == "openai" ? "point.3.connected.trianglepath.dotted" : "cloud.fill")
                    .font(.title3).foregroundStyle(record.transport == "openai" ? Color.teal : Color.orange)
                    .frame(width: 42, height: 42)
                    .background((record.transport == "openai" ? Color.teal : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.name).font(.headline).lineLimit(1).help(record.name)
                    Text(record.transport == "openai" ? "OpenAI · 私有隧道" : "Cloudflare · 公网入口")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(record.transport == "openai" ? Color.teal : Color.orange)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((record.transport == "openai" ? Color.teal : Color.orange).opacity(0.08), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            HStack {
                StatusBadge(status: status)
                Spacer()
                Text("\(record.serverIDs.count) 个 MCP").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("绑定服务").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(TunnelRecordPresentation.bindingSummary(record, servers: store.preferences.servers))
                    .font(.callout).lineLimit(2).frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    .help(TunnelRecordPresentation.bindingSummary(record, servers: store.preferences.servers))
            }
            Divider()
            HStack(spacing: 8) {
                Button("详情", systemImage: "info.circle") {
                    inspecting = TunnelDetailSession(id: record.id, workspace: store.currentWorkspaceID)
                }
                Button("编辑", systemImage: "slider.horizontal.3") { edit(record) }
                Spacer(minLength: 0)
                if store.tunnelRunning(record.id) {
                    Button("停止", systemImage: "stop.fill") { store.stopTunnel(record.id) }
                        .disabled(store.hasPendingCommand(for: record.id))
                } else {
                    Button("启动", systemImage: "play.fill") {
                        startRecord = record; startPlan = store.preferences; startWorkspace = store.currentWorkspaceID
                        startRevision = store.savedRevision; showStart = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.startAllBusy || !store.gatewayReady || store.hasPendingCommand(for: record.id) || record.serverIDs.isEmpty)
                }
            }.controlSize(.small)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct TunnelRecordDetails: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let session: TunnelDetailSession
    private var record: TunnelRecord? {
        guard session.workspace == store.currentWorkspaceID else { return nil }
        return store.preferences.effectiveTunnelRecords.first { $0.id == session.id }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record?.name ?? "隧道详情").font(.title2.bold()).lineLimit(2)
                    Text("只读详情 · 不会启动隧道或修改配置").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                if let record {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label(record.transport == "openai" ? "OpenAI" : "Cloudflare", systemImage: "network").font(.headline)
                            Spacer()
                            StatusBadge(status: store.menuTunnelStatus(record.id))
                        }
                        detailSection("绑定的 MCP 服务", icon: "square.stack.3d.up") {
                            Text(TunnelRecordPresentation.bindingSummary(record, servers: store.preferences.servers))
                            ForEach(record.serverIDs, id: \.self) { id in
                                Label(store.preferences.servers.first(where: { $0.id == id })?.name ?? "已移除服务：\(id)", systemImage: "server.rack")
                            }
                        }
                        detailSection("连接地址", icon: "link") {
                            HStack { Text("本地入口（仅本机）").font(.caption).foregroundStyle(.secondary); Spacer(); Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.endpoint(record: record), forType: .string) } }
                            Text(store.endpoint(record: record)).font(.callout.monospaced()).textSelection(.enabled)
                            if record.transport == "cloudflare" {
                                HStack { Text("公网入口").font(.caption).foregroundStyle(.secondary); Spacer(); if let url = store.recordCloudflarePublicURLs[record.id] { Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) } } }
                                Text(store.recordCloudflarePublicURLs[record.id] ?? "尚未观测到公网地址")
                                    .font(.callout.monospaced()).textSelection(.enabled)
                            }
                        }
                        detailSection("健康与诊断", icon: "waveform.path.ecg") {
                            Text(store.tunnelStates[record.id] ?? "尚无运行诊断")
                            if !store.tunnelRestartReasons(record.id).isEmpty {
                                Label("待重启：" + store.tunnelRestartReasons(record.id).joined(separator: "、"), systemImage: "arrow.clockwise")
                                    .foregroundStyle(.orange)
                            }
                            if record.transport == "openai", store.tunnelRunning(record.id), store.tunnelHealthURLs[record.id] != nil {
                                TunnelDashboardPanel(snapshot: store.tunnelHealthSnapshots[record.id])
                            } else {
                                Text("暂无可展示的实时组件健康数据。请在编辑中的认证与维护里执行连接检查。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("进程运行和本地就绪均不代表远端工具调用已验证。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        detailSection("记录信息", icon: "doc.text") {
                            Text("记录 ID：\(record.id)").textSelection(.enabled)
                            Text(record.participatesInStartAll ? "参与全部启动" : "仅单独启动")
                            if record.transport == "openai" {
                                Text("Profile：\(record.profile)").textSelection(.enabled)
                                if let location = store.tunnelProfileLocations[record.id] {
                                    Text(location).textSelection(.enabled)
                                }
                            }
                        }
                    }.padding(20)
                } else {
                    ContentUnavailableView("记录已改变", systemImage: "arrow.triangle.2.circlepath", description: Text("工作空间已切换或记录已删除，请关闭后重新打开。"))
                        .padding(20)
                }
            }
        }.frame(width: 620, height: 660)
    }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
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
    @State private var savedDraft: TunnelRecord?
    @State private var acceptedPreferences: Preferences?
    @State private var acceptedRevision: String?
    @State private var createProfile: Bool
    @State private var submitted = false
    init(session: TunnelEditSession) {
        self.session = session
        _record = State(initialValue: session.record)
        _runtimeKey = State(initialValue: session.runtimeKey)
        _committedRuntimeKey = State(initialValue: session.runtimeKey)
        _createProfile = State(initialValue: session.isNew)
    }
    private var recordID: String { record.id }
    private var unsaved: Bool { (session.isNew && savedDraft == nil) || record != (savedDraft ?? session.record) || runtimeKey != committedRuntimeKey }
    private var phase: TunnelProfileCreation? { submitted ? store.profileCreation[recordID] : nil }
    private var completed: Bool { phase == .succeeded }
    private var wantsCreation: Bool { record.transport == "openai" && createProfile }
    private var primaryTitle: String { completed ? "完成" : wantsCreation ? "创建并保存本地 Profile" : "保存配置" }

    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    private var busy: Bool { store.startAllBusy || store.tunnelRunning(recordID) || store.hasPendingCommand(for: recordID) || store.profileCreation[recordID]?.isInFlight == true }
    private var contextChanged: Bool {
        session.workspace != store.currentWorkspaceID || (acceptedPreferences ?? session.preferences) != store.preferences || (acceptedRevision ?? session.revision) != store.savedRevision
    }
    private func binding<Value>(_ key: WritableKeyPath<TunnelRecord, Value>) -> Binding<Value> {
        Binding(get: { record[keyPath: key] }, set: { record[keyPath: key] = $0 })
    }
    private func save(initialize: Bool = true, closeAfterSave: Bool = true) {
        if completed { dismiss(); return }
        guard !busy, !contextChanged else { saveError = "配置或运行状态已改变，请取消并重新打开编辑。"; return }
        if wantsCreation && initialize {
            guard store.gatewayReady, store.requireScopedTunnelRuntime(), store.requireProfileCreationRuntime() else {
                saveError = store.errorMessage ?? "请先启动新版本机网关，再创建本地 Profile；不会自动启动或公开服务。"; return
            }
            guard record.tunnelID.range(of: "^tunnel_[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
                  record.profile.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
                  (record.profileFile ?? "").isEmpty else {
                saveError = "请填写已有的 OpenAI Tunnel ID 和唯一 Profile 名称；已有 Profile 文件请选择“使用已有 Profile”。"; return
            }
        }
        do {
            if let account = record.accountID {
                let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { record.accountID = nil }
                else if let normalized = TunnelCredentialReferencePolicy.normalizedAccountID(trimmed) { record.accountID = normalized }
                else { saveError = "账号标识须为 1–100 个字符，不得包含空字符。"; return }
            }
            let updated = try TunnelRecordPresentation.applying(record, isNew: session.isNew && savedDraft == nil, to: store.preferences)
            let previous = store.preferences
            store.preferences = updated
            guard store.save() else {
                store.preferences = previous; saveError = store.errorMessage ?? "保存失败，草稿已保留，未创建 Profile。"; return
            }
            // Persist the stable record identity before invoking any external process.
            // Retry edits the same record; a failed save never triggers initialization.
            savedDraft = record; acceptedPreferences = store.preferences; acceptedRevision = store.savedRevision
            let previousAccount = previous.effectiveTunnelRecords.first { $0.id == recordID }?.accountID
            if TunnelCredentialReferencePolicy.normalizedAccountID(previousAccount) != TunnelCredentialReferencePolicy.normalizedAccountID(record.accountID) {
                store.clearRecordTunnelKeyForAccountChange(recordID)
            }
            store.setRecordTunnelKey(record.credentialSourceRecordID == nil ? runtimeKey : "", for: recordID)
            committedRuntimeKey = runtimeKey
            saveError = nil
            guard wantsCreation && initialize else { if closeAfterSave { dismiss() }; return }
            submitted = true
            if !store.tunnelAction("init", record: record, persistConfiguration: false) {
                store.profileCreation[recordID] = .failed
                saveError = store.errorMessage ?? "配置已保存，但 Profile 创建未提交。"
            }
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
                    Text("账号与凭据 → 隧道配置 → 创建并保存。启动仍需单独确认。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    configuration.disabled(busy || contextChanged || completed)
                    if busy { Label("隧道运行或操作中，停止后可修改配置。", systemImage: "info.circle").font(.caption) }
                    if contextChanged { Text("配置已在其他位置改变，请取消后重新打开。").foregroundStyle(.orange) }
                    if let phase {
                        Label(phase.message, systemImage: completed ? "checkmark.circle.fill" : "info.circle")
                            .font(.callout).foregroundStyle(completed ? Color.green : Color.secondary)
                        if phase == .failed || phase == .unknown {
                            Text(store.tunnelStates[recordID] ?? "请核对 Profile 路径与网关状态。")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if !session.isNew || savedDraft != nil {
                        DisclosureGroup("连接检查与维护（可选）") {
                            VStack(alignment: .leading, spacing: 12) {
                                if unsaved { Text("先保存配置，再进行认证和连接检查。").font(.caption) }
                                if record.transport == "openai" { credentials }
                                actions.disabled(unsaved)
                            }.padding(.top, 8).disabled(contextChanged)
                        }
                    }
                    if wantsCreation {
                        Text("将为已有 Tunnel ID 创建本地 Profile，不创建 Platform 远端隧道，也不启动隧道。已有文件不会覆盖。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !store.gatewayReady { Text("请先启动本机网关，再点击创建。草稿可留在此处；不会自动启动网关。 ").font(.caption).foregroundStyle(.orange) }
                    }
                    if let saveError { Text(saveError).foregroundStyle(.red).font(.callout) }
                }.padding(20)
            }
            Divider()
            HStack {
                Button(savedDraft == nil ? "取消" : busy ? "关闭（创建继续）" : "关闭（配置已保留）", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(primaryTitle) { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!completed && (busy || contextChanged || record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || record.serverIDs.isEmpty || (wantsCreation && !store.gatewayReady)))
            }.padding(20)
        }.frame(width: 660, height: 720).textFieldStyle(.roundedBorder)
        .interactiveDismissDisabled(unsaved || busy)
        .alert("确认隧道操作", isPresented: $showConfirmation) {
            Button("取消", role: .cancel) { pendingAction = nil }
            Button("继续") { let action = pendingAction; pendingAction = nil; action?() }
        } message: { Text(confirmation) }
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("连接方式", selection: binding(\.transport)) {
                Text("OpenAI 私有隧道").tag("openai")
                Text("Cloudflare 公网入口").tag("cloudflare")
            }.pickerStyle(.segmented)
            if record.transport == "openai" { accountConfiguration }
            Divider()
            Text("2 · 隧道基础配置").font(.headline)
            TextField("隧道名称", text: binding(\.name))
            Text("绑定的 MCP 服务（至少选择一个）").font(.subheadline.bold())
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
            if record.transport == "openai" { openAIConfiguration } else { cloudflareConfiguration }
            DisclosureGroup("高级设置") {
                Toggle("参与全部启动", isOn: Binding(get: { record.participatesInStartAll }, set: { binding(\.startWithAll).wrappedValue = $0 })).padding(.top, 8)
            }
        }
    }
    private var knownAccounts: [String] {
        let accounts = store.preferences.effectiveTunnelRecords.compactMap(\.accountID) + [record.accountID].compactMap { $0 }
        return Array(Set(accounts)).filter { !$0.isEmpty }.sorted()
    }
    private var accountConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1 · 账号与 Runtime 凭据").font(.headline)
            Picker("已有账号", selection: Binding(get: { record.accountID ?? "" }, set: { selectAccount($0) })) {
                Text("选择账号 / 手动填写").tag("")
                ForEach(knownAccounts, id: \.self) { account in
                    Text(account).tag(account)
                }
            }
            TextField("账号标识，例如工作区名称（不是 API Key）", text: Binding(get: { record.accountID ?? "" }, set: { selectAccount($0) }))
            Text("账号是本机分类标签，请核对实际 OpenAI 工作区。只复用此账号明确关联的钥匙串凭据。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Runtime API Key", selection: Binding(get: { record.credentialSourceRecordID ?? "" }, set: { value in
                record.credentialSourceRecordID = value.isEmpty ? nil : value; runtimeKey = ""
            })) {
                Text("本次输入 / 此记录已有凭据").tag("")
                ForEach(store.reusableCredentialRecords(for: record.accountID ?? "").filter { $0.id != recordID }) { source in
                    Text("复用：" + source.name + "（钥匙串引用）").tag(source.id)
                }
            }
            if record.credentialSourceRecordID == nil {
                SecureField("Runtime API Key（已有 Profile 可留空）", text: $runtimeKey)
                Text("仅用于本次会话；保存到钥匙串需另行明确确认。已有密钥不显示、不复制到新配置。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("使用已有安全引用，无需重复填写密钥", systemImage: "key.fill").font(.caption).foregroundStyle(.teal)
            }
            if !session.isNew, record.credentialSourceRecordID == nil, !(record.accountID ?? "").isEmpty {
                Button("将已有钥匙串密钥关联到此账号") {
                    let draft = record
                    confirmation = "保存账号设置，并确认此隧道已存的钥匙串密钥属于账号“\(record.accountID ?? "")”？之后此账号的隧道可引用它。不会读取、复制密钥或创建 Profile。"
                    pendingAction = {
                        guard !busy, !contextChanged, record == draft else { saveError = "配置已改变，请重新核对账号。"; return }
                        save(initialize: false, closeAfterSave: false)
                        if saveError == nil, savedDraft == record {
                            _ = store.associateRecordCredentialWithAccount(recordID)
                            runtimeKey = ""; committedRuntimeKey = ""
                        }
                    }
                    showConfirmation = true
                }
                Text(store.tunnelCredentialStatus).font(.caption).foregroundStyle(.secondary)
            }
            if store.reusableCredentialRecords(for: record.accountID ?? "").isEmpty {
                Text("旧记录未标注账号时：先编辑原隧道，保存账号后，明确关联已有钥匙串密钥；之后同账号可直接复用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func selectAccount(_ account: String) {
        guard account != (record.accountID ?? "") else { return }
        record.accountID = account.isEmpty ? nil : account
        record.credentialSourceRecordID = nil
        runtimeKey = ""
        // Auto-select only an unambiguous, explicitly account-bound safe reference.
        let sources = store.reusableCredentialRecords(for: account).filter { $0.id != recordID }
        if sources.count == 1 { record.credentialSourceRecordID = sources[0].id }
    }
    private var openAIConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("已有 OpenAI Tunnel ID（tunnel_…）", text: binding(\.tunnelID))
            Link("在 OpenAI Platform 管理 Tunnel", destination: TunnelHelp.tunnels)
            Text("3 · 本地 Profile").font(.headline)
            Picker("保存方式", selection: $createProfile) {
                Text("创建本地 Profile").tag(true)
                Text("使用已有 Profile / 仅保存更改").tag(false)
            }.pickerStyle(.segmented)
            TextField("Profile 名称", text: binding(\.profile))
            if !createProfile {
                HStack {
                    TextField("可选：已有 Profile 文件绝对路径", text: Binding(get: { record.profileFile ?? "" }, set: { binding(\.profileFile).wrappedValue = $0.isEmpty ? nil : $0 }))
                    Button("选择文件") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { binding(\.profileFile).wrappedValue = url.path }
                    }
                }
            }
            if let location = store.tunnelProfileLocations[recordID] { Text(location).font(.caption).textSelection(.enabled) }
        }
        .onChange(of: createProfile) { _, creating in if creating { record.profileFile = nil } }
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
            Text("密钥输入与引用选择位于顶部账号区域；以下仅管理本机保存。 ").font(.caption)
            HStack {
                Button("保存密钥并自动填入") { approve("将此隧道的 Runtime API Key 保存到本机钥匙串，并允许以后自动填入？不会写入配置或导出文件。") { store.saveRecordTunnelKey(recordID) } }
                    .disabled(unsaved || (store.recordTunnelKeyForEditing(recordID)).isEmpty)
                Button("从钥匙串载入") { store.loadRecordTunnelKey(recordID); runtimeKey = store.recordTunnelKeyForEditing(recordID); committedRuntimeKey = runtimeKey }.disabled(unsaved)
                Button("忘记此隧道密钥") { approve("删除此隧道的新格式已存密钥？旧版工作空间密钥保留，服务端密钥不会撤销。") { store.forgetRecordTunnelKey(recordID); runtimeKey = store.recordTunnelKeyForEditing(recordID); committedRuntimeKey = runtimeKey } }.disabled(unsaved)
            }
            Text(store.tunnelCredentialStatus).font(.caption).foregroundStyle(.secondary)
        }.disabled(busy || record.credentialSourceRecordID != nil)
    }
    private var actions: some View {
        HStack {
            if record.transport == "openai" {
                Text("创建操作已移至主按钮，无需展开维护。").font(.caption).foregroundStyle(.secondary)
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
