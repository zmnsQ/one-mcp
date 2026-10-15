import SwiftUI

struct ImportPreview: View {
    @EnvironmentObject private var store: HarborStore
    private var eligible: [ImportCandidate] { store.importCandidates.filter(\.canSelect) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发现候选 · 选择后合并").font(.title2.bold())
            Text("仅来自你刚才选择的文件，不扫描其他位置。保留现有服务器；新增白名单为空，env 值不会导入。请检查命令是否可信以及参数中的私人信息。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("选择全部可导入项") { store.selectedImportIDs = Set(eligible.map(\.id)) }
                Button("清除选择") { store.selectedImportIDs = [] }
                Spacer()
                Text("已选 \(store.selectedImportIDs.count) / 可导入 \(eligible.count)").font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(store.importCandidates) { candidate in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(candidate.name, isOn: Binding(get: { store.selectedImportIDs.contains(candidate.id) }, set: { selected in
                                    if selected { store.selectedImportIDs.insert(candidate.id) } else { store.selectedImportIDs.remove(candidate.id) }
                                })).disabled(!candidate.canSelect)
                                Text("来源：\(candidate.source)").font(.caption).textSelection(.enabled)
                                if let server = candidate.server {
                                    Text("命令：\(server.executable)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    Text("参数（每行一个）：\n\(server.arguments.isEmpty ? "（无）" : server.arguments.joined(separator: "\n"))").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    Text("工作目录：\(server.workingDirectory.isEmpty ? "（未指定）" : server.workingDirectory)").font(.caption)
                                    Text("env 变量名：\(server.environmentKeys.isEmpty ? "（无）" : server.environmentKeys.joined(separator: ", "))").font(.caption)
                                }
                                if let issue = candidate.issue { Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                                if let warning = candidate.warning { Text(warning).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                }
            }
            HStack {
                Button("取消") { store.cancelImportPreview() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("合并所选 \(store.selectedImportIDs.count) 项") { store.mergeSelectedCandidates() }
                    .buttonStyle(.glassProminent).disabled(store.selectedImportIDs.isEmpty || store.anyProcessRunning)
            }
        }.padding(24).frame(width: 760, height: 620)
        .alert("无法导入", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
