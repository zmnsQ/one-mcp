import SwiftUI
import AppKit

struct TunnelRecordsView: View {
    @EnvironmentObject private var store: HarborStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("隧道记录").font(.title2)
                Spacer()
                Button("添加隧道", systemImage: "plus") {
                    var records = store.preferences.effectiveTunnelRecords
                    var record = TunnelRecord()
                    record.name = "隧道 \(records.count + 1)"
                    record.profile = "onemcp-" + String(record.id.prefix(12))
                    records.append(record); store.preferences.tunnelRecords = records
                }.disabled(store.startAllBusy || store.preferences.effectiveTunnelRecords.count >= 32)
            }
            if store.preferences.effectiveTunnelRecords.isEmpty {
                Text("添加一条隧道，再选择一个或多个 MCP 服务。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.preferences.effectiveTunnelRecords) { record in
                TunnelRecordEditor(recordID: record.id).environmentObject(store)
            }
        }
    }
}

private struct TunnelRecordEditor: View {
    @EnvironmentObject private var store: HarborStore
    let recordID: String
    @State private var confirmation = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showConfirmation = false
    private var record: TunnelRecord {
        store.preferences.effectiveTunnelRecords.first(where: { $0.id == recordID }) ?? TunnelRecord(id: recordID)
    }
    private var busy: Bool { store.startAllBusy || store.tunnelRunning(recordID) || store.hasPendingCommand(for: recordID) }
    private func binding<Value>(_ key: WritableKeyPath<TunnelRecord, Value>) -> Binding<Value> {
        Binding(get: { record[keyPath: key] }, set: { value in
            var records = store.preferences.effectiveTunnelRecords
            guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
            records[index][keyPath: key] = value; store.preferences.tunnelRecords = records
        })
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
            guard plan == store.preferences, workspace == store.currentWorkspaceID, revision == store.savedRevision else {
                store.errorMessage = "确认期间配置已改变，请重新核对后确认。"; return
            }
            action()
        }
        showConfirmation = true
    }
    var body: some View {
        GroupBox(record.name) {
            VStack(alignment: .leading, spacing: 14) {
                configuration.disabled(busy)
                Text(store.endpoint(record: record)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text(store.tunnelStates[recordID] ?? "未运行").font(.caption).foregroundStyle(.secondary)
                if !store.tunnelRestartReasons(recordID).isEmpty {
                    Text("待重启生效：" + store.tunnelRestartReasons(recordID).joined(separator: "、")).font(.caption).foregroundStyle(.orange)
                }
                if record.transport == "openai" { credentials }
                if let url = store.recordCloudflarePublicURLs[recordID] {
                    Text("本次公网入口：\(url)").font(.caption).textSelection(.enabled)
                }
                actions
                if store.tunnelRunning(recordID), store.tunnelHealthURLs[recordID] != nil {
                    TunnelDashboardPanel(snapshot: store.tunnelHealthSnapshots[recordID])
                }
                Text("进程运行或就绪状态不等同端到端调用成功；请在 ChatGPT 完成授权并测试一次可信只读工具调用。")
                    .font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder).padding(12)
        }
        .alert("确认隧道操作", isPresented: $showConfirmation) {
            Button("取消", role: .cancel) { pendingAction = nil }
            Button("继续") { let action = pendingAction; pendingAction = nil; action?() }
        } message: { Text(confirmation) }
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("隧道名称", text: binding(\.name))
            Toggle("参与全部启动", isOn: Binding(get: { record.participatesInStartAll }, set: { binding(\.startWithAll).wrappedValue = $0 }))
            Text("绑定的 MCP 服务（至少选择一个）").font(.headline)
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
        }
    }
    private var openAIConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("OpenAI Tunnel ID", text: binding(\.tunnelID))
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
            SecureField("此隧道 Runtime API Key（已有 Profile 凭据可留空）", text: Binding(get: { store.recordTunnelKeys[recordID] ?? "" }, set: { store.recordTunnelKeys[recordID] = $0 }))
            HStack {
                Button("保存密钥并自动填入") { approve("将此隧道的 Runtime API Key 保存到本机钥匙串，并允许以后自动填入？不会写入配置或导出文件。") { store.saveRecordTunnelKey(recordID) } }
                    .disabled((store.recordTunnelKeys[recordID] ?? "").isEmpty)
                Button("从钥匙串载入") { store.loadRecordTunnelKey(recordID) }
                Button("忘记此隧道密钥") { approve("删除此隧道的新格式已存密钥？旧版工作空间密钥保留，服务端密钥不会撤销。") { store.forgetRecordTunnelKey(recordID) } }
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
            Button("启动") { approve("启动 \(record.name)，公开所选 \(record.serverIDs.count) 个 MCP 的白名单工具？数据与结果会经过 \(record.transport == "openai" ? "OpenAI 工作区" : "Cloudflare 公网入口（要求 OAuth 授权）")。请核对服务、权限与目标账号。") {
                if record.transport == "openai" { store.tunnelAction("run", record: record) } else { store.cloudflareAction("run", record: record) }
            } }.buttonStyle(.glassProminent).disabled(busy || !store.gatewayReady || record.serverIDs.isEmpty)
            Button("停止") { store.stopTunnel(recordID) }.disabled(!store.tunnelRunning(recordID) || store.hasPendingCommand(for: recordID))
            Spacer()
            Button("删除记录", role: .destructive) { approve("删除隧道记录 \(record.name)？本机 Profile 和钥匙串凭据保留。") {
                store.preferences.tunnelRecords = store.preferences.effectiveTunnelRecords.filter { $0.id != recordID }
            } }.disabled(busy)
        }
    }
}
