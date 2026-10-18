import Foundation
import XCTest
@testable import MCPHarbor

final class RuntimeEnvironmentTests: XCTestCase {
    let current = URL(fileURLWithPath: "/Applications/One MCP.app/Contents/Resources")
    func testEmptyAndPreviousBundleFollowCurrentCompleteBundle() {
        let expected = current.appendingPathComponent("gateway/dist/index.js").path
        for old in ["", "/old/build/One MCP.app/Contents/Resources/gateway/dist/index.js"] {
            XCTAssertEqual(RuntimeEnvironment.resolveGateway(saved: old, resourceURL: current, readable: { _ in true }), expected)
        }
    }
    func testExternalCustomPathIsPreservedEvenWhenUnavailable() {
        for exists in [true, false] {
            XCTAssertEqual(RuntimeEnvironment.resolveGateway(saved: "/custom/gateway/dist/index.js", resourceURL: current, readable: { _ in exists }), "/custom/gateway/dist/index.js")
        }
    }
    func testIncompleteCurrentBundleDoesNotReplaceOldPath() {
        let old = "/old/One MCP.app/Contents/Resources/gateway/dist/index.js"
        XCTAssertEqual(RuntimeEnvironment.resolveGateway(saved: old, resourceURL: current, readable: { !$0.hasSuffix("cli.js") }), old)
        XCTAssertFalse(RuntimeEnvironment.missingFiles(for: old, readable: { !$0.contains("node_modules") }).isEmpty)
    }
    func testDeveloperExecutionHasNoImplicitGuess() {
        XCTAssertEqual(RuntimeEnvironment.resolveGateway(saved: "", resourceURL: nil), "")
        XCTAssertFalse(RuntimeEnvironment.missingFiles(for: "").isEmpty)
    }
}


extension RuntimeEnvironmentTests {
    func testRemoteConnectionComponentsAreRequiredInBundle() {
        let script = current.appendingPathComponent("gateway/dist/index.js").path
        for file in ["remote-auth.js", "cloudflare.js"] {
            let missing = RuntimeEnvironment.missingFiles(for: script, readable: { !$0.hasSuffix("/" + file) })
            XCTAssertEqual(missing.count, 1)
            XCTAssertTrue(missing[0].hasSuffix("/" + file))
        }
    }
}
