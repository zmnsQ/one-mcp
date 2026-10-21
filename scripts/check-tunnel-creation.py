#!/usr/bin/env python3
"""Production Foundation state tests + source contracts. Not native UI/Keychain QA."""
from pathlib import Path
import os, subprocess, tempfile, unittest
ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'Sources/MCPHarbor'

class CreationTests(unittest.TestCase):
    def test_save_precedes_one_init_and_never_starts(self):
        view = (SRC / 'TunnelRecordsView.swift').read_text()
        save = view.split('private func save(initialize:')[1].split('private func cloudflare<Value>')[0]
        self.assertLess(save.index('guard store.save()'), save.index('store.tunnelAction("init"'))
        self.assertIn('persistConfiguration: false', save)
        self.assertIn('session.isNew && savedDraft == nil', save)
        self.assertIn('savedDraft = record', save)
        self.assertNotIn('tunnelAction("run"', save)
        self.assertIn('guard !busy, !contextChanged', save)
        self.assertIn('创建并保存本地 Profile', view)
        self.assertNotIn('Button("创建 Profile")', view)
        self.assertNotIn('保存后可在编辑中配置密钥', view)
        self.assertIn('_createProfile = State(initialValue: session.isNew)', view)
        self.assertIn('store.clearRecordTunnelKeyForAccountChange(recordID)', save)
        self.assertIn('store.setRecordTunnelKey(', save)

    def test_credential_controls_remain_above_optional_maintenance(self):
        view = (SRC / 'TunnelRecordsView.swift').read_text()
        config = view.split('private var configuration: some View')[1].split('private var knownAccounts')[0]
        self.assertLess(config.index('accountConfiguration'), config.index('DisclosureGroup("高级设置")'))
        self.assertIn('reusableCredentialRecords(for:', view)
        self.assertIn('associateRecordCredentialWithAccount(recordID)', view)
        self.assertIn('runtimeKey = ""', view.split('private func selectAccount')[1].split('private var openAIConfiguration')[0])

    def test_actual_production_states(self):
        source = (SRC / 'TunnelProfileCreation.swift').read_text()
        checks = '''
precondition(TunnelProfileCreation.correlatedEvent(["action":"init", "exitCode":0, "operationID":"old"], operationID:"current") == nil)
precondition(TunnelProfileCreation.correlatedEvent(["action":"init", "exitCode":0], operationID:"current") == nil)
precondition(TunnelProfileCreation.correlatedEvent(["action":"init", "exitCode":0, "operationID":"current"], operationID:"current") == .succeeded)
precondition(TunnelProfileCreation.submitted.isInFlight)
precondition(TunnelProfileCreation.running.isInFlight)
for state: TunnelProfileCreation in [.succeeded, .failed, .unknown] { precondition(!state.isInFlight) }
precondition(TunnelProfileCreation.event(["action":"doctor", "exitCode":0]) == nil)
precondition(TunnelProfileCreation.event(["action":"init", "running":true]) == .running)
precondition(TunnelProfileCreation.event(["action":"init", "running":false, "exitCode":0]) == .succeeded)
precondition(TunnelProfileCreation.event(["action":"init", "exitCode":1]) == .failed)
precondition(TunnelProfileCreation.event(["action":"init", "exitCode":NSNull(), "errorCode":"TUNNEL_FAILED"]) == .failed)
precondition(TunnelProfileCreation.event(["action":"init", "running":false]) == .unknown)
precondition(TunnelProfileCreation.succeeded.message.contains("尚未启动"))
print("PASS: production Profile creation states; submission is not success")
'''
        with tempfile.TemporaryDirectory(prefix='onemcp-profile-state-') as tmp:
            path = Path(tmp)
            (path / 'main.swift').write_text(source + checks)
            subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-module-cache-path', str(path/'modules'), str(path/'main.swift'), '-o', str(path/'check')], check=True)
            subprocess.run([str(path/'check')], check=True)

if __name__ == '__main__': unittest.main(verbosity=2)
