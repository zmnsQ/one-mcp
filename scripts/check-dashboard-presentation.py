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
