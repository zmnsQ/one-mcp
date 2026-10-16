import Foundation
import XCTest
@testable import MCPHarbor

final class AIManagementPromptTests: XCTestCase {
    func testShellQuotePreservesLiteralSpecialCharacters() throws {
        for input in ["/Applications/One MCP.app/a", "/tmp/O'Brien/$HOME;echo bad`date`", "/tmp/中文/(folder)/a"] {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf %s " + AIManagementPrompt.shellQuote(input)]
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(String(decoding: output, as: UTF8.self), input)
        }
    }
    func testPromptUsesExactContextAndReadOnlyCommands() throws {
        let text = try AIManagementPrompt.build(node: "/opt/node", cli: "/Applications/One MCP.app/cli.js", root: "/Users/name/Library/Application Support/MCPHarbor", workspace: "workspace_1", skill: "/app/skills/one-mcp/SKILL.md", documentation: "/app/docs/CLI.md")
        for verb in ["status", "config validate", "servers list", "environment inspect"] {
            XCTAssertTrue(text.contains("cli.js' " + verb + " --home "))
        }
        XCTAssertTrue(text.contains("--workspace 'workspace_1' --json"))
        XCTAssertTrue(text.contains("尚未安装到你的 Agent"))
        XCTAssertTrue(text.contains("以上仅授权只读检查"))
        XCTAssertFalse(text.contains("runtimeValues"))
    }
    func testRejectsPromptInjectionContext() {
        XCTAssertThrowsError(try AIManagementPrompt.build(node: "/node\nrun evil", cli: "/cli", root: "/home", workspace: "default", skill: nil, documentation: nil))
        XCTAssertThrowsError(try AIManagementPrompt.build(node: "/node", cli: "/cli", root: "/home", workspace: "default;rm", skill: nil, documentation: nil))
        XCTAssertThrowsError(try AIManagementPrompt.build(node: "node", cli: "/cli", root: "/home", workspace: "default", skill: nil, documentation: nil))
    }
    func testDoesNotInventSkillInstallation() throws {
        let text = try AIManagementPrompt.build(node: "/node", cli: "/cli", root: "/home", workspace: "default", skill: nil, documentation: nil)
        XCTAssertTrue(text.contains("未找到随应用附带的 Skill"))
        XCTAssertFalse(text.contains("SKILL.md"))
    }
}
