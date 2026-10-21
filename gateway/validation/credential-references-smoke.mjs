import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {defaults, preferencesSchema, configuredTunnelRecords, workspace, writeConfiguration} from '../dist/configuration.js';

const base = {id: 'saved', name: 'Saved', serverIDs: [], transport: 'openai', profile: '', tunnelID: ''};
const old = preferencesSchema.parse({...defaults(), tunnelRecords: [base]});
assert.equal(old.tunnelRecords[0].accountID, undefined);
assert.equal(old.tunnelRecords[0].credentialSourceRecordID, undefined);
const source = {...base, accountID: 'My work account'};
const reference = {...base, id: 'new', name: 'New', accountID: source.accountID, credentialSourceRecordID: source.id};
const config = {...defaults(), tunnelRecords: [source, reference]};
assert.deepEqual(preferencesSchema.parse(config), config);
assert.deepEqual(configuredTunnelRecords(config), config.tunnelRecords);
for (const invalid of [
    {...reference, accountID: ''}, {...reference, accountID: '   '},
    {...reference, accountID: 'a'.repeat(101)}, {...reference, accountID: 'work\0other'},
    {...reference, credentialSourceRecordID: ''}, {...reference, credentialSourceRecordID: '../secret'},
    {...reference, runtimeKey: 'fake-must-not-persist'}, {...reference, apiKey: 'fake-must-not-persist'}
]) assert.equal(preferencesSchema.safeParse({...defaults(), tunnelRecords: [invalid]}).success, false);

const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'onemcp-credential-reference-'));
try {
    const initial = await workspace(folder);
    await writeConfiguration(initial, config, initial.revision);
    const reloaded = await workspace(folder);
    assert.deepEqual(reloaded.config.tunnelRecords, config.tunnelRecords);
    const text = await fs.readFile(path.join(folder, 'settings.json'), 'utf8');
    assert.match(text, /credentialSourceRecordID/);
    assert.doesNotMatch(text, /runtimeKey|apiKey|fake-must-not-persist/);
} finally { await fs.rm(folder, {recursive: true, force: true}); }
console.log('PASS credential reference schema validation and persistence round-trip; no secret access or remote calls');
