import XCTest
import Darwin
@testable import MCPHarbor

final class ReadOnlyLaunchTests: XCTestCase {
    @MainActor func testLiveWriterDoesNotBlockReadOnlyLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        let bytes = try JSONEncoder().encode(Preferences())
        try bytes.write(to: file)
        let lock = root.appendingPathComponent(".configuration-lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        let owner = try JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "token": "foreign-writer"])
        try owner.write(to: lock.appendingPathComponent("owner.json"))
        let store = HarborStore(configurationFileURL: file, startWatcher: false)
        XCTAssertTrue(store.initialConfigurationLoaded)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.configurationLeaseToken)
        XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try Data(contentsOf: lock.appendingPathComponent("owner.json")), owner)
    }
    @MainActor func testMalformedConfigIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json"), bytes = Data("broken".utf8)
        try bytes.write(to: file)
        let store = HarborStore(configurationFileURL: file, startWatcher: false)
        XCTAssertFalse(store.initialConfigurationLoaded)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testMissingFirstLaunchCreatesNothingUntilSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HarborStore(configurationFileURL: root.appendingPathComponent("settings.json"), startWatcher: false)
        XCTAssertTrue(store.initialConfigurationLoaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(store.save())
        XCTAssertEqual(store.currentWorkspaceID, "default")
        XCTAssertNil(store.configurationLeaseToken)
    }
}
