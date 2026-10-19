import Foundation
import XCTest
@testable import MCPHarbor

final class TunnelRecordTests: XCTestCase {
    private func legacy(_ preferences: Preferences) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        json.removeValue(forKey: "tunnelRecords")
        return try JSONSerialization.data(withJSONObject: json)
    }
    func testLegacyAggregateMigrationSnapshotsBindingsAndPreservesCredentialsMetadata() throws {
        var old = Preferences()
        old.servers = [ServerConfig(id: "one"), ServerConfig(id: "two")]
        old.aggregateTunnelID = "tunnel_old"; old.aggregateProfileFile = "/private/profile.toml"
        var migrated = try JSONDecoder().decode(Preferences.self, from: legacy(old))
        XCTAssertEqual(migrated.effectiveTunnelRecords.count, 1)
        XCTAssertEqual(migrated.effectiveTunnelRecords[0].id, "aggregate")
        XCTAssertEqual(migrated.effectiveTunnelRecords[0].serverIDs, ["one", "two"])
        XCTAssertEqual(migrated.effectiveTunnelRecords[0].profileFile, "/private/profile.toml")
        migrated.servers.append(ServerConfig(id: "three"))
        XCTAssertEqual(migrated.effectiveTunnelRecords[0].serverIDs, ["one", "two"])
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(migrated)), migrated)
    }
    func testLegacyIndividualAndCloudflareMigration() throws {
        var old = Preferences(); old.mode = "individual"
        old.servers = [ServerConfig(id: "one", tunnelID: "tunnel_one", profile: "one", startWithAll: false)]
        let individual = try JSONDecoder().decode(Preferences.self, from: legacy(old))
        XCTAssertEqual(individual.effectiveTunnelRecords.first?.id, "one")
        XCTAssertEqual(individual.effectiveTunnelRecords.first?.serverIDs, ["one"])
        XCTAssertEqual(individual.effectiveTunnelRecords.first?.participatesInStartAll, false)
        old.remoteConnection = RemoteConnectionSettings(preferredTransport: "cloudflare", cloudflare: CloudflareSettings())
        let cloud = try JSONDecoder().decode(Preferences.self, from: legacy(old))
        XCTAssertEqual(cloud.effectiveTunnelRecords.first?.id, "cloudflare-default")
        XCTAssertEqual(cloud.effectiveTunnelRecords.first?.transport, "cloudflare")
        XCTAssertEqual(cloud.effectiveTunnelRecords.first?.serverIDs, ["one"])
    }
    func testNullRecordListCannotTriggerMigration() {
        XCTAssertThrowsError(try JSONDecoder().decode(Preferences.self, from: Data("{\"tunnelRecords\":null}".utf8)))
    }
    func testExplicitEmptyRecordsNeverRestoreLegacyTunnel() throws {
        var config = Preferences(); config.servers = [ServerConfig(id: "one")]; config.aggregateTunnelID = "tunnel_old"
        config.tunnelRecords = []
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(decoded.effectiveTunnelRecords.isEmpty)
    }
    func testRecordsShareBackendsButKeepIndependentConfiguration() throws {
        var config = Preferences(); config.servers = [ServerConfig(id: "one")]
        config.tunnelRecords = [TunnelRecord(id: "a", name: "First", serverIDs: ["one"], profile: "a", tunnelID: "tunnel_a"),
                                TunnelRecord(id: "b", name: "Second", serverIDs: ["one"], transport: "cloudflare", cloudflare: CloudflareSettings(), startWithAll: false)]
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(config)), config)
        XCTAssertNotEqual(TunnelCredentialPolicy.account(workspace: "workspace", record: "a"), TunnelCredentialPolicy.account(workspace: "workspace", record: "b"))
        XCTAssertNotEqual(TunnelCredentialPolicy.account(workspace: "workspace", record: "a"), TunnelCredentialPolicy.account(workspace: "other", record: "a"))
    }
    @MainActor func testMigrationStartupDoesNotWriteFilesOrStartProcesses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var old = Preferences(); old.servers = [ServerConfig(id: "one")]
        let data = try legacy(old), file = root.appendingPathComponent("settings.json")
        try data.write(to: file)
        let store = HarborStore(configurationFileURL: file, startWatcher: false)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(store.preferences.effectiveTunnelRecords.first?.serverIDs, ["one"])
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertNil(store.gateway)
    }
    @MainActor func testRecordBindingFingerprintAndScopedEndpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        let record = TunnelRecord(id: "selected", name: "Selected", serverIDs: ["one", "two"], profile: "p", tunnelID: "tunnel_selected")
        store.preferences.tunnelRecords = [record]; store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.runningTunnelKeys = [record.id]
        store.appliedTunnelFingerprints[record.id] = ["serverIDs": ConfigurationFingerprint.set(["two", "one"])]
        XCTAssertTrue(store.tunnelRestartReasons(record.id).isEmpty)
        store.savedPreferences.tunnelRecords![0].serverIDs = ["one"]
        XCTAssertEqual(store.tunnelRestartReasons(record.id), ["所选 MCP 服务"])
        store.attachedPort = 9999
        XCTAssertEqual(store.endpoint(record: record), "http://127.0.0.1:9999/tunnels/selected/mcp")
        XCTAssertEqual(store.tunnelTargetSignature(key: record.id), [store.preferences.tunnelClientPath, "p", "tunnel_selected", "http://127.0.0.1:9999/tunnels/selected/mcp", "", "one,two"].joined(separator: "\n"))
    }

    @MainActor func testOldGatewayCannotIgnoreRecordScope() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        store.preferences.servers = [ServerConfig(id: "one")]
        let record = TunnelRecord(id: "aggregate", name: "Migrated", serverIDs: ["one"])
        XCTAssertFalse(store.tunnelAction("run", record: record, persistConfiguration: false))
        XCTAssertFalse(store.cloudflareAction("run", record: record, persistConfiguration: false))
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertTrue(store.errorMessage?.contains("新版网关") == true)
        store.appliedGatewayFingerprints["tunnelRecordsVersion"] = ConfigurationFingerprint.scalar("1")
        XCTAssertTrue(store.requireScopedTunnelRuntime())
        store.appliedGatewayFingerprints["tunnelRecordsVersion"] = ConfigurationFingerprint.scalar("2")
        XCTAssertFalse(store.requireScopedTunnelRuntime())
    }

}
