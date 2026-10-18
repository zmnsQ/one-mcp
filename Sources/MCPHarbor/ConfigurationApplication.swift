import Foundation
import CryptoKit

/// Version 1 wire fingerprints use UTF-8 byte lengths, not JSON serialization.
/// Values are never exposed by the runtime; environment values are deliberately excluded.
enum ConfigurationFingerprint {
    static func strings(_ values: [String]) -> String {
        var bytes = Data()
        for value in values {
            let valueBytes = Data(value.utf8)
            bytes.append(Data("\(valueBytes.count):".utf8)); bytes.append(valueBytes)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func scalar(_ value: String) -> String { strings([value]) }
    static func set(_ values: [String]) -> String {
        strings(Set(values.map { Data($0.utf8) }).sorted { $0.lexicographicallyPrecedes($1) }.map { String(decoding: $0, as: UTF8.self) })
    }
    static func server(_ server: ServerConfig) -> [String: String] {
        ["name": scalar(server.name), "executable": scalar(server.executable), "arguments": strings(server.arguments),
         "workingDirectory": scalar(server.workingDirectory), "environmentKeys": set(server.environmentKeys),
         "allowedTools": set(server.allowedTools)]
    }
    static func decode(_ event: [String: Any]) -> [String: String] {
        guard event["configurationFingerprintVersion"] as? Int == 1 else { return [:] }
        return event["configurationFingerprints"] as? [String: String] ?? [:]
    }
    static func changed(_ desired: [String: String], applied: [String: String], labels: [(String, String)]) -> [String] {
        // Older runtime versions have no fingerprints: absence is unknown, not evidence of a change.
        labels.compactMap { key, label in
            guard let live = applied[key], let saved = desired[key], live != saved else { return nil }
            return label
        }
    }
}

struct ConfigurationApplicationNotice: Identifiable {
    let id: String
    let title: String
    let detail: String
}

@MainActor extension HarborStore {
    func clearAppliedConfiguration() {
        appliedServerFingerprints = [:]; appliedTunnelFingerprints = [:]; appliedGatewayFingerprints = [:]
    }
    var runtimeComparisonUnavailable: Bool {
        isGatewayRunning && (appliedGatewayFingerprints.isEmpty ||
            sharedRuntimeServers.contains { $0.running && (appliedServerFingerprints[$0.id] ?? [:]).isEmpty })
    }
    func serverRestartReasons(_ id: String) -> [String] {
        guard isGatewayRunning, ["running", "starting"].contains(states[id] ?? ""),
              let saved = savedPreferences.servers.first(where: { $0.id == id }) else { return [] }
        var fingerprints = appliedServerFingerprints[id] ?? [:]
        // Older shared gateways still provide authoritative permissions.
        if fingerprints["allowedTools"] == nil, let live = sharedRuntimeServers.first(where: { $0.id == id }), live.permissionsKnown {
            fingerprints["allowedTools"] = ConfigurationFingerprint.set(live.allowedTools)
        }
        return ConfigurationFingerprint.changed(ConfigurationFingerprint.server(saved), applied: fingerprints,
            labels: [("name", "工具说明名称"), ("executable", "程序"), ("arguments", "参数"), ("workingDirectory", "工作目录"),
                     ("environmentKeys", "环境变量名称"), ("allowedTools", "工具白名单")])
    }
    func tunnelRestartReasons(_ key: String) -> [String] {
        guard isGatewayRunning, runningTunnelKeys.contains(key) else { return [] }
        if key == "transport:cloudflare" {
            guard let settings = savedPreferences.remoteConnection?.cloudflare else { return ["配置已移除"] }
            let desired = ["executable": ConfigurationFingerprint.scalar(settings.executable),
                "mode": ConfigurationFingerprint.scalar(settings.mode),
                "tunnelID": ConfigurationFingerprint.scalar(settings.mode == "named" ? settings.tunnelID : ""),
                "credentialsFile": ConfigurationFingerprint.scalar(settings.mode == "named" ? settings.credentialsFile : ""),
                "publicURL": ConfigurationFingerprint.scalar(settings.mode == "named" ? settings.publicURL : ""),
                "endpoint": ConfigurationFingerprint.scalar("http://127.0.0.1:\(savedPreferences.port)")]
            return ConfigurationFingerprint.changed(desired, applied: appliedTunnelFingerprints[key] ?? [:],
                labels: [("executable", "Cloudflare 程序"), ("mode", "连接模式"), ("tunnelID", "Tunnel UUID"),
                         ("credentialsFile", "凭据文件路径"), ("publicURL", "公开域名"), ("endpoint", "网关端口")])
        }
        let server = savedPreferences.servers.first(where: { $0.id == key })
        if key != "aggregate" && server == nil { return ["配置已移除"] }
        let profileFile = key == "aggregate" ? (savedPreferences.aggregateProfileFile ?? "") : ""
        let file = profileFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : profileFile
        let desired = ["executable": ConfigurationFingerprint.scalar(savedPreferences.tunnelClientPath),
            "profile": ConfigurationFingerprint.scalar(file.isEmpty ? (server?.profile ?? savedPreferences.aggregateProfile) : ""),
            "tunnelID": ConfigurationFingerprint.scalar(server?.tunnelID ?? savedPreferences.aggregateTunnelID),
            "profileFile": ConfigurationFingerprint.scalar(file),
            "endpoint": ConfigurationFingerprint.scalar("http://127.0.0.1:\(savedPreferences.port)" + (key == "aggregate" ? "/mcp" : "/servers/\(key)/mcp"))]
        return ConfigurationFingerprint.changed(desired, applied: appliedTunnelFingerprints[key] ?? [:],
            labels: [("executable", "隧道程序"), ("profile", "Profile"), ("tunnelID", "Tunnel ID"),
                     ("profileFile", "Profile 文件"), ("endpoint", "网关端口")])
    }
    var gatewayRestartReasons: [String] {
        guard isGatewayRunning else { return [] }
        func path(_ value: String) -> String { URL(fileURLWithPath: value).resolvingSymlinksInPath().standardizedFileURL.path }
        var desired = ["nodePath": ConfigurationFingerprint.scalar(path(savedPreferences.nodePath)),
                       "gatewayScript": ConfigurationFingerprint.scalar(path(savedPreferences.gatewayScript))]
        let oauth = savedPreferences.remoteConnection?.oauth
        desired["oauthEnabled"] = ConfigurationFingerprint.scalar(oauth?.enabled == true ? "true" : "false")
        desired["oauthPublicURL"] = ConfigurationFingerprint.scalar(oauth?.publicURL ?? "")
        desired["oauthIssuer"] = ConfigurationFingerprint.scalar(oauth?.issuer ?? "")
        desired["oauthJWKSURL"] = ConfigurationFingerprint.scalar(oauth?.jwksURL ?? "")
        desired["oauthScope"] = ConfigurationFingerprint.scalar(oauth?.scope ?? "mcp:tools")
        var reasons = ConfigurationFingerprint.changed(desired, applied: appliedGatewayFingerprints,
            labels: [("nodePath", "Node 路径"), ("gatewayScript", "网关脚本"), ("oauthEnabled", "OAuth 开关"),
                     ("oauthPublicURL", "OAuth 公开地址"), ("oauthIssuer", "OAuth issuer"), ("oauthJWKSURL", "OAuth JWKS"), ("oauthScope", "OAuth scope")])
        if let port = attachedPort, port != savedPreferences.port { reasons.append("监听端口") }
        return reasons
    }
    var configurationApplicationNotices: [ConfigurationApplicationNotice] {
        guard isGatewayRunning else { return [] }
        var result: [ConfigurationApplicationNotice] = []
        if !gatewayRestartReasons.isEmpty {
            result.append(.init(id: "gateway", title: "网关 · 待重启生效", detail: gatewayRestartReasons.joined(separator: "、")))
        }
        for server in savedPreferences.servers {
            let reasons = serverRestartReasons(server.id)
            if !reasons.isEmpty {
                result.append(.init(id: "server:" + server.id, title: server.name + " · 待重启生效", detail: reasons.joined(separator: "、")))
            }
        }
        for server in sharedRuntimeServers where server.running && !savedPreferences.servers.contains(where: { $0.id == server.id }) {
            result.append(.init(id: "removed:" + server.id, title: server.name + " · 已从配置移除", detail: "当前进程仍在运行，可在设置中明确停止此服务。"))
        }
        for key in runningTunnelKeys.sorted() {
            let reasons = tunnelRestartReasons(key)
            if !reasons.isEmpty {
                let name = key == "transport:cloudflare" ? "Cloudflare 连接" : key == "aggregate" ? "聚合隧道" : (savedPreferences.servers.first(where: { $0.id == key })?.name ?? key) + " 隧道"
                result.append(.init(id: "tunnel:" + key, title: name + " · 待重启生效", detail: reasons.joined(separator: "、")))
            }
        }
        return result
    }
}

