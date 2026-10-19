import XCTest
@testable import MCPHarbor

final class TunnelRecordPresentationTests: XCTestCase {
    func testSummaryIsShortAndIdentifiesMissingBindings() {
        let servers = [ServerConfig(id: "a", name: "A"), ServerConfig(id: "b", name: "B"), ServerConfig(id: "c", name: "C")]
        XCTAssertEqual(TunnelRecordPresentation.bindingSummary(TunnelRecord(serverIDs: []), servers: servers), "尚未绑定 MCP 服务")
        XCTAssertEqual(TunnelRecordPresentation.bindingSummary(TunnelRecord(serverIDs: ["a", "b", "c"]), servers: servers), "A、B 等 3 个 MCP")
        XCTAssertEqual(TunnelRecordPresentation.bindingSummary(TunnelRecord(serverIDs: ["missing"]), servers: servers), "已移除的服务")
    }
    func testDraftDoesNotModifyOriginalAndEditKeepsOtherRecords() throws {
        var original = Preferences(); original.servers = [ServerConfig(id: "a")]
        let first = TunnelRecord(id: "first", name: "First", serverIDs: ["a"])
        let second = TunnelRecord(id: "second", name: "Second", serverIDs: ["a"])
        original.tunnelRecords = [first, second]
        var draft = first; draft.name = " Edited "
        let changed = try TunnelRecordPresentation.applying(draft, isNew: false, to: original)
        XCTAssertEqual(original.tunnelRecords, [first, second])
        XCTAssertEqual(changed.tunnelRecords?.first?.name, "Edited")
        XCTAssertEqual(changed.tunnelRecords?.last, second)
    }
    func testRejectsMissingEmptyAndDuplicateBindingsAndStaleEdits() {
        var preferences = Preferences(); preferences.servers = [ServerConfig(id: "a")]; preferences.tunnelRecords = []
        for ids in [[], ["missing"], ["a", "a"]] as [[String]] {
            XCTAssertThrowsError(try TunnelRecordPresentation.applying(TunnelRecord(serverIDs: ids), isNew: true, to: preferences))
        }
        XCTAssertThrowsError(try TunnelRecordPresentation.applying(TunnelRecord(serverIDs: ["a"]), isNew: false, to: preferences))
    }
    func testNewDraftAddsOnlyOneRecordAndRejectsDuplicateIdentity() throws {
        var preferences = Preferences(); preferences.servers = [ServerConfig(id: "a")]; preferences.tunnelRecords = []
        let draft = TunnelRecord(id: "new", serverIDs: ["a"])
        let added = try TunnelRecordPresentation.applying(draft, isNew: true, to: preferences)
        XCTAssertEqual(preferences.tunnelRecords, [])
        XCTAssertEqual(added.tunnelRecords, [draft])
        XCTAssertThrowsError(try TunnelRecordPresentation.applying(draft, isNew: true, to: added))
        preferences.tunnelRecords = (0..<32).map { TunnelRecord(id: "t\($0)", serverIDs: ["a"]) }
        XCTAssertThrowsError(try TunnelRecordPresentation.applying(draft, isNew: true, to: preferences))
    }
}
