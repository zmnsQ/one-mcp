import Foundation

/// UI validation is deliberately side-effect free. The shared gateway validates again.
enum RemoteConnectionValidation {
    static func trustedHTTPS(_ value: String) -> URL? {
        guard !value.isEmpty, value.utf8.count <= 2048,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !value.contains("\\"), !value.contains("\""), let components = URLComponents(string: value),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil else { return nil }
        return components.url
    }
    static func publicHTTPS(_ value: String, originOnly: Bool = false) -> URL? {
        guard trustedHTTPS(value) != nil,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("\\"), let components = URLComponents(string: value),
              components.scheme == "https", let host = components.host?.lowercased(),
              host.contains("."), !host.hasSuffix("."),
              !host.hasSuffix(".localhost"), !host.hasSuffix(".local"), !host.hasSuffix(".internal"), !host.hasSuffix(".test"), !host.hasSuffix(".invalid"),
              host != "localhost", !host.contains(":"),
              host.range(of: "^[0-9.]+$", options: .regularExpression) == nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port == nil,
              !originOnly || components.path.isEmpty || components.path == "/" else { return nil }
        guard host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
            $0.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", options: .regularExpression) != nil
        }) else { return nil }
        if originOnly, value != "https://" + host, value != "https://" + host + "/" { return nil }
        return components.url
    }
    static func issue(_ settings: RemoteConnectionSettings?) -> String? {
        guard let settings else { return nil }
        if let transport = settings.preferredTransport, !["openai", "cloudflare"].contains(transport) {
            return "连接方式须为 OpenAI 或 Cloudflare。"
        }
        if let oauth = settings.oauth {
            for (title, value) in [("MCP 公开地址", oauth.publicURL), ("issuer", oauth.issuer), ("JWKS 地址", oauth.jwksURL)] {
                if (oauth.enabled || !value.isEmpty), trustedHTTPS(value) == nil {
                    return "OAuth \(title) 须为不含凭据、查询参数的公网 HTTPS URL。"
                }
            }
            if oauth.enabled || !oauth.scope.isEmpty {
                let scopes = oauth.scope.components(separatedBy: " ")
                guard oauth.scope.utf8.count <= 512, scopes.count <= 16,
                      scopes.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { scalar in
                          scalar.value >= 0x21 && scalar.value <= 0x7E && scalar.value != 0x22 && scalar.value != 0x5C
                      } }) else {
                    return "请填写有效的 OAuth scope，多个 scope 用单个空格分隔。"
                }
            }
        }
        if let cloudflare = settings.cloudflare {
            guard ["quick", "named"].contains(cloudflare.mode) else { return "Cloudflare 模式须为 quick 或 named。" }
            if !cloudflare.publicURL.isEmpty, publicHTTPS(cloudflare.publicURL, originOnly: true) == nil {
                return "Cloudflare 公开地址须为 HTTPS 域名，不含路径、凭据或查询参数。"
            }
            for path in [cloudflare.executable, cloudflare.credentialsFile] where !path.isEmpty {
                guard path.hasPrefix("/"), path.utf8.count <= 4096, !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    return "Cloudflare 程序和凭据文件须使用本机绝对路径。"
                }
            }
        }
        return nil
    }
}

@MainActor extension HarborStore {
    @discardableResult func cloudflareAction(_ action: String, persistConfiguration: Bool = true) -> Bool {
        guard gatewayReady, !tunnelRunning("transport:cloudflare"), !hasPendingCommand(for: "transport:cloudflare"),
              ["doctor", "run"].contains(action), let settings = preferences.remoteConnection?.cloudflare else {
            errorMessage = "请先配置 Cloudflare、启动网关并等待当前操作完成。"; return false
        }
        if let issue = RemoteConnectionValidation.issue(preferences.remoteConnection) { errorMessage = issue; return false }
        guard settings.executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: settings.executable) else {
            errorMessage = "请选择已安装的 cloudflared 可执行文件。"; return false
        }
        guard !persistConfiguration || save() else { return false }
        if action == "run" {
            guard preferences.remoteConnection?.oauth?.enabled == true else { errorMessage = "公网连接前请先配置并启用 OAuth 保护。"; return false }
            guard appliedGatewayFingerprints["oauthEnabled"] == ConfigurationFingerprint.scalar("true") else {
                errorMessage = "尚未确认运行中的网关已启用 OAuth。请保存配置并明确重启支持 OAuth 的网关。"; return false
            }
            guard !gatewayRestartReasons.contains(where: { $0.hasPrefix("OAuth") }) else {
                errorMessage = "OAuth 配置已改变，请先保存并明确重启网关后再连接 Cloudflare。"; return false
            }
        }
        return command("cloudflareAction", params: ["action":action, "key":"transport:cloudflare", "executable":settings.executable,
            "mode":settings.mode, "tunnelID":settings.mode == "named" ? settings.tunnelID : "",
            "credentialsFile":settings.mode == "named" ? settings.credentialsFile : "",
            "publicURL":settings.mode == "named" ? settings.publicURL : ""])
    }
}
