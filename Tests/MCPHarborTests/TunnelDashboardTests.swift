import XCTest
@testable import MCPHarbor
final class TunnelDashboardTests: XCTestCase {
    func testOnlyPrivateLoopbackBaseURL() {
        XCTAssertNotNil(TunnelDashboardURL.validated("http://127.0.0.1:18080/"))
        for value in ["https://example.com", "http://localhost:18080/", "http://127.0.0.1:18080/?token=x", "http://user:pass@127.0.0.1:18080/", "http://127.0.0.1:18080/ui"] {
            XCTAssertNil(TunnelDashboardURL.validated(value))
        }
    }
    func testDegradedIsNotSuccessAndUnknownIsNotVerified() {
        let snapshot = TunnelHealthSnapshot(["available": true, "ready": true, "components": [["name":"control-plane", "status":"degraded"], ["name":"mcp", "status":"unknown"]]])
        XCTAssertEqual(snapshot?.components.first?.label, "需要检查")
        XCTAssertEqual(snapshot?.components.last?.label, "尚无证据")
    }
}
