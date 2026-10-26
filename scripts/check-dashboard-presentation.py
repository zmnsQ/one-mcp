#!/usr/bin/env python3
"""Linux-compatible presentation smoke check; NOT a native SwiftUI/AppKit test.

Compiles the Foundation-only status enum directly from the production source.
Set SWIFTC to a compatible compiler path. Native image/view tests still require macOS.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = (root / 'Sources/MCPHarbor/MenuBarStatus.swift').read_text()
enum_source, boundary, _ = source.partition('@MainActor extension HarborStore')
assert boundary, 'Status source changed: review this smoke harness'
checks = '''
precondition(MenuBarStatus.gateway("Disconnected") == .unknown)
precondition(MenuBarStatus.gateway("Stopped") == .stopped)
precondition(MenuBarStatus.gateway("Stopped (exit 1)") == .failed)
precondition(MenuBarStatus.server("starting") == .starting)
precondition(MenuBarStatus.server("unexpected") == .unknown)
precondition(MenuBarStatus.tunnel(event: [:]) == .unknown)
precondition(MenuBarStatus.tunnel(event: ["running": true, "ready": false]) == .running)
precondition(MenuBarStatus.tunnel(event: ["running": true, "ready": true]) == .ready)
precondition(MenuBarStatus.tunnel(event: ["running": true, "action": "doctor"]) == .checking)
precondition(MenuBarStatus.tunnel(event: ["running": false, "errorCode": "failed"]) == .failed)
precondition(MenuBarStatus.unknown.title != MenuBarStatus.stopped.title)
precondition(MenuBarStatus.unknown.symbol != MenuBarStatus.stopped.symbol)
print("PASS: 12 production status assertions (not native UI validation)")
'''
with tempfile.TemporaryDirectory(prefix='onemcp-presentation-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(enum_source + checks)
    subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-module-cache-path', str(path / 'modules'), str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)

# Compact overview projects existing runtime state; full editing stays in the tunnel page.
dashboard = (root / 'Sources/MCPHarbor/OverviewDashboard.swift').read_text()
assert 'TunnelRecordsView()' not in dashboard
assert 'private var dashboardLayout: AnyLayout' in dashboard
assert 'AnyLayout(HStackLayout' in dashboard and 'AnyLayout(VStackLayout' in dashboard
assert '0.66' in dashboard
assert 'store.menuTunnelIDs.prefix(3)' in dashboard
assert 'store.activities.prefix(3)' in dashboard
assert 'record.summary' in dashboard and 'record.time' in dashboard
assert 'action: onOpenTunnels' in dashboard
assert 'expectedPlan: plan, expectedWorkspace: workspace, expectedRevision: revision' in dashboard
assert 'confirm(store.startAllConfirmation)' in dashboard
assert 'confirm("停止共享网关及全部连接？' in dashboard
assert 'guard workspace == store.currentWorkspaceID, store.preferences.servers.contains(server)' in dashboard
assert '.disabled(busy || !store.gatewayReady || status == .unknown)' in dashboard
assert 'height: 56' in dashboard
assert 'width: 92' not in dashboard
print('PASS compact hero, single adaptive layout, runtime summaries, real activities and guarded actions (source contract only)')
