import XCTest
import AppKit
@testable import MCPHarbor

final class DashboardPresentationTests: XCTestCase {
    @MainActor func testNativeStatusImagesKeepColorAndAccessibleText() {
        for status: MenuBarStatus in [.running, .ready, .starting, .stopping, .stopped, .checking, .failed, .unknown] {
            let image = status.menuImage
            XCTAssertFalse(image.isTemplate, "NSMenu must not turn colored indicators into template glyphs")
            XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
            XCTAssertEqual(image.accessibilityDescription, status.title)
            XCTAssertNotNil(image.tiffRepresentation)
        }
    }
    func testServiceStopDescriptionDoesNotClaimAllIndependentTunnelsStop() {
        let text = ServiceStopImpact.message(name: "Search")
        XCTAssertTrue(text.contains("Search"))
        XCTAssertTrue(text.contains("依赖此服务"))
        XCTAssertTrue(text.contains("旧版 Cloudflare"))
        XCTAssertTrue(text.contains("其他独立隧道"))
        XCTAssertFalse(text.contains("全部隧道"))
    }
    func testUnknownAndStoppedRemainDistinct() {
        XCTAssertNotEqual(MenuBarStatus.unknown.title, MenuBarStatus.stopped.title)
        XCTAssertNotEqual(MenuBarStatus.unknown.symbol, MenuBarStatus.stopped.symbol)
        XCTAssertEqual(MenuBarStatus.gateway("Disconnected"), .unknown)
        XCTAssertEqual(MenuBarStatus.tunnel(event: [:]), .unknown)
    }
}
