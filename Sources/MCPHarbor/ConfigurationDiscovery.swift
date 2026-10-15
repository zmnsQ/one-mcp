import Foundation

struct ImportCandidate: Identifiable {
    let id = UUID().uuidString
    let source: String
    let name: String
    let server: ServerConfig?
    let issue: String?
    let warning: String?
    var canSelect: Bool { server != nil && issue == nil }
}

/// Pure parsing of bytes from explicitly selected files. No filesystem search, execution, or credential lookup.
enum ConfigurationDiscovery {
    static func fingerprint(_ server: ServerConfig) -> String {
        let fields: [Any] = [server.executable, server.arguments, server.workingDirectory, server.environmentKeys.sorted()]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }
    static func candidates(data: Data, source: String, seen: inout Set<String>) throws -> [ImportCandidate] {
        guard data.count <= 1_048_576 else { throw invalid("文件超过 1 MiB。") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = (root["mcpServers"] ?? root["servers"]) as? [String: Any] else {
            throw invalid("未找到 mcpServers（或 VS Code servers）对象；只支持严格 JSON，不执行 JSON 中的命令。")
        }
        guard entries.count <= 256 else { throw invalid("候选数量超过256。") }
        return entries.keys.sorted().map { name in
            func rejected(_ reason: String) -> ImportCandidate { .init(source: source, name: name, server: nil, issue: reason, warning: nil) }
            guard let entry = entries[name] as? [String: Any] else { return rejected("服务器条目必须是对象。") }
            if let kind = entry["type"] as? String, kind != "stdio" { return rejected("远程或未知传输类型 \(kind) 不支持导入。") }
            guard entry["url"] == nil, let command = entry["command"] as? String, !command.isEmpty else { return rejected("仅导入带 command 的本机 stdio；远程 URL 不会转换为本机程序。") }
            guard !command.contains("\0"), command.utf8.count <= 8192 else { return rejected("命令路径无效或过长。") }
            guard entry["args"] == nil || entry["args"] is [String] else { return rejected("args 必须为字符串数组。") }
            guard entry["env"] == nil || entry["env"] is [String: Any] else { return rejected("env 必须为对象。") }
            guard entry["cwd"] == nil || entry["cwd"] is String else { return rejected("cwd 必须为字符串。") }
            let args = entry["args"] as? [String] ?? []
            let envKeys = (entry["env"] as? [String: Any] ?? [:]).keys.sorted()
            guard args.count <= 128, args.allSatisfy({ !$0.contains("\0") && $0.utf8.count < 8192 }),
                  envKeys.allSatisfy({ $0 != "__tunnel_key" && $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil }),
                  !name.isEmpty, name.count <= 100 else { return rejected("名称、参数或环境变量名不符合限制。") }
            var server = ServerConfig()
            server.name = name; server.executable = redactText(command); server.workingDirectory = redactText(entry["cwd"] as? String ?? "")
            server.environmentKeys = envKeys
            server.arguments = redactCredentialArguments(args)
            guard !server.workingDirectory.contains("\0") else { return rejected("工作目录包含无效字符。") }
            var warnings: [String] = []
            if !command.hasPrefix("/") { warnings.append("相对命令需在启动前改为本机可执行文件绝对路径。") }
            if !envKeys.isEmpty { warnings.append("只保留环境变量名；原文件中的值不会导入或自动载入 Keychain。") }
            let sensitive = args != server.arguments || command != server.executable || (entry["cwd"] as? String ?? "") != server.workingDirectory
            if sensitive { warnings.append("疑似凭据已在预览中隐藏。请在源文件中改用环境变量后重新选择文件；不会导入被改写的命令。") }
            let signature = fingerprint(server)
            let duplicate = sensitive ? false : !seen.insert(signature).inserted
            return .init(source: source, name: name, server: server,
                         issue: sensitive ? "命令/参数/路径疑似包含凭据：禁止导入，需手动修正源文件。" : (duplicate ? "与当前工作空间或前面文件的非秘密配置重复；env 值不参与比较。若需不同凭据，请手动添加独立服务器。" : nil),
                         warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
        }
    }
    static func redactCredentialArguments(_ args: [String]) -> [String] {
        var hideNext = false
        let flags = "(?:api[-_]?key|token|access[-_]?token|secret|password|credential|authorization)"
        return args.map { arg in
            if hideNext { hideNext = false; return "[REENTER_VIA_ENV]" }
            if arg.range(of: "(?i)^--?" + flags + "$", options: .regularExpression) != nil { hideNext = true; return arg }
            if let regex = try? NSRegularExpression(pattern: "(?i)(--?" + flags + "=).*"), regex.firstMatch(in: arg, range: NSRange(arg.startIndex..., in: arg)) != nil {
                return regex.stringByReplacingMatches(in: arg, range: NSRange(arg.startIndex..., in: arg), withTemplate: "$1[REENTER_VIA_ENV]")
            }
            return redactText(arg)
        }
    }
    static func redactText(_ value: String) -> String {
        var result = value
        let patterns = [
            "(?i)bearer\\s+[^\\s]+",
            "(?i)([a-z][a-z0-9+.-]*://)[^/\\s@]+@",
            "(?i)((?:[?&]|^)(?:api[-_]?key|token|access[-_]?token|secret|password|credential|authorization)=)[^&\\s]+"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[REDACTED_CREDENTIAL]")
        }
        return result
    }
    private static func invalid(_ text: String) -> Error {
        NSError(domain: "OneMCP.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
