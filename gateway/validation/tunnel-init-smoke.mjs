import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {TunnelManager} from '../dist/tunnels.js';

// Only this local fixture is executed. No real tunnel, credentials or network.
const root = await fs.mkdtemp(path.join(os.tmpdir(), 'onemcp-init-'));
const directory = path.join(root, 'profiles');
const executable = path.join(root, 'fixture.mjs');
const capture = path.join(root, 'calls.jsonl');
const savedEnvironment = Object.fromEntries(['HOME', 'XDG_CONFIG_HOME', 'TUNNEL_CLIENT_PROFILE_DIR'].map(key => [key, process.env[key]]));
const events = [];
const manager = new TunnelManager(19881, event => events.push(event), () => true);
const target = (profile, change = {}) => ({key: profile, action: 'init', executable, profile, tunnelID: `tunnel_${profile}`, runtimeKey: '', ...change});
const calls = async () => {
  try { return (await fs.readFile(capture, 'utf8')).trim().split('\n').filter(Boolean).map(line => JSON.parse(line)); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
};
async function waitFor(test) {
  for (let i = 0; i < 300; i++) { const result = await test(); if (result) return result; await new Promise(resolve => setTimeout(resolve, 10)); }
  assert.fail('Timed out waiting for local fixture');
}
const terminal = (key, start = 0) => waitFor(() => events.slice(start).find(event => event.key === key && event.type === 'tunnelStatus' && 'exitCode' in event));
const rejects = (value, code) => assert.rejects(value, new RegExp(`\\[${code}\\]`));
async function withGate(method, predicate, exercise) {
  const original = fs[method];
  let enter, release, blocked = false;
  const entered = new Promise(resolve => { enter = resolve; });
  const released = new Promise(resolve => { release = resolve; });
  fs[method] = async (...args) => {
    if (!blocked && predicate(...args)) { blocked = true; enter(); await released; }
    return original(...args);
  };
  try { await exercise({entered, release}); }
  finally { release(); fs[method] = original; }
}

try {
  await fs.mkdir(directory);
  process.env.TUNNEL_CLIENT_PROFILE_DIR = directory;
  await fs.writeFile(executable, `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2);
const value = flag => args[args.indexOf(flag) + 1];
const action = args[0];
const profile = args.includes('--profile') ? value('--profile') : path.basename(value('--profile-file'));
fs.appendFileSync(${JSON.stringify(capture)}, JSON.stringify({args, profile}) + '\\n');
if (action === 'run') { process.on('SIGTERM', () => process.exit(0)); setInterval(() => {}, 1000); }
else if (action === 'init') {
  if (profile === 'fail_without_file') process.exit(1);
  const directory = process.env.TUNNEL_CLIENT_PROFILE_DIR || (process.env.XDG_CONFIG_HOME ? path.join(process.env.XDG_CONFIG_HOME, 'tunnel-client') : path.join(process.env.HOME, '.config', 'tunnel-client'));
  fs.mkdirSync(directory, {recursive: true});
  fs.writeFileSync(path.join(directory, profile + '.yaml'), 'mock profile for ' + profile + '\\n');
  process.exit(profile === 'uncertain' ? 1 : 0);
}
`, {mode: 0o700});

  const existing = path.join(directory, 'existing.yaml');
  const originalContent = 'existing configuration must remain unchanged\n';
  await fs.writeFile(existing, originalContent);
  await rejects(manager.action(target('existing')), 'TUNNEL_EXISTING_INIT');
  assert.equal(await fs.readFile(existing, 'utf8'), originalContent);
  await fs.mkdir(path.join(directory, 'directory.yaml'));
  await rejects(manager.action(target('directory')), 'TUNNEL_EXISTING_INIT');
  await fs.symlink(path.join(root, 'missing'), path.join(directory, 'broken.yaml'));
  await rejects(manager.action(target('broken')), 'TUNNEL_EXISTING_INIT');
  assert.equal((await calls()).length, 0);
  assert.equal(events.some(event => event.exitCode === 0), false);
  console.log('PASS named init refuses existing files, directories and broken links without spawning or claiming success');

  const originalLstat = fs.lstat;
  fs.lstat = async (...args) => {
    if (args[0] === path.join(directory, 'inaccessible.yaml')) throw Object.assign(new Error('mock EACCES'), {code: 'EACCES'});
    return originalLstat(...args);
  };
  try { await rejects(manager.action(target('inaccessible')), 'TUNNEL_PROFILE_CHECK'); }
  finally { fs.lstat = originalLstat; }
  delete process.env.HOME; delete process.env.XDG_CONFIG_HOME; delete process.env.TUNNEL_CLIENT_PROFILE_DIR;
  await rejects(manager.action(target('unknown_location')), 'TUNNEL_PROFILE_CHECK');
  process.env.TUNNEL_CLIENT_PROFILE_DIR = directory;
  if (savedEnvironment.HOME !== undefined) process.env.HOME = savedEnvironment.HOME;
  assert.equal((await calls()).length, 0);
  console.log('PASS inaccessible or indeterminate profile locations fail closed');

  for (const operationID of ['', 'not-a-uuid', 'a'.repeat(65), null, 42]) {
    await rejects(manager.action(target('invalid_operation', {operationID})), 'TUNNEL_TARGET');
  }
  assert.equal((await calls()).length, 0);

  await withGate('access', file => file === executable, async ({entered, release}) => {
    const first = manager.action(target('concurrent'));
    await entered;
    await rejects(manager.action(target('concurrent')), 'TUNNEL_BUSY');
    await rejects(manager.action(target('concurrent', {key: 'same_profile', tunnelID: 'tunnel_another'})), 'TUNNEL_DUPLICATE');
    await rejects(manager.action(target('different_profile', {key: 'same_tunnel', tunnelID: 'tunnel_concurrent'})), 'TUNNEL_DUPLICATE');
    release();
    assert.equal((await first).submitted, true);
    assert.equal((await terminal('concurrent')).exitCode, 0);
  });
  assert.equal((await calls()).filter(call => call.profile === 'concurrent').length, 1);
  assert.equal(events.filter(event => event.key === 'concurrent' && event.type === 'tunnelStatus').every(event => event.operationID === undefined), true);
  console.log('PASS synchronous reservation rejects duplicate keys, named profiles and tunnel IDs across executable-access awaits');

  const operationID = 'A06D8BF5-CF43-49A7-82B8-3152FCD03E5A';
  const fresh = target('created', {serverIDs: ['service'], operationID});
  const submitted = await manager.action(fresh);
  assert.deepEqual(submitted, {key: 'created', action: 'init', submitted: true, ready: false});
  const finished = await terminal('created');
  assert.equal(finished.exitCode, 0); assert.equal(finished.running, false); assert.equal(finished.ready, false);
  const initEvents = events.filter(event => event.key === fresh.key && event.type === 'tunnelStatus');
  assert.equal(initEvents.length, 2);
  assert.equal(initEvents.every(event => event.operationID === operationID), true);
  assert.equal(finished.signature, [executable, 'created', 'tunnel_created', 'http://127.0.0.1:19881/tunnels/created/mcp', '', 'service'].join('\n'));
  assert.deepEqual((await calls()).find(call => call.profile === 'created').args, ['init', '--profile', 'created', '--sample', 'sample_mcp_remote_no_auth', '--tunnel-id', 'tunnel_created', '--mcp-server-url', 'http://127.0.0.1:19881/tunnels/created/mcp']);
  const countAfterSuccess = (await calls()).length;
  await rejects(manager.action(fresh), 'TUNNEL_EXISTING_INIT');
  const restarted = new TunnelManager(19881, () => {}, () => true);
  await rejects(restarted.action(fresh), 'TUNNEL_EXISTING_INIT');
  assert.equal((await calls()).length, countAfterSuccess);

  await manager.action(target('uncertain'));
  assert.equal((await terminal('uncertain')).exitCode, 1);
  await rejects(manager.action(target('uncertain')), 'TUNNEL_EXISTING_INIT');
  assert.equal((await calls()).filter(call => call.profile === 'uncertain').length, 1);
  for (let attempt = 0; attempt < 2; attempt++) {
    const start = events.length;
    await manager.action(target('fail_without_file'));
    assert.equal((await terminal('fail_without_file', start)).exitCode, 1);
  }
  assert.equal((await calls()).filter(call => call.profile === 'fail_without_file').length, 2);
  await manager.action(target('inaccessible'));
  assert.equal((await terminal('inaccessible')).exitCode, 0);
  console.log('PASS optional UUID correlation on all init status events and unchanged CLI arguments; retry/restart after existing output never reinitializes; absent-output failures can retry');

  for (const source of ['XDG_CONFIG_HOME', 'HOME']) {
    delete process.env.TUNNEL_CLIENT_PROFILE_DIR;
    delete process.env.XDG_CONFIG_HOME;
    process.env.HOME = path.join(root, 'home');
    if (source === 'XDG_CONFIG_HOME') process.env.XDG_CONFIG_HOME = path.join(root, 'xdg');
    const destination = source === 'HOME' ? path.join(process.env.HOME, '.config', 'tunnel-client') : path.join(process.env.XDG_CONFIG_HOME, 'tunnel-client');
    await fs.mkdir(destination, {recursive: true});
    await fs.writeFile(path.join(destination, 'precedence.yaml'), originalContent);
    await rejects(manager.action(target('precedence')), 'TUNNEL_EXISTING_INIT');
  }
  process.env.TUNNEL_CLIENT_PROFILE_DIR = directory;
  if (savedEnvironment.HOME !== undefined) process.env.HOME = savedEnvironment.HOME;
  console.log('PASS overwrite guard follows named-profile XDG and HOME fallback locations');

  const canonical = path.join(root, 'canonical.yaml');
  const aliasOne = path.join(root, 'alias-one.yaml');
  const aliasTwo = path.join(root, 'alias-two.yaml');
  await fs.writeFile(canonical, originalContent);
  await fs.symlink(canonical, aliasOne); await fs.symlink(canonical, aliasTwo);
  const beforeAlias = (await calls()).length;
  await withGate('mkdtemp', prefix => prefix.includes('onemcp-health-'), async ({entered, release}) => {
    const first = manager.action(target('alias_one', {action: 'run', profileFile: aliasOne}));
    await entered;
    await rejects(manager.action(target('alias_two', {action: 'run', profileFile: aliasTwo})), 'TUNNEL_DUPLICATE');
    release(); await first;
    await waitFor(async () => (await calls()).length === beforeAlias + 1);
    await manager.stopAll();
  });
  assert.equal((await calls()).length, beforeAlias + 1);
  console.log('PASS explicit-file aliases remain reserved across realpath and health-folder preparation');

  const beforeStop = (await calls()).length;
  await withGate('access', file => file === executable, async ({entered, release}) => {
    const action = manager.action(target('cancelled'));
    const rejection = rejects(action, 'TUNNEL_FAILED');
    await entered;
    const stopped = manager.stopAll();
    release(); await rejection; await stopped;
  });
  assert.equal((await calls()).length, beforeStop);
  await manager.action(target('cancelled'));
  assert.equal((await terminal('cancelled')).exitCode, 0);
  console.log('PASS stopAll cancels pending preflight without launching; released reservations allow a later explicit retry');

  const beforePreparation = (await calls()).length;
  let preparedFolder;
  await withGate('chmod', folder => {
    if (!folder.includes('onemcp-health-')) return false;
    preparedFolder = folder; return true;
  }, async ({entered, release}) => {
    const action = manager.action(target('cancelled_run', {action: 'run', serverIDs: ['service']}));
    const rejection = rejects(action, 'TUNNEL_FAILED');
    await entered;
    const stopped = manager.stopForServer('service');
    release(); await rejection; await stopped;
  });
  assert.equal((await calls()).length, beforePreparation);
  await assert.rejects(fs.stat(preparedFolder), {code: 'ENOENT'});
  console.log('PASS stopping a bound server cancels pending run and removes its prepared health folder');

  const invalidExecutable = path.join(root, 'invalid-interpreter');
  await fs.writeFile(invalidExecutable, '#!/nonexistent/onemcp-test-interpreter\n', {mode: 0o700});
  await rejects(manager.action(target('spawn_failure', {executable: invalidExecutable})), 'TUNNEL_EXECUTABLE');
  const startAfterSpawnFailure = events.length;
  await manager.action(target('spawn_failure'));
  assert.equal((await terminal('spawn_failure', startAfterSpawnFailure)).exitCode, 0);
  console.log('PASS spawn failure releases reservations for a corrected explicit retry');
} finally {
  await manager.stopAll();
  for (const [key, value] of Object.entries(savedEnvironment)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
  await fs.rm(root, {recursive: true, force: true});
}
