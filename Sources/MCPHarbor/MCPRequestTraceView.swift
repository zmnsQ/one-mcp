import SwiftUI
import AppKit

struct MCPRequestTrace: Codable, Identifiable {
    let id: String; let time: String; let stage: String; let route: String; let httpMethod: String
    let hostAccepted: Bool; let originPresent: Bool; let acceptJSON: Bool; let acceptSSE: Bool; let diagnosticMarkerMatched: Bool
    let protocolHeader: String?; let rpcMethod: String?; let requestedProtocol: String?; let negotiatedProtocol: String?
    let rpcErrorCode: Int?; let toolCount: Int?; let httpStatus: Int?; let completed: Bool?
    static func decode(_ value: [String: Any]) -> Self? {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
struct ConnectionLogEvent: Codable, Identifiable {
    let id: String; let time: String; let category: String; let level: String; let code: String; let message: String
    let action: String?; let running: Bool?; let ready: Bool?; let exitCode: Int?; let toolCount: Int?
    static func decode(_ value: [String: Any]) -> Self? {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
private struct ConnectionLogRow: Identifiable {
    let id: String; let time: String; let category: String; let title: String; let detail: String; let isError: Bool
}
struct MCPRequestTracePanel: View {
    @EnvironmentObject var store: HarborStore
    @State private var search = ""
    @State private var filter = "all"
    @State private var errorsFirst = true
    @State private var feedback = ""
    private func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    private var rows: [ConnectionLogRow] {
        var result = store.connectionEvents.map { row in
            ConnectionLogRow(id: row.id, time: row.time, category: row.category,
                             title: "[\(row.code)] \(row.message)", detail: json(row), isError: row.level == "error")
        }
        result += store.requestTraces.map { row in
            let failed = (row.httpStatus ?? 0) >= 400 || row.rpcErrorCode != nil || row.completed == false
            return ConnectionLogRow(id: row.id, time: row.time, category: "request",
                title: "\(row.rpcMethod ?? row.httpMethod) · HTTP \(row.httpStatus.map(String.init) ?? "未知") · \(reason(row))", detail: json(row), isError: failed)
        }
        return result.filter { row in
            (filter == "all" || (filter == "errors" ? row.isError : row.category == filter)) &&
            (search.isEmpty || (row.title + row.detail).localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if errorsFirst && a.isError != b.isError { return a.isError }
            return a.time > b.time
        }
    }
    private func reason(_ row: MCPRequestTrace) -> String {
        if row.completed == false { return "连接在响应完成前关闭" }
        if let code = row.rpcErrorCode { return "MCP 错误 \(code)，展开查看协议与接收格式" }
        if (row.httpStatus ?? 0) >= 400 {
            return ["host":"本机 Host 校验未通过", "origin":"Origin 校验未通过", "content-type":"请求内容类型不符", "path":"入口路径不匹配", "capacity":"并发请求达到上限", "body-size":"请求超过大小限制", "body":"请求解析失败", "sdk":"MCP 协议层拒绝请求"][row.stage] ?? "请求在 \(row.stage) 阶段未通过"
        }
        return row.rpcMethod == "tools/call" ? "请求已响应；不据此推定工具结果成功" : "请求已响应"
    }
    var body: some View {
        GroupBox("实时连接日志") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("实时更新 · \(store.requestTraces.count + store.connectionEvents.count) 条记录").font(.headline)
                    Spacer()
                    Button("复制连接诊断") { copy() }.disabled(store.requestTraces.isEmpty && store.connectionEvents.isEmpty)
                    Button("导出日志…") { export() }.disabled(store.requestTraces.isEmpty && store.connectionEvents.isEmpty)
                }
                HStack {
                    TextField("搜索状态码、阶段或协议版本", text: $search)
                    Picker("筛选", selection: $filter) {
                        Text("全部").tag("all"); Text("仅错误").tag("errors"); Text("MCP 请求").tag("request")
                        Text("隧道").tag("tunnel"); Text("工具发现").tag("discovery"); Text("MCP 服务").tag("server"); Text("网关").tag("gateway")
                    }.frame(width: 160)
                    Toggle("错误优先", isOn: $errorsFirst).toggleStyle(.checkbox)
                }
                if rows.isEmpty { Text("暂无符合筛选的记录。重新尝试连接后，展开记录查看各阶段。旧网关需重新启动才能记录新日志。").foregroundStyle(.secondary) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            DisclosureGroup {
                                Text(row.detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title).foregroundStyle(row.isError ? Color.orange : Color.primary)
                                    Text(row.time).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(4)
                }.frame(minHeight: 120, maxHeight: 360)
                if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(.secondary) }
                Text("显示最近 80 条请求与 200 条状态事件，仅存当前网关内存。复制和导出包含全部已保留记录，不受筛选影响。不记录参数、结果正文或原始请求头；官方进程原始输出不展示，仅显示安全分类。请求来源未验证，本机诊断标记也不能证明身份。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
    private var report: String {
        struct Report: Encodable { let schemaVersion = 1; let source = "OneMCP bounded metadata journal; request origin unverified"; let requests: [MCPRequestTrace]; let events: [ConnectionLogEvent] }
        return json(Report(requests: store.requestTraces, events: store.connectionEvents))
    }
    private func copy() {
        NSPasteboard.general.clearContents()
        feedback = NSPasteboard.general.setString(report, forType: .string) ? "已复制全部保留的连接日志" : "复制失败，请重试。"
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "OneMCP-connection-log.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(report.utf8).write(to: url, options: .atomic); feedback = "连接日志已导出。" }
        catch { feedback = "导出失败，请选择可写入的位置。" }
    }
}
