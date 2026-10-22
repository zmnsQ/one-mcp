import Foundation
import XCTest
@testable import MCPHarbor

final class ToolSelectionTests: XCTestCase {
    @MainActor private func withStore(_ body: (HarborStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var config = Preferences()
        config.servers = [ServerConfig(id: "echo", name: "Echo", executable: "/usr/bin/true", allowedTools: ["echo"])]
        let file = root.appendingPathComponent("settings.json")
        try JSONEncoder().encode(config).write(to: file, options: .atomic)
        try body(HarborStore(configurationFileURL: file, startWatcher: false))
    }
    @MainActor func testSaveSelectionPreservesUnrelatedDrafts() throws {
        try withStore { store in
            store.preferences.servers[0].name = "Unsaved name"
            store.preferences.servers[0].arguments = ["unsaved-private-argument"]
            store.preferences.servers[0].allowedTools = []
            XCTAssertTrue(store.saveToolSelection("echo"))
            XCTAssertEqual(store.savedPreferences.servers[0].name, "Echo")
            XCTAssertEqual(store.savedPreferences.servers[0].arguments, [])
            XCTAssertEqual(store.savedPreferences.servers[0].allowedTools, [])
            XCTAssertEqual(store.preferences.servers[0].name, "Unsaved name")
            XCTAssertTrue(store.hasUnsavedChanges)
        }
    }
    @MainActor func testOldRuntimeDoesNotSaveOrApply() throws {
        try withStore { store in
            store.states["echo"] = "running"
            store.gatewayState = "Ready · loopback only"
            store.preferences.servers[0].allowedTools = []
            store.applyToolSelection("echo")
            XCTAssertEqual(store.savedPreferences.servers[0].allowedTools, ["echo"])
            XCTAssertTrue(store.pendingCommands.isEmpty)
            XCTAssertNotNil(store.errorMessage)
        }
    }
    @MainActor func testStoppedSelectionSavesWithoutStarting() throws {
        try withStore { store in
            store.preferences.servers[0].allowedTools = []
            store.applyToolSelection("echo")
            XCTAssertEqual(store.savedPreferences.servers[0].allowedTools, [])
            XCTAssertTrue(store.pendingCommands.isEmpty)
            XCTAssertNil(store.gateway)
        }
    }
    @MainActor func testLiveCapabilitySeparatesPermissionAndProcessChanges() throws {
        try withStore { store in
            let old = store.savedPreferences.servers[0]
            store.isAttachedGateway = true
            store.states["echo"] = "running"
            store.appliedGatewayFingerprints["liveToolSelectionVersion"] = ConfigurationFingerprint.scalar("1")
            store.appliedServerFingerprints["echo"] = ConfigurationFingerprint.server(old)
            store.sharedRuntimeServers = [.init(id: "echo", name: "Echo", running: true, allowedTools: ["echo"])]
            store.savedPreferences.servers[0].allowedTools = []
            XCTAssertTrue(store.serverRestartReasons("echo").isEmpty)
            XCTAssertTrue(store.configurationApplicationNotices.contains { $0.id == "tools:echo" })
            store.savedPreferences.servers[0].arguments = ["changed"]
            XCTAssertEqual(store.serverRestartReasons("echo"), ["参数"])
        }
    }
}
