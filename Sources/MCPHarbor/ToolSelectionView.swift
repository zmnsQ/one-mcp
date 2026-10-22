import SwiftUI

/// Switches edit a draft; only the explicit apply action changes runtime exposure.
struct ToolSelectionView: View {
    @EnvironmentObject private var store: HarborStore
    @Binding var server: ServerConfig
    let confirm: (String, @escaping () -> Void) -> Void
    @State private var search = ""
    private var running: Bool { store.states[server.id] == "running" }
    private var live: Set<String>? {
        guard let runtime = store.sharedRuntimeServers.first(where: { $0.id == server.id && $0.running }), runtime.permissionsKnown else { return nil }
        return Set(runtime.allowedTools)
    }
    private var selected: Set<String> { Set(server.allowedTools) }
    private var catalog: [ToolInfo] { store.tools[server.id] ?? [] }
    private var visible: [ToolInfo] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }
    private var unavailable: [String] { selected.subtracting(Set(catalog.map(\.name))).sorted() }
    private var busy: Bool { store.hasPendingCommand(for: server.id) || store.startAllBusy || ["starting", "stopping"].contains(store.states[server.id] ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("允许使用的工具", systemImage: "switch.2").font(.title3.bold())
                Text("\(server.name) · 目录 \(catalog.count) 项 · 已选 \(selected.count) 项 · " + liveSummary).font(.caption).foregroundStyle(.secondary)
                Text("默认关闭；修改开关后，点击下方按钮保存并应用。").font(.caption).foregroundStyle(.secondary)
            }
            if let change = store.toolChanges[server.id] { Label(change, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            TextField("搜索工具名称或用途", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("搜索当前服务的工具名称或用途")
            HStack(alignment: .top) {
                Button("刷新工具目录", systemImage: "arrow.clockwise") { store.command("listTools", params: ["serverId": server.id]) }.disabled(!running || busy)
                Text("仅查询目录，不会自动勾选或开放新工具。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if catalog.isEmpty {
                Label("尚未发现工具", systemImage: "tray").font(.headline)
                Text("点击上方启动按钮读取目录，再逐项选择。").font(.callout).foregroundStyle(.secondary)
            } else if visible.isEmpty { Text("没有匹配的工具。试试其他名称或用途关键词。").foregroundStyle(.secondary) }
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visible) { tool in
                    ToolSelectionCard(tool: tool, selected: Binding(get: { server.allowedTools.contains(tool.name) }, set: { enabled in
                        if enabled && !server.allowedTools.contains(tool.name) { server.allowedTools.append(tool.name) }
                        if !enabled { server.allowedTools.removeAll { $0 == tool.name } }
                    }), status: status(for: tool.name)).disabled(busy)
                }
            }
            if !unavailable.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("已选但不在当前目录", systemImage: "exclamationmark.triangle").font(.caption.bold()).foregroundStyle(.orange)
                    Text("当前目录不可调用这些工具；保留的选择会在工具重新出现时允许调用，可逐项取消。").font(.caption).foregroundStyle(.secondary)
                    ForEach(unavailable, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { server.allowedTools.contains(name) }, set: { enabled in
                            if !enabled { server.allowedTools.removeAll { $0 == name } }
                        })).toggleStyle(.switch).disabled(busy)
                    }
                }.padding(12).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(selectionSummary).font(.caption.weight(.semibold)).foregroundStyle(running && live != selected ? Color.orange : Color.secondary)
                Button(running ? "保存并应用工具选择" : "保存工具选择", systemImage: "checkmark.shield", action: apply)
                    .buttonStyle(.borderedProminent).disabled(busy || (running && !store.gatewayReady))
                Text("仅应用工具选择，不重启进程。客户端需刷新工具或重连（无状态 HTTP 不推送目录变更）。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
    private func apply() {
        let id = server.id
        let workspace = store.currentWorkspaceID
        let revision = store.savedRevision
        let confirmedSelection = selected
        let confirmedLive = live
        if running {
            let message: String
            if let live {
                message = "保存并应用 \(server.name) 的工具选择？新增 \(selected.subtracting(live).count) 项，移除 \(live.subtracting(selected).count) 项权限。不重启进程。"
            } else {
                message = "当前运行授权尚未核对。将保存并应用 \(server.name) 的 \(selected.count) 项工具选择？这可能新增工具权限，不重启进程。"
            }
            confirm(message) {
                let currentDraft = store.preferences.servers.first { $0.id == id }
                let currentRuntime = store.sharedRuntimeServers.first { $0.id == id && $0.running && $0.permissionsKnown }
                let currentLive = currentRuntime.map { Set($0.allowedTools) }
                guard store.currentWorkspaceID == workspace, store.savedRevision == revision,
                      store.states[id] == "running", let currentDraft,
                      Set(currentDraft.allowedTools) == confirmedSelection, currentLive == confirmedLive else {
                    store.errorMessage = "工具选择或运行状态已改变，请重新核对后应用。"
                    return
                }
                store.applyToolSelection(id)
            }
        } else { store.applyToolSelection(id) }
    }
    private var liveSummary: String {
        if !running { return "当前未运行" }
        guard let live else { return "生效数量待核对" }
        return "运行授权 \(live.count) 项"
    }
    private var selectionSummary: String {
        if !running { return "保存后用于下次启动；不会启动服务。" }
        guard let live else { return "运行授权待核对，不能确认当前选择已应用。" }
        return live == selected ? "工具选择与运行授权一致。" : "待应用：新增 \(selected.subtracting(live).count) 项，移除 \(live.subtracting(selected).count) 项。"
    }
    private func status(for name: String) -> String {
        if !running { return selected.contains(name) ? "已选 · 下次启动使用" : "未选择" }
        guard let live else { return "运行授权待核对" }
        let chosen = selected.contains(name), active = live.contains(name)
        if chosen != active { return chosen ? "待应用 · 新增" : "待应用 · 移除（当前仍开放）" }
        return active ? "已生效" : "未开放"
    }
}

private struct ToolSelectionCard: View {
    let tool: ToolInfo
    @Binding var selected: Bool
    let status: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: $selected) {
                Text(tool.name).font(.system(.body, design: .monospaced).weight(.semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.toggleStyle(.switch).accessibilityLabel("允许工具 \(tool.name)")
            Text(tool.description.isEmpty ? "此服务未提供用途说明，请核对后再授权。" : tool.description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(status).font(.caption.weight(.medium)).foregroundStyle(status.hasPrefix("待") ? Color.orange : Color.secondary)
            DisclosureGroup("技术详情：公开名称、参数与标注") {
                VStack(alignment: .leading, spacing: 8) { Text(tool.publicName); Text(tool.metadataJSON) }
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15)))
    }
}
