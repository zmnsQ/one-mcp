import Foundation
import XCTest
@testable import MCPHarbor

final class CLIServiceTests: XCTestCase {
    func testLegacyConfigurationDecodesWithoutCLIKeys() throws {
        let data = Data(#"{"id":"legacy","name":"Legacy","executable":"/usr/bin/true","arguments":[],"workingDirectory":"","environmentKeys":[],"allowedTools":[],"tunnelID":"","profile":""}"#.utf8)
        let server = try JSONDecoder().decode(ServerConfig.self, from: data)
        XCTAssertNil(server.kind)
        XCTAssertNil(server.cli)
        XCTAssertFalse(server.isCLI)
        XCTAssertTrue(server.participatesInStartAll)
        XCTAssertNil(CLIConfigurationValidation.issue(server))
        XCTAssertNil(ConfigurationFingerprint.server(server)["kind"])
    }
    func testCLIDraftsAndLaunchValidation() throws {
        var server = ServerConfig(kind: "cli", cli: CLIServiceConfiguration(), startWithAll: false)
        XCTAssertNil(CLIConfigurationValidation.issue(server))
        XCTAssertNotNil(CLIConfigurationValidation.issue(server, requireTools: true))
        server.cli?.tools = [CLIToolDefinition(name: "inspect", description: "Inspect only", arguments: [CLIArgument(name: "format", flag: "--format", enumValues: ["json", "text"])])]
        XCTAssertNil(CLIConfigurationValidation.issue(server, requireTools: true))
        XCTAssertEqual(try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(server)), server)
        XCTAssertTrue(server.allowedTools.isEmpty)
        XCTAssertFalse(server.participatesInStartAll)
        XCTAssertEqual(server.cli?.fingerprintValues, ["30000", "65536", "1", "1", "inspect", "Inspect only", "1", "format", "string", "--format", "false", "2", "json", "text"])
        server.allowedTools = ["unknown"]
        XCTAssertNotNil(CLIConfigurationValidation.issue(server))
    }
    func testInvalidLimitsAndDuplicateFlags() {
        var server = ServerConfig(kind: "cli", cli: CLIServiceConfiguration(tools: [CLIToolDefinition(name: "run", arguments: [CLIArgument(name: "a", flag: "--same"), CLIArgument(name: "b", flag: "--same")])]))
        XCTAssertNotNil(CLIConfigurationValidation.issue(server))
        server.cli?.tools[0].arguments = [CLIArgument(name: "constructor")]
        XCTAssertNotNil(CLIConfigurationValidation.issue(server))
        server.cli?.tools[0].arguments = [CLIArgument(name: "flag", type: "boolean")]
        XCTAssertNotNil(CLIConfigurationValidation.issue(server))
        server.cli?.tools[0].arguments = []
        server.cli?.maxConcurrent = 5
        XCTAssertNotNil(CLIConfigurationValidation.issue(server))
    }
}
