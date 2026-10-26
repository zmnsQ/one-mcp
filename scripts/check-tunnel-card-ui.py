#!/usr/bin/env python3
"""Source contracts only: no native SwiftUI compilation or visual verification."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parent.parent / 'Sources/MCPHarbor/TunnelRecordsView.swift').read_text()
CARD = SOURCE.split('private func tunnelCard', 1)[1].split('private struct TunnelRecordDetails', 1)[0]

class TunnelCardUIContracts(unittest.TestCase):
    def test_runtime_is_observed_not_simulated(self):
        self.assertIn('store.menuTunnelStatus(record.id)', CARD)
        self.assertIn('store.hasPendingCommand(for: record.id)', CARD)
        self.assertNotIn('asyncAfter', CARD)
        self.assertNotIn('Task.sleep', CARD)

    def test_pending_commands_are_explained_and_block_reentry(self):
        self.assertIn('let busy = pending || store.startAllBusy', CARD)
        self.assertIn('操作已提交，等待网关确认', CARD)
        self.assertIn('.disabled(busy || status == .unknown)', CARD)
        self.assertIn('.disabled(busy || !store.gatewayReady || status == .unknown || record.serverIDs.isEmpty)', CARD)

    def test_chinese_names_and_feedback_can_wrap(self):
        self.assertIn('Text(record.name).font(.headline).lineLimit(2)', CARD)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', CARD)
        self.assertIn('尚未绑定 MCP 服务', CARD)
        self.assertIn('上次运行出现错误', CARD)

    def test_shared_surface_and_busy_label(self):
        self.assertIn('.harborSurface()', CARD)
        self.assertEqual(CARD.count('RuntimeActionLabel('), 2)

    def test_contextual_accessibility(self):
        self.assertIn('.accessibilityLabel("启动隧道', CARD)
        self.assertIn('.accessibilityLabel("停止隧道', CARD)
        self.assertIn('.accessibilityLabel("编辑隧道', CARD)

    def test_start_confirmation_snapshot_guard_is_retained(self):
        self.assertIn('startPlan == store.preferences', SOURCE)
        self.assertIn('startWorkspace == store.currentWorkspaceID', SOURCE)
        self.assertIn('startRevision == store.savedRevision', SOURCE)
        self.assertIn('startRevision = store.savedRevision; showStart = true', CARD)

if __name__ == '__main__':
    unittest.main()
