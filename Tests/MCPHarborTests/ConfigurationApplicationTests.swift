import Foundation
import XCTest
@testable import MCPHarbor

final class ConfigurationApplicationTests: XCTestCase {
    @MainActor private func withStore(_ body: (HarborStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var config = Preferences()
        config.servers = [ServerConfig(id: "echo", name: "Echo", executable: "/usr/bin/true", arguments: ["before"], allowedTools: ["echo"])]
        let file = root.appendingPathComponent("settings.json")
        try JSONEncoder().encode(config).write(to: file, options: .atomic)
        let store = HarborStore(configurationFileURL: file, startWatcher: false)
        try body(store, file)
    }
    @MainActor private func snapshot(_ store: HarborStore, config: Preferences) {
        store.applySharedSnapshot(["workspaceID":"default", "protocolVersion":1, "port":config.port,
            "configurationFingerprintVersion":1,
            "servers":config.servers.map { server in
                ["id":server.id, "name":server.name, "running":true, "allowedTools":server.allowedTools,
                 "configurationFingerprintVersion":1, "configurationFingerprints":ConfigurationFingerprint.server(server)] as [String: Any]
            }])
    }
    @MainActor func testSavedEditReloadsWhileRunningWithoutApplyingOrRestarting() throws {
        try withStore { store, file in
            let applied = store.savedPreferences
            snapshot(store, config: applied)
            var desired = applied; desired.servers[0].arguments = ["after"]
            try JSONEncoder().encode(desired).write(to: file, options: .atomic)
            store.reloadExternalConfiguration()
            XCTAssertEqual(store.preferences, desired)
            XCTAssertEqual(store.savedPreferences, desired)
            XCTAssertFalse(store.hasUnsavedChanges)
            XCTAssertEqual(store.states["echo"], "running")
            XCTAssertEqual(store.serverRestartReasons("echo"), ["参数"])
            XCTAssertTrue(store.pendingCommands.isEmpty)
            XCTAssertNil(store.gateway)
            // Periodic runtime snapshots cannot replace desired data or clear pending changes.
            snapshot(store, config: applied)
            XCTAssertEqual(store.preferences, desired)
            XCTAssertEqual(store.serverRestartReasons("echo"), ["参数"])
            // After an explicitly restarted process reports the new applied fields, the badge clears.
            snapshot(store, config: desired)
            XCTAssertTrue(store.serverRestartReasons("echo").isEmpty)
        }
    }
    @MainActor func testDirtyEditorIsPreservedAndCanExplicitlyReloadWhileRunning() throws {
        try withStore { store, file in
            let applied = store.savedPreferences; snapshot(store, config: applied)
            store.preferences.servers[0].name = "Unsaved edit"
            var desired = applied; desired.servers[0].arguments = ["external"]
            try JSONEncoder().encode(desired).write(to: file, options: .atomic)
            store.reloadExternalConfiguration()
            XCTAssertEqual(store.preferences.servers[0].name, "Unsaved edit")
            XCTAssertNotNil(store.externalConfigurationNotice)
            snapshot(store, config: applied)
            XCTAssertNotNil(store.externalConfigurationNotice)
            XCTAssertFalse(store.save())
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: file)), desired)
            store.reloadExternalConfiguration(discardLocalChanges: true)
            XCTAssertEqual(store.preferences, desired)
            XCTAssertEqual(store.serverRestartReasons("echo"), ["参数"])
        }
    }
    @MainActor func testInvalidAndMissingExternalConfigRetainsLastGoodAndRecovers() throws {
        try withStore { store, file in
            let good = store.savedPreferences; snapshot(store, config: good)
            try Data("invalid: secret-value-must-not-appear".utf8).write(to: file)
            store.reloadExternalConfiguration()
            XCTAssertEqual(store.preferences, good)
            XCTAssertNotNil(store.externalConfigurationNotice)
            XCTAssertFalse(store.externalConfigurationNotice?.contains("secret-value") == true)
            try FileManager.default.removeItem(at: file)
            store.reloadExternalConfiguration()
            XCTAssertEqual(store.preferences, good)
            XCTAssertNotNil(store.externalConfigurationNotice)
            try JSONEncoder().encode(good).write(to: file, options: .atomic)
            store.reloadExternalConfiguration()
            XCTAssertNil(store.externalConfigurationNotice)
        }
    }
    @MainActor func testAddedAndRemovedItemsDoNotRestartOrExpandRuntime() throws {
        try withStore { store, file in
            let applied = store.savedPreferences; snapshot(store, config: applied)
            var desired = applied
            desired.servers = [ServerConfig(id: "new", name: "New", executable: "/usr/bin/true")]
            try JSONEncoder().encode(desired).write(to: file, options: .atomic)
            store.reloadExternalConfiguration()
            XCTAssertEqual(store.selectedID, "new")
            XCTAssertTrue(store.serverRestartReasons("new").isEmpty)
            XCTAssertNil(store.states["new"])
            XCTAssertEqual(store.sharedRuntimeServers.first?.id, "echo")
            XCTAssertEqual(store.configurationApplicationNotices.map(\.id), ["removed:echo"])
            XCTAssertTrue(store.pendingCommands.isEmpty)
        }
    }
    @MainActor func testOnlyChangedEffectiveFieldsNeedRestartAndReversionClears() throws {
        try withStore { store, _ in
            let applied = store.savedPreferences; snapshot(store, config: applied)
            store.savedPreferences.mode = "individual"
            store.savedPreferences.servers[0].tunnelID = "tunnel_changed"
            XCTAssertTrue(store.serverRestartReasons("echo").isEmpty)
            store.savedPreferences.servers[0].allowedTools = ["additional", "echo"]
            XCTAssertEqual(store.serverRestartReasons("echo"), ["工具白名单"])
            XCTAssertEqual(store.sharedRuntimeServers.first?.allowedTools, ["echo"])
            store.savedPreferences = applied
            XCTAssertTrue(store.serverRestartReasons("echo").isEmpty)
        }
    }
    @MainActor func testDisconnectClearsAppliedStateAndReconnectRestoresComparison() throws {
        try withStore { store, _ in
            let applied = store.savedPreferences; snapshot(store, config: applied)
            store.savedPreferences.servers[0].arguments = ["changed"]
            store.consumeEvent("{\"type\":\"sharedDisconnected\"}")
            XCTAssertTrue(store.appliedServerFingerprints.isEmpty)
            XCTAssertTrue(store.configurationApplicationNotices.isEmpty)
            snapshot(store, config: applied)
            XCTAssertEqual(store.serverRestartReasons("echo"), ["参数"])
        }
    }
    @MainActor func testFreshMissingDefaultRemainsQuietUntilFirstSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.reloadExternalConfiguration()
        XCTAssertNil(store.externalConfigurationNotice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    @MainActor func testOwnedGatewayKeepsRemovedRunningSummary() throws {
        try withStore { store, _ in
            // The owned process sends events rather than shared snapshots.
            let server = store.savedPreferences.servers[0]
            let event: [String: Any] = ["type":"serverStatus", "serverId":server.id, "name":server.name,
                "status":"running", "allowedTools":server.allowedTools,
                "configurationFingerprintVersion":1, "configurationFingerprints":ConfigurationFingerprint.server(server)]
            store.consumeEvent(String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self))
            XCTAssertEqual(store.sharedRuntimeServers.first?.name, "Echo")
            XCTAssertEqual(store.sharedRuntimeServers.first?.allowedTools, ["echo"])
            store.consumeEvent("{\"type\":\"serverStatus\",\"serverId\":\"echo\",\"status\":\"stopped\"}")
            XCTAssertTrue(store.sharedRuntimeServers.isEmpty)
        }
    }
    @MainActor func testLegacyOwnedEventDoesNotInventEmptyPermissions() throws {
        try withStore { store, _ in
            store.consumeEvent("{\"type\":\"serverStatus\",\"serverId\":\"echo\",\"status\":\"running\"}")
            // Treat as a connected runtime only for testing computed comparison (no process launched).
            store.isAttachedGateway = true
            XCTAssertEqual(store.sharedRuntimeServers.first?.permissionsKnown, false)
            XCTAssertTrue(store.serverRestartReasons("echo").isEmpty)
            XCTAssertTrue(store.runtimeComparisonUnavailable)
        }
    }
    @MainActor func testGatewayAndTunnelReasonsReflectOnlyEffectiveSavedChanges() throws {
        try withStore { store, _ in
            store.savedPreferences.tunnelRecords = [TunnelRecord(id: "aggregate", name: "Selected services", serverIDs: ["echo"], profile: "profile")]
            let applied = store.savedPreferences; snapshot(store, config: applied)
            let hash = ConfigurationFingerprint.scalar
            let tunnel: [String: Any] = ["type":"tunnelStatus", "key":"aggregate", "running":true,
                "configurationFingerprintVersion":1,
                "configurationFingerprints":["executable":hash(applied.tunnelClientPath),
                    "profile":hash("profile"), "tunnelID":hash(""),
                    "profileFile":hash(""), "endpoint":hash("http://127.0.0.1:8787/tunnels/aggregate/mcp"), "serverIDs":ConfigurationFingerprint.set(["echo"])]]
            store.consumeEvent(String(decoding: try JSONSerialization.data(withJSONObject: tunnel), as: UTF8.self))
            XCTAssertTrue(store.tunnelRestartReasons("aggregate").isEmpty)
            store.savedPreferences.mode = "individual"
            XCTAssertTrue(store.tunnelRestartReasons("aggregate").isEmpty)
            XCTAssertTrue(store.runningTunnelKeys.contains("aggregate"))
            store.savedPreferences.port = 9988
            XCTAssertEqual(store.gatewayRestartReasons, ["监听端口"])
            XCTAssertEqual(store.tunnelRestartReasons("aggregate"), ["网关端点"])
            XCTAssertEqual(store.endpoint(nil), "http://127.0.0.1:8787/mcp")
            store.savedPreferences.port = applied.port
            store.savedPreferences.tunnelRecords![0].tunnelID = "tunnel_changed"
            XCTAssertTrue(store.gatewayRestartReasons.isEmpty)
            XCTAssertEqual(store.tunnelRestartReasons("aggregate"), ["Tunnel ID"])
            store.consumeEvent("{\"type\":\"tunnelStatus\",\"key\":\"aggregate\",\"running\":false}")
            XCTAssertTrue(store.tunnelRestartReasons("aggregate").isEmpty)
            XCTAssertNil(store.appliedTunnelFingerprints["aggregate"])
        }
    }
    func testSharedFingerprintGoldenVectors() throws {
        struct Vector: Decodable { let values: [String]; let sha256: String }
        struct Fixture: Decodable { let version: Int; let vectors: [Vector] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("gateway/validation/configuration-fingerprint-vectors.json")))
        XCTAssertEqual(fixture.version, 1)
        for vector in fixture.vectors { XCTAssertEqual(ConfigurationFingerprint.strings(vector.values), vector.sha256) }
    }
    func testFingerprintEncodingDistinguishesLengthsAndCanonicalUnicode() {
        XCTAssertNotEqual(ConfigurationFingerprint.strings([]), ConfigurationFingerprint.scalar(""))
        XCTAssertNotEqual(ConfigurationFingerprint.strings(["ab", "c"]), ConfigurationFingerprint.strings(["a", "bc"]))
        XCTAssertEqual(ConfigurationFingerprint.set(["b", "a", "b"]), ConfigurationFingerprint.set(["a", "b"]))
        XCTAssertNotEqual(ConfigurationFingerprint.scalar("é"), ConfigurationFingerprint.scalar("e\u{301}"))
        XCTAssertNotEqual(ConfigurationFingerprint.set(["é", "e\u{301}"]), ConfigurationFingerprint.set(["é"]))
        XCTAssertTrue(ConfigurationFingerprint.decode(["configurationFingerprintVersion":2, "configurationFingerprints":["name":"unknown"]]).isEmpty)
    }
}
