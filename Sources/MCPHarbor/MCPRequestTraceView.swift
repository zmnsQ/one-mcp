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
struct MCPRequestTracePanel: View {
    @EnvironmentObject var store: HarborStore
    @State private var copied = false
    var body: some View {
        GroupBox("连接请求诊断") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.requestTraces.isEmpty ? "尚未记录到请求" : "已记录 \(store.requestTraces.count) 条请求（来源未验证）").font(.headline)
                    Spacer()
                    Button(copied ? "已复制" : "复制连接诊断") { copy() }.disabled(store.requestTraces.isEmpty)
                }
                Text("在 ChatGPT 再试一次添加，然后复制诊断。这里只保留请求阶段、状态码与协议版本；不含参数、结果正文、密钥或原始请求头。本机诊断标记不是身份验证。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(store.requestTraces.suffix(6).reversed())) { row in
                    HStack {
                        Text(row.rpcMethod ?? row.httpMethod).font(.system(.caption, design: .monospaced))
                        Text("HTTP \(row.httpStatus ?? 0) · \(row.stage)").font(.caption)
                        if let code = row.rpcErrorCode { Text("RPC \(code)").font(.caption).foregroundStyle(.orange) }
                        Spacer()
                        Text(row.diagnosticMarkerMatched ? "带本机诊断标记" : "来源未验证").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("记录仅在新版网关启动后收集，最近 80 条仅存内存。HTTP 成功不等于 MCP 或工具调用成功。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
    private func copy() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store.requestTraces), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(text, forType: .string)
    }
}
