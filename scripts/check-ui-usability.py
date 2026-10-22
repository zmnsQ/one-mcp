#!/usr/bin/env python3
"""Lightweight source-contract + production-model tests, NOT native UI testing.

No SwiftPM build, network, gateway processes, credentials or Actions are used.
Run with SWIFTC=/path/to/swiftc python3 scripts/check-ui-usability.py.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'Sources/MCPHarbor'

def read(name):
    return (SRC / name).read_text()

class UIContractTests(unittest.TestCase):
    def test_static_status_is_not_a_disabled_native_menu_item(self):
        app = read('MCPHarborApp.swift')
        self.assertIn('.menuBarExtraStyle(.window)', app)
        self.assertIn('MenuBarPanel().environmentObject(store)', app)
        row = read('MenuBarPanel.swift').split('struct MenuStatusRow: View')[1]
        self.assertNotIn('.disabled(', row)
        self.assertNotIn('Button', row)
        self.assertIn('.foregroundStyle(.primary)', row)
        self.assertIn('size: 13', row)
        self.assertIn('Text(status.title)', row)
        self.assertIn('status.symbol', row)
        self.assertIn('status.color', row)
        self.assertIn('.accessibilityLabel(', row)

    def test_single_main_window_is_reopened_by_identity(self):
        self.assertIn('Window("One MCP", id: "main")', read('MCPHarborApp.swift'))
        self.assertIn('openWindow(id: "main")', read('MenuBarPanel.swift'))
        self.assertNotIn('NSApp.windows.first', read('MenuBarPanel.swift'))

    def test_scroll_bounds_long_menu_lists(self):
        menu = read('MenuBarPanel.swift')
        self.assertIn('ScrollView {', menu)
        self.assertIn('.frame(height: statusListHeight)', menu)
        self.assertIn('min(320, 112 + 36 *', menu)
        self.assertNotIn('就绪不代表', menu)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', menu)

    def test_expanded_controls_are_outside_header_button(self):
        style = read('FullRowDisclosureStyle.swift')
        body, header = style.split('private struct DisclosureHeader', 1)
        self.assertIn('DisclosureHeader(isExpanded: Binding(', body)
        self.assertIn('if configuration.isExpanded {', body)
        self.assertIn('configuration.content', body)
        self.assertNotIn('configuration.content', header)
        self.assertNotIn('onTapGesture', style)
        self.assertNotIn('highPriorityGesture', style)
        self.assertNotIn('simultaneousGesture', style)

    def test_header_hit_area_keyboard_and_focus_contract(self):
        style = read('FullRowDisclosureStyle.swift')
        self.assertIn('minHeight: 44', style)
        self.assertIn('.contentShape(Rectangle())', style)
        self.assertIn('.focused($isFocused)', style)
        self.assertIn('.stroke(isFocused ? Color.accentColor', style)
        self.assertIn('.accessibilityValue(isExpanded ?', style)
        self.assertIn('.onKeyPress(.rightArrow)', style)
        self.assertIn('.onKeyPress(.leftArrow)', style)
        self.assertIn('isExpanded.toggle()', style)

    def test_shared_style_is_applied_at_view_root(self):
        view = read('HarborView.swift')
        body = view.split('private var header:')[0]
        self.assertIn('.disclosureGroupStyle(FullRowDisclosureStyle())', body)

    def test_bulk_controls_and_result_list_are_not_page_headers(self):
        view = read('HarborView.swift')
        self.assertEqual(view.count('SidebarRuntimeControls('), 1)
        self.assertNotIn('store.startAllSteps', view)
        header = view.split('private var header:')[1].split('private func approve')[0]
        self.assertNotIn('store.startAll(', header)
        self.assertNotIn('store.stopGateway()', header)
        sidebar = read('SidebarRuntimeControls.swift')
        self.assertIn('.sheet(isPresented: $showDetails)', sidebar)
        self.assertIn('failedSteps > 0', sidebar)
        self.assertIn('summary.failureCount > 0', sidebar)
        self.assertIn('store.cancelStartAll()', sidebar)
        self.assertIn('上次全部启动结果', sidebar)

    def test_sidebar_controls_keep_confirmation_and_snapshot_guards(self):
        sidebar = read('SidebarRuntimeControls.swift')
        self.assertIn('confirm(store.startAllConfirmation)', sidebar)
        self.assertIn('expectedPlan: plan, expectedWorkspace: workspace, expectedRevision: revision', sidebar)
        self.assertIn('confirm("停止共享网关及全部连接？', sidebar)
        self.assertIn('store.shutdown()', sidebar)
        self.assertIn('store.hasUnsavedChanges', sidebar)
        self.assertIn('ViewThatFits(in: .horizontal)', sidebar)
        self.assertIn('VStack(alignment: .leading, spacing: 8) { startAllButton; stopAllButton }', sidebar)

    def test_all_settings_and_safety_guards_remain(self):
        view = read('HarborView.swift')
        for operation in ['repairEnvironment()', 'choosePath("node")', 'choosePath("gateway")',
                          'checkSetup()', 'saveCredentialsToKeychain()', 'loadCredentialsFromKeychain()',
                          'deleteSavedCredentials()', 'exportConfiguration()', 'importConfiguration()',
                          'exportToolGuide()', 'exportLogs()', 'stopTunnel(key)',
                          'ServiceStopImpact.message(name: server.name)', 'AIManagementAccessView()',
                          'EnvironmentDiscoveryView()', 'CLIServiceEditor(']:
            self.assertIn(operation, view)
        self.assertIn('.disabled(store.anyProcessRunning || store.discoveryBusy)', view)
        self.assertIn('.padding(12).disabled(store.isGatewayRunning)', view)
        self.assertIn('approve("恢复备份将替换当前工作空间', view)
        self.assertIn('approve("删除此工作空间全部已存 Keychain', view)
        self.assertIn('approve("将当前工作空间已输入', view)

    def test_diagnostics_shortcut_expands_both_ancestors(self):
        view = read('HarborView.swift')
        self.assertIn('section = .settings; showDiagnostics = true; showLogs = true', view)
        self.assertIn('DisclosureGroup(isExpanded: $showDiagnostics)', view)
        self.assertIn('isExpanded: $showLogs', view)

    def test_semantic_palette_is_not_arbitrary_text_tint(self):
        presentation = read('StatusPresentation.swift')
        self.assertIn('switch tone', presentation)
        for tone, color in [('positive', 'Green'), ('warning', 'Orange'), ('negative', 'Red')]:
            self.assertIn(f'case .{tone}: return .system{color}', presentation)
        self.assertIn('case .neutral: return .secondaryLabelColor', presentation)

    def test_production_status_and_summary_models(self):
        models = read('MenuBarStatus.swift').split('@MainActor extension HarborStore')[0]
        steps = read('StartAll.swift').split('@MainActor extension HarborStore')[0]
        checks = '''
let positive: [MenuBarStatus] = [.running, .ready]
let warning: [MenuBarStatus] = [.starting, .checking, .stopping]
let neutral: [MenuBarStatus] = [.stopped, .unknown]
for state in positive { precondition(state.tone == .positive) }
for state in warning { precondition(state.tone == .warning) }
for state in neutral { precondition(state.tone == .neutral) }
precondition(MenuBarStatus.failed.tone == .negative)
let all: [MenuBarStatus] = positive + warning + neutral + [.failed]
for state in all { precondition(!state.title.isEmpty && !state.symbol.isEmpty) }
precondition(MenuBarStatus.stopped.symbol != MenuBarStatus.unknown.symbol)
let live = RuntimeStatusSummary(gateway: .ready, servers: [.running, .failed, .stopped], tunnels: [.ready, .starting])
precondition(live.runningServers == 1 && live.runningTunnels == 1)
precondition(live.failureCount == 1 && !live.hasUnknownStates)
let disconnected = RuntimeStatusSummary(gateway: .unknown, servers: [.unknown], tunnels: [.unknown])
precondition(disconnected.hasUnknownStates)
precondition(disconnected.activityText.contains("状态待确认"))
precondition(disconnected.runningServers == 0 && disconnected.runningTunnels == 0)
let empty = RuntimeStatusSummary(gateway: .stopped, servers: [], tunnels: [])
precondition(empty.failureCount == 0 && !empty.hasUnknownStates)
precondition(empty.activityText.contains("0/0"))
let failed = RuntimeStatusSummary(gateway: .failed, servers: [.failed], tunnels: [.failed])
precondition(failed.failureCount == 3)
for (raw, title, state): (String, String, MenuBarStatus) in [
    ("succeeded", "已完成", .ready), ("failed", "失败", .failed),
    ("starting", "启动中", .starting), ("skipped", "已跳过", .stopped),
    ("waiting", "等待中", .checking)] {
    let step = StartAllStep(id: "test", title: "Test", status: raw)
    precondition(step.statusTitle == title && step.presentationStatus == state)
}
print("PASS production status tones, summary counts/unknown states and startup-result labels")
'''
        with tempfile.TemporaryDirectory(prefix='onemcp-ui-contract-') as tmp:
            path = Path(tmp)
            (path / 'main.swift').write_text(models + steps + checks)
            subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-module-cache-path', str(path / 'modules'),
                            str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
            subprocess.run([str(path / 'check')], check=True)

if __name__ == '__main__':
    unittest.main(verbosity=2)
