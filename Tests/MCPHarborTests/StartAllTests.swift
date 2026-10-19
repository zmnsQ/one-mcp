import Foundation
import XCTest
@testable import MCPHarbor

final class StartAllTests: XCTestCase {
    func testParticipationIsBackwardCompatibleAndRoundTrips() throws {
        let server = ServerConfig()
        XCTAssertTrue(server.participatesInStartAll)
        var excluded = server; excluded.startWithAll = false
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(excluded))
        XCTAssertFalse(decoded.participatesInStartAll)
        XCTAssertEqual(decoded.allowedTools, server.allowedTools)
    }
    @MainActor func testSkipRunningAndExcludedWithoutStartingTunnel() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        var running = ServerConfig(); running.id = "running"; running.name = "Running"
        var excluded = ServerConfig(); excluded.id = "excluded"; excluded.startWithAll = false
        store.preferences.servers = [running, excluded]
        store.preferences.tunnelRecords = [TunnelRecord(id: "selected", name: "Selected", serverIDs: [running.id])]
        store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"; store.states["running"] = "running"
        store.startAll()
        let task = store.startAllTask
        store.startAll() // Double click cannot replace the active operation or submit work.
        await task?.value
        XCTAssertFalse(store.startAllBusy)
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertEqual(store.startAllSteps.first(where: { $0.id == "server:running" })?.status, "skipped")
        XCTAssertEqual(store.startAllSteps.first(where: { $0.id == "server:excluded" })?.detail, "未参与全部启动")
        XCTAssertTrue(store.startAllSteps.first(where: { $0.id == "tunnel:selected" })?.detail.contains("Tunnel ID") == true)
    }
    @MainActor func testTunnelExitUpdatesBatchResultAfterSubmission() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.preferences.tunnelRecords = [TunnelRecord(id: "record-one", name: "Tunnel")]
        store.startAllSteps = [.init(id: "tunnel:record-one", title: "Tunnel", detail: "submitted", status: "succeeded")]
        store.refreshStartAllTunnel(["key":"record-one", "action":"run", "running":false, "errorCode":"TUNNEL_AUTH", "message":"凭据不可用"])
        XCTAssertEqual(store.startAllSteps.first?.status, "failed")
        XCTAssertEqual(store.startAllSteps.first?.detail, "凭据不可用")
    }
    @MainActor func testUnsavedConfigurationIsNotImplicitlyWritten() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.preferences.servers = [ServerConfig()]
        store.startAll()
        XCTAssertFalse(store.startAllBusy)
        XCTAssertNil(store.startAllTask)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.json").path))
    }
    @MainActor func testExternalDiskEditBeforeWatcherPreventsDispatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        let store = HarborStore(configurationFileURL: url, startWatcher: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(Preferences()).write(to: url)
        store.startAll()
        XCTAssertFalse(store.startAllBusy)
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertTrue(store.errorMessage?.contains("磁盘配置") == true)
    }
    @MainActor func testApprovalCannotFollowChangedPlan() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        let approved = store.preferences
        store.preferences.mode = "individual"; store.savedPreferences = store.preferences
        store.startAll(expectedPlan: approved, expectedWorkspace: store.currentWorkspaceID, expectedRevision: store.savedRevision)
        XCTAssertFalse(store.startAllBusy)
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertTrue(store.errorMessage?.contains("确认期间") == true)
    }
    @MainActor func testConfigurationChangeBeforeTaskRunsAbortsWithoutDispatch() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        store.startAll(); store.preferences.port = 9999
        await store.startAllTask?.value
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertFalse(store.startAllBusy)
    }
}


extension StartAllTests {
    @MainActor func testCloudflareChoiceDoesNotRequireOpenAITunnelOrKey() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.preferences.tunnelRecords = [TunnelRecord(id: "cloudflare-one", name: "Cloudflare", transport: "cloudflare")]
        store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        XCTAssertTrue(store.startAllConfirmation.contains("Cloudflare"))
        store.startAll()
        await store.startAllTask?.value
        XCTAssertNotNil(store.startAllSteps.first(where: { $0.id == "tunnel:cloudflare-one" }))
        XCTAssertNil(store.startAllSteps.first(where: { $0.id == "tunnel:aggregate" }))
        XCTAssertTrue(store.pendingCommands.isEmpty)
    }
}


extension StartAllTests {
    func testRecordParticipationDefaultsToEnabledAndRoundTrips() throws {
        var record = TunnelRecord(id: "excluded", name: "Excluded")
        XCTAssertTrue(record.participatesInStartAll)
        record.startWithAll = false
        let decoded = try JSONDecoder().decode(TunnelRecord.self, from: JSONEncoder().encode(record))
        XCTAssertFalse(decoded.participatesInStartAll)
        XCTAssertEqual(decoded.id, record.id)
    }

    @MainActor func testExcludedRecordIsSkippedWithoutDispatch() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.preferences.tunnelRecords = [TunnelRecord(id: "excluded-record", name: "Excluded record", startWithAll: false)]
        store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        store.startAll()
        await store.startAllTask?.value
        let step = store.startAllSteps.first(where: { $0.id == "tunnel:excluded-record" })
        XCTAssertEqual(step?.status, "skipped")
        XCTAssertEqual(step?.detail, "未参与全部启动")
        XCTAssertFalse(store.startAllConfirmation.contains("Excluded record"))
        XCTAssertTrue(store.pendingCommands.isEmpty)
    }

    @MainActor func testEmptyAndMissingBindingsAreSkippedForBothTransports() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.preferences.tunnelRecords = [
            TunnelRecord(id: "openai-empty", name: "Empty OpenAI"),
            TunnelRecord(id: "openai-missing", name: "Missing OpenAI", serverIDs: ["removed"]),
            TunnelRecord(id: "cloudflare-empty", name: "Empty Cloudflare", transport: "cloudflare"),
            TunnelRecord(id: "cloudflare-missing", name: "Missing Cloudflare", serverIDs: ["removed"], transport: "cloudflare")
        ]
        store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        store.states["removed"] = "running" // A stale state cannot satisfy a missing configuration.
        store.startAll()
        await store.startAllTask?.value
        for record in store.preferences.effectiveTunnelRecords {
            let step = store.startAllSteps.first(where: { $0.id == "tunnel:" + record.id })
            XCTAssertEqual(step?.status, "skipped")
            XCTAssertTrue(step?.detail.contains("所选 MCP") == true)
        }
        XCTAssertTrue(store.pendingCommands.isEmpty)
    }

    @MainActor func testEverySelectedBackendMustRunForBothTransports() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        var first = ServerConfig(); first.id = "first"
        var second = ServerConfig(); second.id = "second"; second.startWithAll = false
        store.preferences.servers = [first, second]
        store.preferences.tunnelRecords = [
            TunnelRecord(id: "openai-pair", name: "OpenAI pair", serverIDs: [first.id, second.id]),
            TunnelRecord(id: "cloudflare-pair", name: "Cloudflare pair", serverIDs: [first.id, second.id], transport: "cloudflare")
        ]
        store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        store.states[first.id] = "running"; store.states[second.id] = "stopped"
        store.startAll()
        await store.startAllTask?.value
        for record in store.preferences.effectiveTunnelRecords {
            let step = store.startAllSteps.first(where: { $0.id == "tunnel:" + record.id })
            XCTAssertEqual(step?.status, "skipped")
            XCTAssertTrue(step?.detail.contains("尚未全部运行") == true)
        }
        XCTAssertTrue(store.pendingCommands.isEmpty)

        // An already-running selected backend counts even when excluded from server startup.
        // Missing OpenAI credentials then fail preflight, proving backend readiness passed.
        store.states[second.id] = "running"
        store.preferences.tunnelRecords = [store.preferences.effectiveTunnelRecords[0]]
        store.savedPreferences = store.preferences
        store.startAll()
        await store.startAllTask?.value
        let readyStep = store.startAllSteps.first(where: { $0.id == "tunnel:openai-pair" })
        XCTAssertEqual(readyStep?.status, "failed")
        XCTAssertTrue(readyStep?.detail.contains("Tunnel ID") == true)
        XCTAssertTrue(store.pendingCommands.isEmpty)
    }

    @MainActor func testMixedTransportConfirmationNamesRecordsAndDisclosesBothDestinations() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.preferences.tunnelRecords = [
            TunnelRecord(id: "openai-one", name: "Office tools"),
            TunnelRecord(id: "cloudflare-one", name: "Public tools", transport: "cloudflare"),
            TunnelRecord(id: "excluded", name: "Excluded tools", startWithAll: false)
        ]
        let confirmation = store.startAllConfirmation
        XCTAssertTrue(confirmation.contains("Office tools"))
        XCTAssertTrue(confirmation.contains("Public tools"))
        XCTAssertFalse(confirmation.contains("Excluded tools"))
        XCTAssertTrue(confirmation.contains("发送到 OpenAI"))
        XCTAssertTrue(confirmation.contains("经过 Cloudflare"))
        XCTAssertTrue(confirmation.contains("OAuth"))
    }
}
