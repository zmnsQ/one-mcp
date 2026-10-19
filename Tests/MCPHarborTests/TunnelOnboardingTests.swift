import Foundation
import XCTest
@testable import MCPHarbor

final class TunnelOnboardingTests: XCTestCase {
    func testExistingPreferencesRemainCompatibleAndRemoteDefaultsAreOff() throws {
        let encoded = try JSONEncoder().encode(Preferences())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["remoteConnection"])
        XCTAssertNil(try JSONDecoder().decode(Preferences.self, from: encoded).remoteConnection)
        XCTAssertFalse(OAuthSettings().enabled)
        XCTAssertEqual(CloudflareSettings().mode, "named")
        let empty = try JSONDecoder().decode(RemoteConnectionSettings.self, from: Data("{}".utf8))
        XCTAssertNil(empty.preferredTransport)
        XCTAssertNil(empty.oauth)
        XCTAssertNil(empty.cloudflare)
    }
    func testRemoteSettingsRoundTripWithoutSecretFields() throws {
        var oauth = OAuthSettings(); oauth.enabled = true
        oauth.publicURL = "https://mcp.example.com/mcp"
        oauth.issuer = "https://identity.example.com/"
        oauth.jwksURL = "https://identity.example.com/keys"
        oauth.scope = "mcp:read mcp:tools"
        var cloudflare = CloudflareSettings(); cloudflare.executable = "/usr/local/bin/cloudflared"
        cloudflare.publicURL = "https://mcp.example.com"
        cloudflare.credentialsFile = "/private/tunnel-credentials.json"
        var config = Preferences()
        config.remoteConnection = RemoteConnectionSettings(preferredTransport: "cloudflare", oauth: oauth, cloudflare: cloudflare)
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), config)
        XCTAssertNil(RemoteConnectionValidation.issue(config.remoteConnection))
        let json = String(decoding: data, as: UTF8.self)
        for secret in ["runtimeKey", "clientSecret", "accessToken", "refreshToken", "privateKey", "tunnelToken"] {
            XCTAssertFalse(json.contains("\"" + secret + "\""))
        }
    }
    func testPresenceHintsDoNotClaimVerifiedAuthentication() {
        XCTAssertTrue(TunnelSetupHints.credential("dummy-fixture").contains("尚待检查"))
        XCTAssertTrue(TunnelSetupHints.tunnel("tunnel_fixture").contains("尚待核对"))
        XCTAssertTrue(TunnelSetupHints.credential(" \n").contains("可留空"))
    }
    func testOfficialHelpDestinationsHaveNoSecretsOrRedirectParameters() {
        let links = [TunnelHelp.setup, TunnelHelp.installation, TunnelHelp.tunnels, TunnelHelp.runtimeKeys,
                     TunnelHelp.permissions, TunnelHelp.plugins, TunnelHelp.oauth, TunnelHelp.cloudflare, TunnelHelp.cloudflareInstall]
        for url in links {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNil(url.user); XCTAssertNil(url.password); XCTAssertNil(url.query)
            XCTAssertTrue(["developers.openai.com", "platform.openai.com", "chatgpt.com", "github.com", "developers.cloudflare.com"].contains(url.host ?? ""))
        }
        XCTAssertEqual(TunnelHelp.runtimeKeys.path, "/settings/organization/api-keys")
    }
    func testOAuthAndCloudflareURLsHaveSeparateContracts() {
        XCTAssertNotNil(RemoteConnectionValidation.trustedHTTPS("https://identity.example.com/tenant/"))
        XCTAssertNotNil(RemoteConnectionValidation.publicHTTPS("https://mcp.example.com", originOnly: true))
        for input in ["http://mcp.example.com", "https://user:secret@mcp.example.com", "https://mcp.example.com?token=secret", "https://mcp.example.com#secret", "https://mcp.example.com/\nheader"] {
            XCTAssertNil(RemoteConnectionValidation.trustedHTTPS(input))
        }
        for input in ["https://localhost", "https://127.0.0.1", "https://mcp.example.com/mcp", "https://mcp.example.com:443", "https://mcp.example.com:8443", "https://mcp.internal", "https://invalid..example.com"] {
            XCTAssertNil(RemoteConnectionValidation.publicHTTPS(input, originOnly: true), input)
        }
    }
    func testDisabledOnboardingCanBeIncompleteButCannotPersistSecretURLs() {
        var oauth = OAuthSettings()
        var settings = RemoteConnectionSettings(oauth: oauth)
        XCTAssertNil(RemoteConnectionValidation.issue(settings))
        oauth.issuer = "https://user:secret@identity.example.com"
        settings.oauth = oauth
        XCTAssertNotNil(RemoteConnectionValidation.issue(settings))
        oauth.issuer = ""; oauth.enabled = true; settings.oauth = oauth
        XCTAssertNotNil(RemoteConnectionValidation.issue(settings))
    }
    @MainActor func testCloudflareSnapshotReportsObservationAndClearsOnDisconnect() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        let snapshot: [String: Any] = ["workspaceID":"default", "protocolVersion":1, "port":8787,
            "tunnels":[["type":"tunnelStatus", "key":"transport:cloudflare", "action":"run", "running":true, "ready":false,
                        "publicURL":"https://mcp.example.com", "mcpURL":"https://mcp.example.com/mcp", "state":"awaiting_public_metadata"]]]
        store.applySharedSnapshot(snapshot)
        XCTAssertTrue(store.tunnelRunning("transport:cloudflare"))
        XCTAssertEqual(store.cloudflarePublicURL, "https://mcp.example.com/mcp")
        XCTAssertEqual(store.tunnelReady["transport:cloudflare"], false)
        store.consumeEvent("{\"type\":\"sharedDisconnected\"}")
        XCTAssertNil(store.cloudflarePublicURL)
        XCTAssertFalse(store.tunnelRunning("transport:cloudflare"))
    }
    @MainActor func testOAuthEditsRemainPendingUntilRuntimeFingerprintChanges() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.isAttachedGateway = true
        store.appliedGatewayFingerprints = ["oauthEnabled":ConfigurationFingerprint.scalar("false")]
        var oauth = OAuthSettings(); oauth.enabled = true
        store.savedPreferences.remoteConnection = RemoteConnectionSettings(oauth: oauth)
        XCTAssertEqual(store.gatewayRestartReasons, ["OAuth 开关"])
        XCTAssertTrue(store.pendingCommands.isEmpty)
        store.appliedGatewayFingerprints["oauthEnabled"] = ConfigurationFingerprint.scalar("true")
        XCTAssertTrue(store.gatewayRestartReasons.isEmpty)
    }
}

extension TunnelOnboardingTests {
    @MainActor func testAbsentOAuthMatchesBackendDefaultsWithoutRestartNotice() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.isAttachedGateway = true
        let hash = ConfigurationFingerprint.scalar
        store.appliedGatewayFingerprints = ["oauthEnabled":hash("false"), "oauthPublicURL":hash(""),
            "oauthIssuer":hash(""), "oauthJWKSURL":hash(""), "oauthScope":hash("mcp:tools")]
        XCTAssertNil(store.savedPreferences.remoteConnection)
        XCTAssertTrue(store.gatewayRestartReasons.isEmpty)
    }
    @MainActor func testReservedTransportKeyCannotCollideWithServerID() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.isAttachedGateway = true
        store.savedPreferences.servers = [ServerConfig(id: "cloudflare")]
        store.savedPreferences.tunnelRecords = [TunnelRecord(id: "cloudflare", name: "Named record", serverIDs: ["cloudflare"])]
        store.runningTunnelKeys = ["cloudflare", "transport:cloudflare"]
        XCTAssertTrue(store.tunnelRestartReasons("cloudflare").isEmpty)
        XCTAssertEqual(store.tunnelRestartReasons("transport:cloudflare"), ["配置已移除"])
    }
}
