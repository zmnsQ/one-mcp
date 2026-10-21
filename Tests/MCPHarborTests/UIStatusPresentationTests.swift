import XCTest
@testable import MCPHarbor

final class UIStatusPresentationTests: XCTestCase {
    func testStatusToneAndSymbolsRemainSemantic() {
        for state: MenuBarStatus in [.running, .ready] { XCTAssertEqual(state.tone, .positive) }
        for state: MenuBarStatus in [.starting, .checking, .stopping] { XCTAssertEqual(state.tone, .warning) }
        XCTAssertEqual(MenuBarStatus.failed.tone, .negative)
        for state: MenuBarStatus in [.stopped, .unknown] { XCTAssertEqual(state.tone, .neutral) }
        XCTAssertNotEqual(MenuBarStatus.unknown.symbol, MenuBarStatus.stopped.symbol)
        XCTAssertNotEqual(MenuBarStatus.failed.symbol, MenuBarStatus.ready.symbol)
    }

    func testSidebarCountsOnlyObservedRunningStates() {
        let summary = RuntimeStatusSummary(gateway: .ready,
            servers: [.running, .starting, .failed, .stopped], tunnels: [.ready, .stopping])
        XCTAssertEqual(summary.runningServers, 1)
        XCTAssertEqual(summary.runningTunnels, 1)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertFalse(summary.hasUnknownStates)
    }

    func testUnknownCountsAreNotPresentedAsConfirmedStopped() {
        let summary = RuntimeStatusSummary(gateway: .unknown, servers: [.unknown], tunnels: [.unknown])
        XCTAssertTrue(summary.hasUnknownStates)
        XCTAssertTrue(summary.activityText.contains("状态待确认"))
        XCTAssertFalse(summary.activityText.contains("0/1"))
    }

    func testSkippedStartupResultIsDistinctFromFailure() {
        let skipped = StartAllStep(id: "one", title: "One", status: "skipped")
        let failure = StartAllStep(id: "two", title: "Two", status: "failed")
        XCTAssertEqual(skipped.statusTitle, "已跳过")
        XCTAssertEqual(failure.statusTitle, "失败")
        XCTAssertNotEqual(skipped.presentationStatus.tone, failure.presentationStatus.tone)
    }
}
