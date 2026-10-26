#!/usr/bin/env python3
"""A-direction source contracts. Not a substitute for a macOS render/build."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parent.parent/'Sources/MCPHarbor'
def read(n): return (R/n).read_text()
class PearlGlass(unittest.TestCase):
    def test_continuous_native_canvas(self):
        s=read('HarborDesignSystem.swift'); h=read('HarborView.swift')
        for t in ['titlebarAppearsTransparent = true', 'titleVisibility = .hidden', 'window.backgroundColor = HarborPalette.canvas', 'showsBaselineSeparator = false', '.darkAqua, .aqua']:
            self.assertIn(t,s)
        self.assertNotIn('NSApp.appearance',s)
        self.assertNotIn('styleMask',s)
        self.assertGreaterEqual(h.count('HarborCanvas()'),4)
        self.assertNotIn('Color(nsColor: .windowBackgroundColor)',h)
        header=h.split('private var header: some View')[1].split('private func approve')[0]
        self.assertNotIn('.background {',header)
    def test_single_hero_not_four_equal_surface_cards(self):
        s=read('OverviewDashboard.swift')
        self.assertIn('workspaceHero',s)
        self.assertIn('本地网关已就绪',s)
        self.assertIn('远端调用需单独验证',s)
        metric=s.split('private func metric(')[1].split('private func onboardingStep')[0]
        self.assertNotIn('.harborSurface()',metric)
    def test_shared_actions_and_semantics(self):
        s=read('SidebarRuntimeControls.swift'); t=read('MenuBarPanel.swift')
        self.assertIn('TrayActionLabel(',s)
        self.assertIn('TrayActionStyle(tint: .red)',s)
        for v in ['accessibilityReduceMotion', 'colorSchemeContrast', 'isFocused', 'busy && !reduceMotion']:
            self.assertIn(v,t)
        self.assertIn('serversExpanded = false',t)
        self.assertIn('tunnelsExpanded = false',t)
    def test_navigation_and_sheets_use_a_direction(self):
        s=read('HarborPresentationComponents.swift')
        self.assertIn('selected ? Color.white',s)
        self.assertIn('selected ? HarborPalette.selection',s)
        for n in ['ImportPreview.swift','AIManagementView.swift','ServiceLogView.swift','TunnelRecordsView.swift']:
            self.assertIn('HarborCanvas()',read(n))
if __name__=='__main__': unittest.main(verbosity=2)
