import SwiftUI

extension HarborStore {
    func recordServiceLogSnapshotEvent(_ event: [String: Any], instanceID: String, sequence: Int) {
        let known = Set(preferences.servers.map(\.id) + sharedRuntimeServers.map(\.id))
        serviceLogs.retain(serverIDs: known)
        serviceLogs.ingestSnapshot(event, instanceID: instanceID, sequence: sequence, knownServerIDs: known)
    }

    func recordServiceLogEvent(_ event: [String: Any]) {
        let known = Set(preferences.servers.map(\.id) + sharedRuntimeServers.map(\.id))
        serviceLogs.retain(serverIDs: known)
        serviceLogs.ingest(event, knownServerIDs: known)
    }
}

struct ServiceLogView: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    @State private var errorsOnly = false
    private var allLines: [ServiceLogEntry] { store.serviceLogs.lines(for: server.id) }
    private var lines: [ServiceLogEntry] { errorsOnly ? allLines.filter { $0.level == "错误" } : allLines }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(server.name) · 服务日志", systemImage: "doc.text.magnifyingglass").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("实时更新 · 最近 \(ServiceLogBuffer.defaultLimit) 条 · 仅本次会话")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("记录范围") {
                Text("记录本机网关观察到的生命周期、调用结果和安全诊断。时间为本应用的接收时间，不是远端事件发生时间。不会显示 MCP 标准输出、原始标准错误、请求参数或返回内容；不读取远端服务内部日志。共享网关只提供当前可用的近期事件，并非完整历史。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.caption)
            HStack {
                Text("\(lines.count) 条").font(.caption)
                Toggle("仅错误", isOn: $errorsOnly).toggleStyle(.checkbox).font(.caption)
                Spacer()
                Button("清空此服务日志") { store.serviceLogs.clear(serverID: server.id) }.disabled(allLines.isEmpty)
            }
            if lines.isEmpty {
                ContentUnavailableView(errorsOnly ? "暂无错误日志" : "暂无服务日志", systemImage: "doc.text", description: Text("后续收到此服务的运行事件后会显示在这里。其他服务的日志不会混入。"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: 10) {
                                Text(line.time, style: .time).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                Text(line.level).foregroundStyle(line.level == "错误" ? Color.orange : Color.secondary).frame(width: 40)
                                Text(line.text).frame(maxWidth: .infinity, alignment: .leading)
                            }.font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.background(Color.secondary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }.padding(24).frame(minWidth: 520, idealWidth: 720, minHeight: 460, idealHeight: 560)
    }
}
