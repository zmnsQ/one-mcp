import Foundation
import XCTest
@testable import MCPHarbor

final class SharedRuntimeRecoveryTests: XCTestCase {
    @MainActor func testDisconnectedAdapterDoesNotClaimGatewayStoppedOrDeleteConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        let original = store.preferences
        store.consumeEvent("{\"type\":\"sharedDisconnected\",\"message\":\"connection lost\"}")
        XCTAssertEqual(store.gatewayState, "Disconnected")
        XCTAssertFalse(store.isAttachedGateway)
        XCTAssertFalse(store.gatewayStartBusy)
        XCTAssertEqual(store.preferences, original)
        XCTAssertNil(store.gateway)
    }
    @MainActor func testTruncatedSnapshotPreservesPermissionsAndWarnsAboutMissingCatalog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        let original = store.preferences
        store.applySharedSnapshot(["workspaceID":"default", "protocolVersion":1, "port":8787,
            "servers":[["id":"large", "name":"Large", "running":true, "allowedTools":["echo"],
                        "toolCount":1000, "toolMetadataTruncated":true, "toolCatalogOmitted":true]]])
        XCTAssertTrue(store.gatewayReady)
        XCTAssertEqual(store.sharedRuntimeServers.first?.allowedTools, ["echo"])
        XCTAssertEqual(store.states["large"], "running")
        XCTAssertNil(store.tools["large"])
        XCTAssertTrue(store.notice?.contains("省略") == true)
        XCTAssertEqual(store.preferences, original)
    }
}
