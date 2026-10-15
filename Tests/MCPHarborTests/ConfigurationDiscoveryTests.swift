import Foundation
import XCTest
@testable import MCPHarbor

final class ConfigurationDiscoveryTests: XCTestCase {
    private func parse(_ json: String, seen: inout Set<String>) throws -> [ImportCandidate] {
        try ConfigurationDiscovery.candidates(data: Data(json.utf8), source: "explicitly-selected.json", seen: &seen)
    }
    func testEnvironmentValuesAreNotCopied() throws {
        var seen = Set<String>()
        let rows = try parse(#"{"mcpServers":{"one":{"command":"/bin/mock","env":{"API_KEY":"never-copy-this"}}}}"#, seen: &seen)
        let server = try XCTUnwrap(rows.first?.server)
        XCTAssertEqual(server.environmentKeys, ["API_KEY"])
        XCTAssertTrue(server.allowedTools.isEmpty)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(server), as: UTF8.self).contains("never-copy-this"))
        XCTAssertTrue(rows[0].canSelect)
    }
    func testDuplicateAcrossSourcesAndExistingConfiguration() throws {
        var existing = ServerConfig(); existing.executable = "/bin/mock"; existing.environmentKeys = ["API_KEY"]
        var seen: Set<String> = [ConfigurationDiscovery.fingerprint(existing)]
        let rows = try parse(#"{"mcpServers":{"renamed":{"command":"/bin/mock","env":{"API_KEY":"different-secret"}}}}"#, seen: &seen)
        XCTAssertFalse(rows[0].canSelect)
        XCTAssertNotNil(rows[0].issue)
    }
    func testVSCodeAndUnsupportedRemote() throws {
        var seen = Set<String>()
        let rows = try parse(#"{"servers":{"local":{"type":"stdio","command":"node","args":["index.js"]},"remote":{"type":"http","url":"https://example.com/mcp"}}}"#, seen: &seen)
        XCTAssertTrue(rows[0].canSelect)
        XCTAssertNotNil(rows[0].warning)
        XCTAssertFalse(rows[1].canSelect)
    }
    func testSensitiveArgumentsAreHiddenAndBlocked() throws {
        var seen = Set<String>()
        let rows = try parse(#"{"mcpServers":{"secret":{"command":"/bin/mock","args":["--api-key","sensitive-one","--token=sensitive-two","Bearer sensitive-three","https://user:sensitive-four@example.com/path","https://example.com/?token=sensitive-five"]}}}"#, seen: &seen)
        XCTAssertFalse(rows[0].canSelect)
        let preview = try XCTUnwrap(rows[0].server).arguments.joined(separator: " ")
        for value in ["sensitive-one", "sensitive-two", "sensitive-three", "sensitive-four", "sensitive-five"] { XCTAssertFalse(preview.contains(value)) }
        XCTAssertTrue(seen.isEmpty)
    }
    func testMalformedEntriesDoNotBecomeCandidates() throws {
        var seen = Set<String>()
        let rows = try parse(#"{"mcpServers":{"bad":{"command":"/bin/mock","args":"not-array"},"good":{"command":"/bin/mock"}}}"#, seen: &seen)
        XCTAssertFalse(rows[0].canSelect)
        XCTAssertTrue(rows[1].canSelect)
        XCTAssertThrowsError(try parse("not JSON", seen: &seen))
        XCTAssertThrowsError(try ConfigurationDiscovery.candidates(data: Data(repeating: 65, count: 1_048_577), source: "large", seen: &seen))
    }
    func testDuplicateOrderAndNoImplicitAllowlist() throws {
        var seen = Set<String>()
        let rows = try parse(#"{"mcpServers":{"a":{"command":"/bin/mock","allowedTools":["danger"]},"b":{"command":"/bin/mock"}}}"#, seen: &seen)
        XCTAssertTrue(rows[0].canSelect)
        XCTAssertFalse(rows[1].canSelect)
        XCTAssertEqual(rows[0].server?.allowedTools, [])
    }
}
