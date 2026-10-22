import XCTest
@testable import MCPHarbor

final class ActivityPolicyTests: XCTestCase {
    func testDiffDescribesChangesWithoutCommandsOrSecrets() {
        var old = Preferences(), new = Preferences()
        var server = ServerConfig(); server.id = "service"; server.name = "Browser"; old.servers = [server]
        server.executable = "/private/command"; server.arguments = ["--token", "secret-value"]
        server.allowedTools = ["one", "two"]; new.servers = [server]
        let changes = ActivityPolicy.configurationChanges(from: old, to: new)
        XCTAssertTrue(changes.contains { $0.0 == "修改工具选择" && $0.2.joined().contains("新增开放 2 项") })
        let text = String(describing: changes)
        XCTAssertFalse(text.contains("secret-value")); XCTAssertFalse(text.contains("/private/command"))
    }
    func testUnsafeLabelIsNotDisplayed() {
        for label in ["token=private", "curl https://private/path", "sk-private", "hello\nworld", "/private/path"] {
            XCTAssertEqual(ActivityPolicy.label(label, fallback: "服务"), "服务")
        }
        XCTAssertEqual(ActivityPolicy.label("浏览器 MCP", fallback: "服务"), "浏览器 MCP")
    }
    func testBoundedDeduplicatedJournal() {
        var records: [ActivityRecord] = []
        for i in 0..<100 {
            let item = ActivityRecord(id: String(i), time: Date(), source: .external, action: "修改配置", object: "服务", outcome: .saved, details: [])
            ActivityPolicy.append(item, to: &records); ActivityPolicy.append(item, to: &records)
        }
        XCTAssertEqual(records.count, 80); XCTAssertEqual(records.first?.id, "99")
        XCTAssertEqual(records.first?.source, .external)
        XCTAssertNotEqual(ActivityOutcome.saved, .applied)
    }
}
