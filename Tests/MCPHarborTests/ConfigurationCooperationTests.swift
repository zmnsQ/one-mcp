import XCTest
@testable import MCPHarbor

final class ConfigurationCooperationTests: XCTestCase {
    func testCleanIdleEditorReloads() {
        XCTAssertEqual(ConfigurationReloadDecision.decide(saved: "old", disk: "new", dirty: false, running: false), .reload)
    }
    func testDirtyEditorPreservesEditsEvenWhenRunning() {
        for running in [false, true] {
            XCTAssertEqual(ConfigurationReloadDecision.decide(saved: "old", disk: "new", dirty: true, running: running), .preserveEdits)
        }
    }
    func testRunningSnapshotDefersUntilStopped() {
        XCTAssertEqual(ConfigurationReloadDecision.decide(saved: "old", disk: "new", dirty: false, running: true), .deferUntilStopped)
        XCTAssertEqual(ConfigurationReloadDecision.decide(saved: "new", disk: "new", dirty: false, running: true), .unchanged)
    }
}
