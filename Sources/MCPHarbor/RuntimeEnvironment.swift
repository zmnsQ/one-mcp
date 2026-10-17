import Foundation

/// Resolves app-owned resources without executing a program or changing custom installations.
enum RuntimeEnvironment {
    static func readableFile(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue && FileManager.default.isReadableFile(atPath: path)
    }
    static func missingFiles(for script: String, readable: (String) -> Bool = { RuntimeEnvironment.readableFile($0) }) -> [String] {
        guard script.hasPrefix("/") else { return ["gateway/dist/index.js"] }
        let dist = URL(fileURLWithPath: script).deletingLastPathComponent()
        let root = dist.deletingLastPathComponent()
        let files = [dist.appendingPathComponent("runtime-start-command.js").path, dist.appendingPathComponent("takeover-command.js").path, dist.appendingPathComponent("runtime-bridge.js").path, script, dist.appendingPathComponent("cli.js").path,
                     root.appendingPathComponent("package.json").path,
                     root.appendingPathComponent("node_modules/@modelcontextprotocol/sdk/package.json").path,
                     root.appendingPathComponent("node_modules/zod/package.json").path]
        return files.filter { !readable($0) }
    }
    static func isAppOwned(_ script: String) -> Bool {
        ["/One MCP.app/Contents/Resources/gateway/dist/index.js", "/MCPHarbor.app/Contents/Resources/gateway/dist/index.js"].contains { script.hasSuffix($0) }
    }
    static func resolveGateway(saved: String, resourceURL: URL?, readable: (String) -> Bool = { RuntimeEnvironment.readableFile($0) }) -> String {
        // A valid explicit external installation remains authoritative. Old app paths track this build.
        guard saved.isEmpty || isAppOwned(saved), let resourceURL else { return saved }
        let bundled = resourceURL.appendingPathComponent("gateway/dist/index.js").path
        return missingFiles(for: bundled, readable: readable).isEmpty ? bundled : saved
    }
}

@MainActor extension HarborStore {
    var runtimeFilesReady: Bool {
        FileManager.default.isExecutableFile(atPath: preferences.nodePath) &&
        RuntimeEnvironment.missingFiles(for: preferences.gatewayScript).isEmpty &&
        (1024...65535).contains(preferences.port)
    }
    var runtimeSetupSummary: String {
        if !RuntimeEnvironment.missingFiles(for: preferences.gatewayScript).isEmpty {
            return "应用运行组件缺失。点击自动检查并修复；若仍未恢复，请重新构建完整应用。"
        }
        if !FileManager.default.isExecutableFile(atPath: preferences.nodePath) { return "未找到已安装的 Node.js。自动检查会查找常见安装位置。" }
        if !(1024...65535).contains(preferences.port) { return "本机端口设置无效，请在高级设置中选择 1024–65535。" }
        return "本机运行组件已就绪，可以启动。连接 ChatGPT 仍需配置官方隧道。"
    }
    @discardableResult func resolveRuntimePaths() -> Bool {
        guard !anyProcessRunning else { return false }
        let before = preferences
        preferences.gatewayScript = RuntimeEnvironment.resolveGateway(saved: preferences.gatewayScript, resourceURL: Bundle.main.resourceURL)
        if !FileManager.default.isExecutableFile(atPath: preferences.nodePath),
           let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            preferences.nodePath = node
        }
        return before != preferences
    }
    func repairEnvironment() {
        guard !anyProcessRunning, !discoveryBusy else { return }
        let changed = resolveRuntimePaths()
        checkSetup()
        if changed {
            guard save() else { return }
            notice = "已修复运行组件位置。没有安装软件或启动服务。"
        }
        guard runtimeFilesReady else { discoveryError = runtimeSetupSummary; return }
        detectEnvironment()
    }
}
