import XCTest
@testable import MCPHarbor
final class TunnelCredentialPolicyTests: XCTestCase {
    func testStableWorkspaceAccountMatchesExistingVault() {
        XCTAssertEqual(TunnelCredentialPolicy.account(workspace: "default"), "default:__tunnel_key")
        XCTAssertNotEqual(TunnelCredentialPolicy.account(workspace: "a"), TunnelCredentialPolicy.account(workspace: "b"))
        XCTAssertFalse(TunnelCredentialPolicy.preference(workspace: "default").contains(".app/"))
    }
    func testAutofillRequiresOptInAndPreservesEnteredValue() {
        XCTAssertFalse(TunnelCredentialPolicy.shouldAutofill(enabled: false, current: ""))
        XCTAssertFalse(TunnelCredentialPolicy.shouldAutofill(enabled: true, current: "already-entered"))
        XCTAssertTrue(TunnelCredentialPolicy.shouldAutofill(enabled: true, current: ""))
    }
}
