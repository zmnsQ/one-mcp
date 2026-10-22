#!/usr/bin/env python3
"""Source-level safety/integration checks runnable without the macOS SDK."""
from pathlib import Path
import unittest
import os, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
class ActivityPresentationTests(unittest.TestCase):
    def read(self, name): return (ROOT / 'Sources/MCPHarbor' / name).read_text()
    def test_sidebar_owns_activity(self):
        self.assertIn('SidebarActivityView(confirm: confirm)', self.read('SidebarRuntimeControls.swift'))
        self.assertNotIn('if let notice = store.notice', self.read('HarborView.swift'))
        self.assertIn('DisclosureGroup', self.read('SidebarActivityView.swift'))
    def test_external_source_is_not_inferred_ai(self):
        text = self.read('ConfigurationCooperation.swift')
        self.assertNotIn('AI 已更新', text)
        self.assertIn('source: .external', text)
        self.assertIn('recordConfigurationActivity(from: savedPreferences', text)
    def test_events_are_bounded_and_payload_free(self):
        text = self.read('ActivityRecord.swift')
        self.assertIn('static let limit = 80', text)
        self.assertIn('records.contains(where:', text)
        journal = self.read('ActivityJournal.swift')
        self.assertNotIn('event["error"]', journal)
        self.assertNotIn('params[', journal)
        self.assertIn('method == "updateAllowedTools"', journal)
        self.assertNotIn('Text(store.notice', self.read('SidebarActivityView.swift'))
    def test_real_swift_policy(self):
        harness = r'''import Foundation
var old = Preferences(), new = Preferences()
var server = ServerConfig(); server.id = "one"; server.name = "Browser"; old.servers = [server]
server.arguments = ["--token", "SECRET_VALUE"]; server.allowedTools = ["first", "second"]; new.servers = [server]
let changes = ActivityPolicy.configurationChanges(from: old, to: new)
precondition(changes.count == 2)
precondition(changes[0].0 == "修改工具选择")
precondition(!String(describing: changes).contains("SECRET_VALUE"))
precondition(ActivityPolicy.label("curl https://private/path", fallback: "safe") == "safe")
precondition(ActivityPolicy.label("浏览器 MCP", fallback: "safe") == "浏览器 MCP")
var records: [ActivityRecord] = []
for i in 0..<100 {
 let item = ActivityRecord(id: String(i), time: Date(), source: .external, action: "修改", object: "服务", outcome: .saved, details: [])
 ActivityPolicy.append(item, to: &records); ActivityPolicy.append(item, to: &records)
}
precondition(ActivityPolicy.noticeDetail("工具目录较大，界面已省略部分元数据或目录。运行中的工具及白名单未改变；请勿依据不完整目录重新设置权限。").contains("请勿依据不完整目录"))
precondition(ActivityPolicy.noticeDetail("已明确保存 3 项凭据到此工作空间的 macOS Keychain。").contains("3 项凭据"))
precondition(!ActivityPolicy.noticeDetail("secret=PRIVATE /private/command").contains("PRIVATE"))
precondition(records.count == 80 && records.first?.id == "99")
precondition(records.first?.source == .external && records.first?.outcome == .saved)
print("Activity policies passed")
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'main.swift').write_text(harness)
            subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-module-cache-path', str(path / 'cache'),
                str(ROOT / 'Sources/MCPHarbor/Models.swift'), str(ROOT / 'Sources/MCPHarbor/ActivityRecord.swift'),
                str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
            subprocess.run([str(path / 'check')], check=True)
    def test_store_records_save_and_ack(self):
        text = self.read('HarborStore.swift')
        self.assertIn('var activities:', text)
        self.assertIn('recordConfigurationActivity(', text)
        self.assertIn('recordCommandActivity(', text)
if __name__ == '__main__': unittest.main()
