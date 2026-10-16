import SwiftUI
import AppKit

struct AIManagementAccessView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var showing = false
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("让 AI 管理 One MCP").font(.headline)
                Text("复制专用提示词，交给有本机执行权限的 AI 助手。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("查看使用说明") { showing = true }
        }.padding(.vertical, 6)
            .sheet(isPresented: $showing) { AIManagementSheet().environmentObject(store) }
    }
}

private struct AIManagementSheet: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var copyError: String?
    private var prompt: String? { try? store.aiManagementPrompt() }
    private var promptError: String {
        do { _ = try store.aiManagementPrompt(); return "请重新打开使用说明。" }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("让 AI 管理 One MCP").font(.title2.bold())
            Text("把下方提示词发给可以操作这台 Mac 的 AI Agent。它会先检查状态，再由你批准具体改动。复制不会安装 Skill，也不会自动连接或运行任何服务。")
                .font(.callout).foregroundStyle(.secondary)
            if let prompt {
                ScrollView {
                    Text(prompt).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                if let copyError { Text(copyError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Text(copied ? "已复制，可以粘贴给你的 AI 助手。" : "仅包含运行路径和操作说明，不包含凭据。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("关闭") { dismiss() }
                    Button(copied ? "再次复制提示词" : "复制提示词") {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(prompt, forType: .string)
                        copyError = copied ? nil : "复制失败，请选择上方文本手动复制。"
                    }.buttonStyle(.glassProminent)
                }
                .onChange(of: prompt) { _, _ in copied = false; copyError = nil }
            } else {
                Label("运行组件尚未就绪", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                Text(store.runtimeFilesReady ? promptError : store.runtimeSetupSummary).font(.callout)
                Text("请返回设置，点击“自动检查并修复”。组件就绪后再生成提示词。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack { Spacer(); Button("关闭") { dismiss() } }
            }
        }.padding(24).frame(width: 720, height: 580)
    }
}
