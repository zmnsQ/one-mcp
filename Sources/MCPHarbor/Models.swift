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
