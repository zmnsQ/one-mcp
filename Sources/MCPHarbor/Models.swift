import Foundation

struct ServerConfig: Codable, Identifiable, Hashable {
    var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    var name = "New MCP"
    var executable = ""
    var arguments: [String] = []
    var workingDirectory = ""
    var environmentKeys: [String] = []
    var allowedTools: [String] = []
    var tunnelID = ""
    var profile = ""
    var kind: String?
    var cli: CLIServiceConfiguration?
    var isCLI: Bool { kind == "cli" }
    var startWithAll: Bool?
    var participatesInStartAll: Bool { startWithAll != false }
}
struct Preferences: Codable, Equatable {
    var nodePath = "/opt/homebrew/bin/node"
    var gatewayScript = ""
    var tunnelClientPath = ""
    var port = 8787
    var aggregateTunnelID = ""
    var aggregateProfile = "mcpharbor-aggregate"
    var aggregateProfileFile: String?
    var mode = "aggregate"
    var remoteConnection: RemoteConnectionSettings?
    var servers: [ServerConfig] = []
    var tunnelRecords: [TunnelRecord]? = []
    var effectiveTunnelRecords: [TunnelRecord] { tunnelRecords ?? migratedTunnelRecords }
    private var migratedTunnelRecords: [TunnelRecord] {
        if remoteConnection?.preferredTransport == "cloudflare", let settings = remoteConnection?.cloudflare {
            return [TunnelRecord(id: "cloudflare-default", name: "Cloudflare", serverIDs: servers.map(\.id), transport: "cloudflare", cloudflare: settings)]
        }
        if mode == "individual" {
            return servers.map { TunnelRecord(id: $0.id, name: String($0.name.prefix(96)) + " 隧道", serverIDs: [$0.id], profile: $0.profile, tunnelID: $0.tunnelID, startWithAll: $0.startWithAll) }
        }
        guard !servers.isEmpty || !aggregateTunnelID.isEmpty || aggregateProfileFile != nil else { return [] }
        return [TunnelRecord(id: "aggregate", name: "聚合隧道", serverIDs: servers.map(\.id), profile: aggregateProfile, tunnelID: aggregateTunnelID, profileFile: aggregateProfileFile)]
    }
    enum CodingKeys: String, CodingKey {
        case nodePath, gatewayScript, tunnelClientPath, port, aggregateTunnelID, aggregateProfile, aggregateProfileFile, mode, remoteConnection, servers, tunnelRecords
    }
    init() {}
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        nodePath = try v.decodeIfPresent(String.self, forKey: .nodePath) ?? "/opt/homebrew/bin/node"
        gatewayScript = try v.decodeIfPresent(String.self, forKey: .gatewayScript) ?? ""
        tunnelClientPath = try v.decodeIfPresent(String.self, forKey: .tunnelClientPath) ?? ""
        port = try v.decodeIfPresent(Int.self, forKey: .port) ?? 8787
        aggregateTunnelID = try v.decodeIfPresent(String.self, forKey: .aggregateTunnelID) ?? ""
        aggregateProfile = try v.decodeIfPresent(String.self, forKey: .aggregateProfile) ?? "mcpharbor-aggregate"
        aggregateProfileFile = try v.decodeIfPresent(String.self, forKey: .aggregateProfileFile)
        mode = try v.decodeIfPresent(String.self, forKey: .mode) ?? "aggregate"
        remoteConnection = try v.decodeIfPresent(RemoteConnectionSettings.self, forKey: .remoteConnection)
        servers = try v.decodeIfPresent([ServerConfig].self, forKey: .servers) ?? []
        if v.contains(.tunnelRecords), try v.decodeNil(forKey: .tunnelRecords) {
            throw DecodingError.dataCorruptedError(forKey: .tunnelRecords, in: v, debugDescription: "tunnelRecords must be an array")
        }
        tunnelRecords = try v.decodeIfPresent([TunnelRecord].self, forKey: .tunnelRecords)
        if tunnelRecords == nil { tunnelRecords = migratedTunnelRecords }
    }
}

/// Each binding is an explicit snapshot. Adding a service never expands an existing tunnel.
struct TunnelRecord: Codable, Identifiable, Equatable {
    var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    var name = "新隧道"
    var serverIDs: [String] = []
    var transport = "openai"
    var profile = ""
    var tunnelID = ""
    var profileFile: String?
    var cloudflare: CloudflareSettings?
    var startWithAll: Bool?
    var participatesInStartAll: Bool { startWithAll != false }
}
struct ToolInfo: Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let publicName: String
    let metadataJSON: String
}
struct LogLine: Identifiable {
    let id = UUID()
    let time = Date()
    let source: String
    let text: String
}


/// Non-secret setup only. API keys, OAuth tokens and Cloudflare credential contents
/// must never be persisted in these preferences or included in configuration exports.
struct RemoteConnectionSettings: Codable, Equatable {
    var preferredTransport: String?
    var oauth: OAuthSettings?
    var cloudflare: CloudflareSettings?
}
struct OAuthSettings: Codable, Equatable {
    var enabled = false
    var publicURL = ""
    var issuer = ""
    var jwksURL = ""
    var scope = "mcp:tools"
    enum CodingKeys: String, CodingKey { case enabled, publicURL, issuer, jwksURL, scope }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        publicURL = try values.decodeIfPresent(String.self, forKey: .publicURL) ?? ""
        issuer = try values.decodeIfPresent(String.self, forKey: .issuer) ?? ""
        jwksURL = try values.decodeIfPresent(String.self, forKey: .jwksURL) ?? ""
        scope = try values.decodeIfPresent(String.self, forKey: .scope) ?? "mcp:tools"
    }
}
struct CloudflareSettings: Codable, Equatable {
    var executable = ""
    var mode = "named"
    var tunnelID = ""
    var credentialsFile = ""
    var publicURL = ""
    enum CodingKeys: String, CodingKey { case executable, mode, tunnelID, credentialsFile, publicURL }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        executable = try values.decodeIfPresent(String.self, forKey: .executable) ?? ""
        mode = try values.decodeIfPresent(String.self, forKey: .mode) ?? "named"
        tunnelID = try values.decodeIfPresent(String.self, forKey: .tunnelID) ?? ""
        credentialsFile = try values.decodeIfPresent(String.self, forKey: .credentialsFile) ?? ""
        publicURL = try values.decodeIfPresent(String.self, forKey: .publicURL) ?? ""
    }
}

struct CLIServiceConfiguration: Codable, Hashable {
    var tools: [CLIToolDefinition] = []
    var timeoutMs = 30000
    var maxOutputBytes = 65536
    var maxConcurrent = 1
    var fingerprintValues: [String] {
        var values = [String(timeoutMs), String(maxOutputBytes), String(maxConcurrent), String(tools.count)]
        for tool in tools {
            values += [tool.name, tool.description, String(tool.arguments.count)]
            for arg in tool.arguments {
                values += [arg.name, arg.type, arg.flag ?? "", arg.required ? "true" : "false", String(arg.enumValues?.count ?? 0)]
                values += arg.enumValues ?? []
            }
        }
        return values
    }
}
struct CLIToolDefinition: Codable, Hashable {
    var name = ""
    var description = ""
    var arguments: [CLIArgument] = []
}
struct CLIArgument: Codable, Hashable {
    var name = ""
    var type = "string"
    var flag: String?
    var required = false
    var enumValues: [String]?
}
enum CLIConfigurationValidation {
    static func issue(_ server: ServerConfig, requireTools: Bool = false) -> String? {
        guard ["mcp", "cli"].contains(server.kind ?? "mcp") else { return "服务类型必须为 MCP 或 CLI。" }
        guard server.isCLI else { return server.cli == nil ? nil : "MCP 服务不能带有 CLI 配置。" }
        guard !server.environmentKeys.contains(where: { $0.hasPrefix("ONEMCP_") }) else { return "CLI 环境变量不能使用 ONEMCP_ 保留前缀。" }
        guard let cli = server.cli else { return "CLI 服务缺少工具配置。" }
        guard (100...120000).contains(cli.timeoutMs), (1024...1048576).contains(cli.maxOutputBytes), (1...4).contains(cli.maxConcurrent) else { return "CLI 限制：超时 100–120000 毫秒、输出 1024–1048576 字节、并发 1–4。" }
        func nameOK(_ value: String) -> Bool { value.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil && !["constructor", "prototype", "__proto__"].contains(value) }
        guard (!requireTools || !cli.tools.isEmpty), cli.tools.count <= 32, Set(cli.tools.map(\.name)).count == cli.tools.count else { return "CLI 工具须为1–32个，名称不可重复。" }
        for tool in cli.tools {
            guard nameOK(tool.name), tool.description.utf16.count <= 1000, !tool.description.contains("\0"), tool.arguments.count <= 32, Set(tool.arguments.map(\.name)).count == tool.arguments.count else { return "CLI 工具名称、描述或参数列表无效。" }
            let flags = tool.arguments.compactMap(\.flag)
            guard Set(flags).count == flags.count else { return "CLI 选项名不可重复。" }
            for arg in tool.arguments {
                guard nameOK(arg.name), ["string", "number", "boolean"].contains(arg.type) else { return "CLI 参数名称或类型无效。" }
                if let flag = arg.flag, flag.range(of: "^--[A-Za-z][A-Za-z0-9-]{0,63}$", options: .regularExpression) == nil { return "CLI 选项须为 --option；位置参数请留空。" }
                if arg.type == "boolean", arg.flag == nil { return "布尔参数必须设置选项名。" }
                if let values = arg.enumValues {
                    guard arg.type == "string", !values.isEmpty, values.count <= 100, Set(values).count == values.count, values.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && $0.utf16.count <= 8192 && !$0.contains("\0") }) else { return "枚举仅支持字符串参数，请填入不重复的非空值。" }
                }
            }
        }
        guard Set(server.allowedTools).isSubset(of: Set(cli.tools.map(\.name))) else { return "CLI 白名单含未定义的工具。" }
        return nil
    }
}
