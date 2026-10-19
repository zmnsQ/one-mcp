import XCTest
@testable import MCPHarbor

final class MenuBarStatusTests: XCTestCase {
    func testServiceStatesAreLocalizedWithoutInventingUnknownStatus() {
        XCTAssertEqual(MenuBarStatus.server("running").title, "运行中")
        XCTAssertEqual(MenuBarStatus.server("starting"), .starting)
        XCTAssertEqual(MenuBarStatus.server("stopping"), .stopping)
        XCTAssertEqual(MenuBarStatus.server("error"), .failed)
        XCTAssertEqual(MenuBarStatus.server(nil), .stopped)
        XCTAssertEqual(MenuBarStatus.server("new-protocol-state"), .unknown)
    }
    func testGatewayDisconnectDoesNotClaimStopped() {
        XCTAssertEqual(MenuBarStatus.gateway("Disconnected"), .unknown)
        XCTAssertEqual(MenuBarStatus.gateway("Stopped (exit 1)"), .failed)
        XCTAssertEqual(MenuBarStatus.gateway("Ready · loopback only"), .ready)
    }
    func testTunnelStateUsesStructuredEvidence() {
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": true, "ready": false]), .running)
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": true, "ready": true]), .ready)
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": true, "action": "doctor"]), .checking)
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": true, "state": "Stopping"]), .stopping)
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": false, "exitCode": 0]), .stopped)
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": false, "exitCode": 1]), .failed)
        XCTAssertEqual(MenuBarStatus.tunnel(event: ["running": false, "errorCode": "FAILED", "message": "private detail"]), .failed)
        XCTAssertEqual(MenuBarStatus.tunnel(event: [:]), .unknown)
    }
    @MainActor func testDisconnectedAndStoppedGatewayNeverShowStaleReady() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        store.gatewayState = "Ready · loopback only"
        store.states["server"] = "running"
        store.tunnelMenuStates["tunnel"] = .ready
        XCTAssertEqual(store.menuServerStatus("server"), .running)
        XCTAssertEqual(store.menuTunnelStatus("tunnel"), .ready)
        store.gatewayState = "Disconnected"
        XCTAssertEqual(store.menuServerStatus("server"), .unknown)
        XCTAssertEqual(store.menuTunnelStatus("tunnel"), .unknown)
        store.gatewayState = "Stopped"
        XCTAssertEqual(store.menuServerStatus("server"), .stopped)
        XCTAssertEqual(store.menuTunnelStatus("tunnel"), .stopped)
        store.consumeEvent("{\"type\":\"sharedDisconnected\"}")
        XCTAssertTrue(store.tunnelMenuStates.isEmpty)
    }
}
