#!/usr/bin/env python3
"""Source regression contracts only. Does NOT replace a macOS build or visual QA."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parent.parent / 'Sources/MCPHarbor'
def read(name): return (ROOT / name).read_text()
class RefactorContracts(unittest.TestCase):
    def test_shared_native_surface_and_accessibility(self):
        source = read('HarborDesignSystem.swift')
        for token in ['HarborPalette.canvas', 'colorSchemeContrast', 'accessibilityReduceMotion', '.onHover', 'isEnabled', 'configuration.isPressed']:
            self.assertIn(token, source)
        self.assertNotIn('repeatForever', source)
        for name in ['OverviewDashboard.swift', 'TunnelRecordsView.swift', 'FullRowDisclosureStyle.swift']:
            self.assertIn('.harborSurface()', read(name))
    def test_runtime_feedback_never_uses_cosmetic_timeout(self):
        source = read('HarborDesignSystem.swift')
        self.assertIn('if busy', source)
        self.assertNotIn('asyncAfter', source)
        self.assertNotIn('Timer', source)
        self.assertIn('hasPendingCommand(for: server.id)', read('OverviewDashboard.swift'))
    def test_dashboard_filter_is_non_mutating_and_has_recovery(self):
        source = read('OverviewDashboard.swift')
        self.assertIn('localizedStandardContains', source)
        self.assertIn('ForEach(filteredServices)', source)
        self.assertIn('清除筛选', source)
        self.assertIn('onChange(of: store.currentWorkspaceID)', source)
        self.assertNotIn('.onSubmit', source)  # IME confirmation must not execute commands.
    def test_start_confirmation_is_preserved(self):
        source = read('OverviewDashboard.swift')
        self.assertIn('guard workspace == store.currentWorkspaceID', source)
        self.assertIn('store.preferences.servers.contains(server)', source)
        self.assertIn('ServiceStopImpact.message', source)
        self.assertIn('status == .unknown', source)
    def test_motion_is_explicit_and_reducible(self):
        for name in ['HarborView.swift', 'OverviewDashboard.swift', 'FullRowDisclosureStyle.swift']:
            source = read(name)
            self.assertIn('accessibilityReduceMotion', source)
            self.assertIn('reduceMotion ? ', source)
        self.assertIn('.numericText()', read('OverviewDashboard.swift'))
        self.assertIn('.rotationEffect', read('FullRowDisclosureStyle.swift'))
    def test_previews_do_not_write_read_only_accessibility_environment(self):
        source = read('HarborDesignPreview.swift')
        self.assertNotIn('.environment(\\.accessibilityReduceMotion', source)
        self.assertNotIn('.environment(\\.colorSchemeContrast', source)
    def test_native_focus_and_adaptive_interactive_harness(self):
        source = read('HarborDesignSystem.swift')
        source = read('HarborDesignPreview.swift')
        self.assertNotIn('.frame(width: 760)', source)
        self.assertIn('.adaptive(minimum: 280)', source)
        self.assertIn('minWidth: 360, idealWidth: 760', source)
        self.assertIn('focusedAction = .toggle', source)
        self.assertIn('preview-focus-status', source)
        self.assertIn('.focusable(true, interactions: .activate)', source)
        self.assertNotIn('asyncAfter', source)
    def test_navigation_and_status_have_nonvisual_labels(self):
        self.assertIn('.keyboardShortcut(item.shortcut', read('HarborView.swift'))
        self.assertIn('.accessibilityLabel("状态：', read('StatusPresentation.swift'))
        self.assertIn('知道了', read('HarborView.swift'))
if __name__ == '__main__': unittest.main(verbosity=2)
