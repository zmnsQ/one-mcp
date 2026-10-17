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
