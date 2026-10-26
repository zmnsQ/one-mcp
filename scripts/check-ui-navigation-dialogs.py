#!/usr/bin/env python3
"""Second-pass structural contracts. Not native rendering/type-check evidence."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parent.parent/'Sources/MCPHarbor'
def read(n): return (ROOT/n).read_text()
class PresentationArchitecture(unittest.TestCase):
    def test_sidebar_is_rebuilt_not_original_list(self):
        s=read('HarborView.swift')
        self.assertIn('private var workspaceSidebar:',s)
        self.assertIn('HarborNavigationRow(',s)
        self.assertIn('当前工作空间',s)
        self.assertIn('.navigationSplitViewColumnWidth(min: 260',s)
        self.assertNotIn('List(selection: Binding<Section?>',s)
    def test_navigation_motion_and_accessibility(self):
        s=read('HarborPresentationComponents.swift')
        for t in ['accessibilityReduceMotion','accessibilityValue(selected','@FocusState','minHeight: 54','value: selected']:
            self.assertIn(t,s)
    def test_services_are_task_first(self):
        s=read('HarborView.swift')
        self.assertIn('if servicePane == "使用与授权"',s)
        self.assertIn('serviceNextStep(server)',s)
        self.assertIn('Text("程序配置").tag("程序配置")',s)
        self.assertIn('ProcessConfigurationView(',s)
        self.assertIn('CLIServiceEditor(',s)
        self.assertIn('SecureField(key',s)
        self.assertIn('ToolSelectionView(',s)
    def test_settings_adapt_without_removing_features(self):
        s=read('HarborView.swift')
        self.assertIn('settingsConnectionColumn.frame(maxWidth: .infinity',s)
        self.assertIn('settingsSafetyColumn.frame(maxWidth: .infinity',s)
        self.assertIn('private var settingsLayout: AnyLayout',s)
        self.assertIn('.frame(maxHeight: 300)',s)
        self.assertIn('当前打开的服务不在筛选结果中',s)
        for t in ['runtimeSettingsCard','advancedSettingsCard','diagnosticSettingsCard','aiManagementSettingsCard','credentialSettingsCard','backupSettingsCard']:
            self.assertGreaterEqual(s.count(t),2)
    def test_confirmation_keeps_explicit_actions_and_stale_guard(self):
        s=read('HarborView.swift'); c=read('HarborPresentationComponents.swift')
        self.assertIn('onDismiss: { pendingAction = nil }',s)
        self.assertIn('gateway === store.gateway, bridge === store.runtimeBridge',s)
        self.assertIn('let action = pendingAction; pendingAction = nil; showConfirmation = false; action?()',s)
        self.assertIn('role: .cancel, action: onCancel',c)
        self.assertIn('Button("确认并继续", action: onContinue)',c)
        self.assertNotIn('keyboardShortcut(.defaultAction)',c)
        self.assertNotIn('Task.sleep',c)
    def test_major_sheets_use_shared_graphical_headers(self):
        for n in ['HarborView.swift','TunnelRecordsView.swift','ImportPreview.swift','ServiceLogView.swift','AIManagementView.swift','SidebarRuntimeControls.swift']:
            self.assertIn('HarborSheetHeader(',read(n),n)
    def test_tray_is_window_based_and_explicitly_confirmed(self):
        s=read('MenuBarPanel.swift')
        self.assertIn('workspaceName',s)
        self.assertIn('runtimeMetric(',s)
        self.assertIn('expectedPlan: plan, expectedWorkspace: workspace, expectedRevision: revision',s)
        self.assertIn('alert.runModal() == .alertFirstButtonReturn',s)
        self.assertIn('HarborNavigationRouter.shared.destination = "settings"',s)
        self.assertIn('.menuBarExtraStyle(.window)',read('MCPHarborApp.swift'))
        router=read('HarborNavigationRouter.swift')
        self.assertNotIn('HarborStore',router)
        self.assertNotIn('startAll(',router)
        self.assertIn('.onReceive(navigationRouter.$destination)',read('HarborView.swift'))
    def test_tray_lists_start_collapsed_and_actions_are_large(self):
        s=read('MenuBarPanel.swift')
        for t in ['serversExpanded = false', 'tunnelsExpanded = false',
                  'DisclosureGroup(isExpanded: expanded)', 'FullRowDisclosureStyle()',
                  'serversExpanded ? 12', 'tunnelsExpanded ? 12',
                  'var height: CGFloat = 90', 'TrayActionStyle(tint: .red)',
                  'store.menuGatewayStatus == .stopping', '.disabled(stopping ||',
                  'store.gatewayStartBusy || stopping', 'accessibilityReduceMotion']:
            self.assertIn(t,s)
        self.assertEqual(s.count('Button(role: .destructive) { confirmStop() }'), 1)
        self.assertEqual(s.count('Button { confirmStart() }'), 1)
    def test_tunnel_advanced_setup_is_still_reachable(self):
        s=read('HarborView.swift')
        for t in ['连接帮助与高级维护','RemoteConnectionSettingsView()','TunnelOnboardingGuide()','MCPRequestTracePanel()']:
            self.assertIn(t,s)
if __name__=='__main__': unittest.main(verbosity=2)
