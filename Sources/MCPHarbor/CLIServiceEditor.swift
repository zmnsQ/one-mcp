import SwiftUI

/// Explicit schemas only: editing or previewing never executes the configured program.
struct CLIServiceEditor: View {
    @Binding var configuration: CLIServiceConfiguration
    @Binding var allowedTools: [String]
    var body: some View {
        GroupBox("CLI → MCP 工具") {
            VStack(alignment: .leading, spacing: 14) {
                Text("手动定义工具和参数，不运行 --help。固定命令前缀填写在上方“参数”中；工具参数按下方顺序追加。不会经 shell 解析，但程序仍拥有当前账户的权限，这不是沙箱。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("动态参数值不能以 - 开头；布尔选项为 true 时追加，false 时省略。子命令请放在固定命令前缀中。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("超时（毫秒）", value: $configuration.timeoutMs, format: .number)
                    TextField("输出上限（字节）", value: $configuration.maxOutputBytes, format: .number)
                    TextField("并发上限", value: $configuration.maxConcurrent, format: .number)
                }.textFieldStyle(.roundedBorder)
                ForEach(configuration.tools.indices, id: \.self) { index in
                    toolCard(index)
                }
                Button("添加 CLI 工具", systemImage: "plus") {
                    configuration.tools.append(CLIToolDefinition())
                }.disabled(configuration.tools.count >= 32)
                Text("工具默认不开放。核对命令、参数及影响后，逐个启用白名单；修改运行中配置需要停止服务。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
    private func toolCard(_ index: Int) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("工具名（字母开头，仅字母、数字、下划线）", text: $configuration.tools[index].name)
                        .onChange(of: configuration.tools[index].name) { old, _ in allowedTools.removeAll { $0 == old } }
                    Button("删除工具", role: .destructive) {
                        allowedTools.removeAll { $0 == configuration.tools[index].name }
                        configuration.tools.remove(at: index)
                    }
                }
                TextField("工具说明", text: $configuration.tools[index].description)
                Toggle("允许通过 MCP 调用此工具", isOn: Binding(get: {
                    allowedTools.contains(configuration.tools[index].name)
                }, set: { enabled in
                    let name = configuration.tools[index].name
                    allowedTools.removeAll { $0 == name }
                    if enabled { allowedTools.append(name) }
                })).disabled(configuration.tools[index].name.isEmpty)
                ForEach(configuration.tools[index].arguments.indices, id: \.self) { argumentIndex in
                    CLIArgumentEditor(argument: $configuration.tools[index].arguments[argumentIndex], remove: {
                        configuration.tools[index].arguments.remove(at: argumentIndex)
                    })
                }
                Button("添加参数") { configuration.tools[index].arguments.append(CLIArgument()) }
                    .disabled(configuration.tools[index].arguments.count >= 32)
            }.textFieldStyle(.roundedBorder).padding(6)
        }
    }
}
private struct CLIArgumentEditor: View {
    @Binding var argument: CLIArgument
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("参数名", text: $argument.name)
                Picker("类型", selection: $argument.type) {
                    Text("字符串").tag("string")
                    Text("数字").tag("number")
                    Text("布尔").tag("boolean")
                }.frame(width: 160)
                Toggle("必填", isOn: $argument.required)
                Button("删除", role: .destructive, action: remove)
            }
            TextField("选项名，如 --format；留空为位置参数", text: Binding(get: { argument.flag ?? "" }, set: { argument.flag = $0.isEmpty ? nil : $0 }))
            if argument.type == "string" {
                DisclosureGroup("限制为枚举值（可选，每行一个）") {
                    TextEditor(text: Binding(get: { argument.enumValues?.joined(separator: "\n") ?? "" }, set: {
                        let values = $0.components(separatedBy: "\n").filter { !$0.isEmpty }
                        argument.enumValues = values.isEmpty ? nil : values
                    })).font(.system(.caption, design: .monospaced)).frame(height: 60)
                }
            }
        }.padding(10).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: argument.type) { _, type in if type != "string" { argument.enumValues = nil } }
    }
}
