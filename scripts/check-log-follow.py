#!/usr/bin/env python3
"""Production log follow state and source contracts; not native SwiftUI validation."""
import os
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='onemcp-log-follow-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text('''import Foundation
var state = ServiceLogFollowState()
let a = UUID(), b = UUID(), c = UUID()
assert(state.isFollowing && state.unseenCount == 0)
state.receive(oldIDs: [], newIDs: [a])
assert(state.unseenCount == 0)
state.setFollowing(false)
state.receive(oldIDs: [a], newIDs: [a, b])
assert(!state.isFollowing && state.unseenCount == 1)
// Same-size rolling buffer still detects new arrivals and bounds unread IDs.
state.receive(oldIDs: [a, b], newIDs: [b, c])
assert(state.unseenCount == 2)
state.receive(oldIDs: [b, c], newIDs: [c])
assert(state.unseenCount == 1)
state.receive(oldIDs: [c], newIDs: [])
assert(state.unseenCount == 0 && !state.isFollowing)
state.receive(oldIDs: [], newIDs: [a])
state.setFollowing(true)
assert(state.isFollowing && state.unseenCount == 0)
state.setFollowing(false)
state.receive(oldIDs: [], newIDs: [a, b])
state.resetUnread()
assert(state.unseenCount == 0 && !state.isFollowing)
print("PASS log follow state: arrivals, rollover, clear, explicit resume, filter reset")
''')
    subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-module-cache-path', str(path / 'modules'),
        str(root / 'Sources/MCPHarbor/ServiceLogFollowState.swift'), str(path / 'main.swift'),
        '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)
view = (root / 'Sources/MCPHarbor/ServiceLogView.swift').read_text()
assert 'phase == .interacting' in view
assert 'onChange(of: ServiceLogDisplaySnapshot' in view
assert 'old.errorsOnly != new.errorsOnly' in view
# Counter observation must survive the conditional ScrollViewReader's removal.
reader_tail = view.index('onChange(of: follow.isFollowing)')
assert view.index('onChange(of: ServiceLogDisplaySnapshot') > reader_tail
assert 'Observe outside the nonempty branch' in view
assert '.keyboardShortcut(.cancelAction)' in view
assert '.accessibilityHint(' in view
assert '.textSelection(.enabled)' in view
assert 'withAnimation' not in view
print('PASS source integration contracts (not native UI validation)')
