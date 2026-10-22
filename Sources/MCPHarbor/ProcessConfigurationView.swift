import SwiftUI

struct ProcessConfigurationView: View {
    @Binding var server: ServerConfig
    let locked: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("进程配置", systemImage: "terminal").font(.title3.bold())
            Text(locked ? "服务运行中，进程配置已锁定。工具开放范围可在上方单独保存并应用。" : "设置本机执行的程序。保存不会自动启动；更改进程配置需要重新启动服务。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                field("服务名称", hint: "便于辨认的名称") { TextField("例如：文件工具", text: $server.name) }
                field("可执行文件", hint: "填写本机程序的绝对路径") {
                    TextField("例如：/opt/homebrew/bin/node", text: $server.executable).font(.system(.body, design: .monospaced))
                }
                field("服务类型", hint: "切换类型将清空工具定义和白名单，并取消参与全部启动") {
                    Picker("服务类型", selection: Binding(get: { server.kind ?? "mcp" }, set: { kind in
                        guard kind != (server.kind ?? "mcp") else { return }
                        server.kind = kind
                        server.cli = kind == "cli" ? CLIServiceConfiguration() : nil
                        server.allowedTools = []
                        server.startWithAll = false
                    })) { Text("MCP 程序").tag("mcp"); Text("CLI 转 MCP").tag("cli") }.labelsHidden()
                }
                DisclosureGroup("启动参数（\(server.arguments.count) 项）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每行一个参数，无需 shell 转义。例如脚本路径或 --flag。").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: lines($server.arguments)).font(.system(.body, design: .monospaced)).frame(minHeight: 88).padding(6)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }.padding(.top, 8)
                }
                DisclosureGroup("高级：工作目录与环境变量") {
                    VStack(alignment: .leading, spacing: 14) {
                        field("工作目录", hint: "可选，留空使用默认目录") { TextField("绝对路径", text: $server.workingDirectory) }
                        field("环境变量名称", hint: "每行一个名称；具体值在下方填写，仅保存在内存中") {
                            TextEditor(text: lines($server.environmentKeys)).font(.system(.body, design: .monospaced)).frame(minHeight: 70)
                        }
                    }.padding(.top, 10)
                }
            }.disabled(locked).textFieldStyle(.roundedBorder)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
    private func field<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content().frame(maxWidth: .infinity, alignment: .leading)
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func lines(_ binding: Binding<[String]>) -> Binding<String> {
        Binding(get: { binding.wrappedValue.joined(separator: "\n") }, set: { binding.wrappedValue = $0.components(separatedBy: "\n").filter { !$0.isEmpty } })
    }
}
