#!/usr/bin/env python3
"""Source-level UI regressions only; not a SwiftUI build or visual/interaction test."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "Sources/MCPHarbor/HarborView.swift").read_text()
tools = (root / "Sources/MCPHarbor/ToolSelectionView.swift").read_text()
process = (root / "Sources/MCPHarbor/ProcessConfigurationView.swift").read_text()
menu = (root / "Sources/MCPHarbor/MenuBarPanel.swift").read_text()
assert 'DisclosureGroup("允许使用的工具' not in view
assert view.index('ToolSelectionView(server:') < view.index('ProcessConfigurationView(server:')
assert 'Text(tool.name)' in tools and 'tool.description' in tools and 'Toggle(isOn: $selected)' in tools
assert 'TextField("搜索工具名称或用途"' in tools
assert 'runtime.permissionsKnown' in tools
assert '保存并应用工具选择' in tools and '保存工具选择' in tools
assert '.disabled(running)' not in tools
assert '["starting", "stopping"].contains' in tools
assert 'confirm(message)' in tools
for guard in ('store.currentWorkspaceID == workspace', 'store.savedRevision == revision',
              'Set(currentDraft.allowedTools) == confirmedSelection', 'currentLive == confirmedLive'):
    assert guard in tools, guard
assert 'store.applyToolSelection(id)' in tools
assert 'Toggle' not in process  # Process options must not conflate permission switches.
assert '.disabled(locked)' in process and 'DisclosureGroup("启动参数' in process
assert '.frame(height: statusListHeight)' in menu
assert menu.index('statusSection("隧道"') < menu.index('statusSection("MCP 服务"')
print('PASS tool cards, draft/apply guards, layered process fields, fixed tray viewport (source checks only)')
