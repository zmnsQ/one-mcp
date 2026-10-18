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
