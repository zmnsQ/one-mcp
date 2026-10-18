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
        store.preferences.servers = [running, excluded]; store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"; store.states["running"] = "running"
        store.startAll()
        let task = store.startAllTask
        store.startAll() // Double click cannot replace the active operation or submit work.
        await task?.value
        XCTAssertFalse(store.startAllBusy)
        XCTAssertTrue(store.pendingCommands.isEmpty)
        XCTAssertEqual(store.startAllSteps.first(where: { $0.id == "server:running" })?.status, "skipped")
        XCTAssertEqual(store.startAllSteps.first(where: { $0.id == "server:excluded" })?.detail, "未参与全部启动")
        XCTAssertTrue(store.startAllSteps.first(where: { $0.id == "tunnel:aggregate" })?.detail.contains("Tunnel ID") == true)
    }
    @MainActor func testTunnelExitUpdatesBatchResultAfterSubmission() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.startAllSteps = [.init(id: "tunnel:aggregate", title: "Tunnel", detail: "submitted", status: "succeeded")]
        store.refreshStartAllTunnel(["key":"aggregate", "action":"run", "running":false, "errorCode":"TUNNEL_AUTH", "message":"凭据不可用"])
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
        store.preferences.remoteConnection = RemoteConnectionSettings(preferredTransport: "cloudflare")
        store.savedPreferences = store.preferences
        store.isAttachedGateway = true; store.gatewayState = "Ready · loopback only"
        XCTAssertTrue(store.startAllConfirmation.contains("Cloudflare"))
        store.startAll()
        await store.startAllTask?.value
        XCTAssertNotNil(store.startAllSteps.first(where: { $0.id == "tunnel:transport:cloudflare" }))
        XCTAssertNil(store.startAllSteps.first(where: { $0.id == "tunnel:aggregate" }))
        XCTAssertTrue(store.pendingCommands.isEmpty)
    }
}
