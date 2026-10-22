import XCTest
@testable import MCPHarbor

final class ServiceLogTests: XCTestCase {
    func testExactIDsAndIndependentBounds() {
        var buffer = ServiceLogBuffer(limit: 2)
        buffer.ingest(["type": "serverStatus", "serverId": "a", "status": "running"], knownServerIDs: ["a", "ab"])
        for _ in 0..<5 { buffer.ingest(["type": "serviceCall", "serverId": "ab", "outcome": "started"], knownServerIDs: ["a", "ab"]) }
        buffer.ingest(["type": "serverStatus", "serverId": "same display name", "status": "running"], knownServerIDs: ["a", "ab"])
        XCTAssertEqual(buffer.lines(for: "a").count, 1)
        XCTAssertEqual(buffer.lines(for: "ab").count, 2)
        XCTAssertTrue(buffer.lines(for: "same display name").isEmpty)
        buffer.clear(serverID: "ab")
        XCTAssertEqual(buffer.lines(for: "a").count, 1)
        XCTAssertTrue(buffer.lines(for: "ab").isEmpty)
    }
    func testNeverCopiesUntrustedTextOrSecrets() {
        var buffer = ServiceLogBuffer()
        let secret = "Authorization: Basic abc123 https://example.test/?token=private-token {\"jsonrpc\":\"2.0\",\"arguments\":\"private\"}"
        buffer.ingest(["type": "log", "serverId": "a", "message": secret], knownServerIDs: ["a"])
        buffer.ingest(["type": "serverStatus", "serverId": "a", "status": "error", "message": secret, "error": secret], knownServerIDs: ["a"])
        buffer.ingest(["type": "serviceCall", "serverId": "a", "outcome": "failed", "arguments": secret, "result": secret], knownServerIDs: ["a"])
        XCTAssertEqual(buffer.lines(for: "a").count, 2)
        let text = buffer.lines(for: "a").map(\.text).joined()
        for value in ["abc123", "private-token", "Authorization", "jsonrpc", "https:"] { XCTAssertFalse(text.contains(value)) }
    }
    func testFailureCategoriesAndGlobalBound() {
        var buffer = ServiceLogBuffer()
        for reason in ["timeout", "cancelled", "tool_error", "upstream_error"] {
            buffer.ingest(["type": "serviceCall", "serverId": "a", "outcome": "failed", "reason": reason], knownServerIDs: ["a"])
        }
        XCTAssertEqual(Set(buffer.lines(for: "a").map(\.text)).count, 4)
        let ids = Set((0..<100).map { "service-\($0)" })
        for id in ids { buffer.ingest(["type": "serverStatus", "serverId": id, "status": "running"], knownServerIDs: ids) }
        XCTAssertLessThanOrEqual(buffer.entries.count, 32)
    }
    func testSnapshotReplayAcrossReconnectAndClear() {
        var buffer = ServiceLogBuffer()
        let event: [String: Any] = ["type": "serverStatus", "serverId": "a", "status": "running"]
        buffer.ingestSnapshot(event, instanceID: "gateway-a", sequence: 10, knownServerIDs: ["a"])
        buffer.ingestSnapshot(event, instanceID: "gateway-a", sequence: 10, knownServerIDs: ["a"])
        XCTAssertEqual(buffer.lines(for: "a").count, 1)
        buffer.clear(serverID: "a")
        buffer.ingestSnapshot(event, instanceID: "gateway-a", sequence: 9, knownServerIDs: ["a"])
        buffer.ingestSnapshot(event, instanceID: "gateway-a", sequence: 10, knownServerIDs: ["a"])
        XCTAssertTrue(buffer.lines(for: "a").isEmpty)
        buffer.ingestSnapshot(event, instanceID: "gateway-a", sequence: 11, knownServerIDs: ["a"])
        buffer.ingestSnapshot(event, instanceID: "gateway-b", sequence: 1, knownServerIDs: ["a"])
        XCTAssertEqual(buffer.lines(for: "a").count, 2)
        buffer = ServiceLogBuffer()
        buffer.ingestSnapshot(event, instanceID: "gateway-a", sequence: 10, knownServerIDs: ["a"])
        XCTAssertEqual(buffer.lines(for: "a").count, 1)
    }
    func testLifecycleAndSafeDiagnostics() {
        var buffer = ServiceLogBuffer()
        for status in ["starting", "running", "stopped", "error"] {
            buffer.ingest(["type": "serverStatus", "serverId": "a", "status": status], knownServerIDs: ["a"])
        }
        buffer.ingest(["type": "log", "serverId": "a", "message": "Upstream stderr received; hidden to protect credentials"], knownServerIDs: ["a"])
        XCTAssertEqual(buffer.lines(for: "a").count, 5)
        XCTAssertTrue(buffer.lines(for: "a").last!.text.contains("原文已隐藏"))
        buffer.retain(serverIDs: [])
        XCTAssertTrue(buffer.entries.isEmpty)
    }
}
