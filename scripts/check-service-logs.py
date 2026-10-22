#!/usr/bin/env python3
"""Run the production Foundation-only log buffer's XCTest cases on Linux/macOS.

Set SWIFTC to the compiler path. This does not typecheck or run native SwiftUI.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
names = [
    'testExactIDsAndIndependentBounds',
    'testNeverCopiesUntrustedTextOrSecrets',
    'testFailureCategoriesAndGlobalBound',
    'testLifecycleAndSafeDiagnostics',
    'testSnapshotReplayAcrossReconnectAndClear',
]
with tempfile.TemporaryDirectory(prefix='onemcp-service-logs-') as directory:
    path = Path(directory)
    tests = (root / 'Tests/MCPHarborTests/ServiceLogTests.swift').read_text()
    (path / 'Tests.swift').write_text(tests.replace('@testable import MCPHarbor', ''))
    cases = ',\n'.join(f'("{name}", ServiceLogTests.{name})' for name in names)
    (path / 'main.swift').write_text('import XCTest\nXCTMain([testCase([\n' + cases + '\n])])\n')
    subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-module-cache-path', str(path / 'modules'),
                    str(root / 'Sources/MCPHarbor/ServiceLog.swift'), str(path / 'Tests.swift'),
                    str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)

view = (root / 'Sources/MCPHarbor/ServiceLogView.swift').read_text()
shared = (root / 'Sources/MCPHarbor/SharedRuntime.swift').read_text()
store = (root / 'Sources/MCPHarbor/HarborStore.swift').read_text()
assert 'serviceLogs.lines(for: server.id)' in view
assert 'recordServiceLogSnapshotEvent(event, instanceID: instanceID, sequence: sequence)' in shared and 'recordServiceLogEvent(event)' in store
assert 'serverId' in (root / 'Sources/MCPHarbor/ServiceLog.swift').read_text()
print('PASS service log model XCTest and source integration contracts (not native UI validation)')
