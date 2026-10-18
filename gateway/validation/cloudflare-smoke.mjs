import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import {
  CloudflareTunnelManager, cloudflarePublicOrigin, quickTunnelOrigin,
  cloudflareMetricsOrigin, probeCloudflareMetadata, cloudflareConfigurationFingerprints
} from '../dist/cloudflare.js';
import { configurationFingerprint } from '../dist/configuration-fingerprints.js';

const origin = 'https://sample-session.trycloudflare.com';
const issuer = 'https://auth.example.com';
const waitFor = async (predicate, label = 'condition') => {
  const until = Date.now() + 2500;
  while (!predicate()) { if (Date.now() >= until) assert.fail(`Timed out: ${label}`); await new Promise(resolve => setTimeout(resolve, 5)); }
};
const json = value => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });
const metadata = (base = origin) => ({ resource: `${base}/mcp`, authorization_servers: [issuer], scopes_supported: ['mcp:tools'] });
const quick = { action: 'run', mode: 'quick', executable: process.execPath };
const named = { ...quick, mode: 'named', tunnelID: '12345678-1234-1234-1234-123456789abc',
  credentialsFile: fileURLToPath(new URL('../package.json', import.meta.url)), publicURL: 'https://mcp.example.com' };
class MockChild extends EventEmitter {
  stdout = new PassThrough(); stderr = new PassThrough(); kills = []; ended = false;
  kill(signal) { this.kills.push(signal); if (this.ignoreTerm && signal === 'SIGTERM') return true; this.finish(null); return true; }
  finish(code = 0) { if (this.ended) return; this.ended = true; this.stdout.end(); this.stderr.end(); queueMicrotask(() => this.emit('close', code)); }
}
function harness(options = {}) {
  const events = [], launches = [], origins = [], requests = [];
  let active = options.active ?? true;
  let child;
  const manager = new CloudflareTunnelManager(19871, event => events.push(event), {
    isActive: () => active,
    expectedIssuer: () => issuer,
    expectedScopes: () => ['mcp:tools'],
    setPublicOrigin: value => { options.setPublicOrigin?.(value); origins.push(value); }
  }, {
    pollIntervalMs: 15, probeTimeoutMs: 40, doctorTimeoutMs: 60, stopTimeoutMs: 30,
    spawn: (executable, args, spawnOptions) => {
      child = new MockChild(); launches.push({ executable, args, options: spawnOptions, child });
      queueMicrotask(() => {
        if (options.spawnFailure) { child.emit('error', new Error('SECRET-SPAWN-ERROR')); child.finish(null); return; }
        child.emit('spawn'); options.onSpawn?.(child, args);
      });
      return child;
    },
    fetch: async (url, init) => {
      requests.push({ url: String(url), init });
      if (options.fetch) return options.fetch(String(url), init);
      return String(url).startsWith('http://127.0.0.1:') ? new Response(null, { status: 200 }) : json(metadata(new URL(String(url)).origin));
    }
  });
  return { manager, events, launches, origins, requests, get child() { return child; }, setActive(value) { active = value; } };
}

assert.equal(cloudflarePublicOrigin('https://mcp.example.com/'), 'https://mcp.example.com');
for (const bad of ['http://mcp.example.com', 'https://mcp.example.com/mcp', 'https://user:pass@mcp.example.com', 'https://mcp.example.com?token=secret', 'https://127.0.0.1', 'https://[::1]', 'https://mcp.local', 'https://localhost', 'https://mcp.example.com:443', 'https://mcp.example.com#x', 'https://mcp.example.com\\evil', 'https://%65xample.com', 'https://-bad.example.com']) assert.throws(() => cloudflarePublicOrigin(bad), /CLOUDFLARE_URL/);
assert.equal(quickTunnelOrigin(`2026 INF | ${origin} |`), origin);
assert.equal(quickTunnelOrigin(`${origin}/`), origin);
for (const bad of [`${origin}.evil.example`, `${origin}@evil.example`, `${origin}/secret`, `${origin}?token=x`, `${origin}:443`, `${origin}#x`, 'https://nested.foo.trycloudflare.com', 'https://-bad.trycloudflare.com', 'http://foo.trycloudflare.com', 'https://foo.trycloudflare.com\\evil']) assert.equal(quickTunnelOrigin(bad), undefined, bad);
assert.equal(cloudflareMetricsOrigin('2026 INF Starting metrics server on 127.0.0.1:20241/metrics'), 'http://127.0.0.1:20241');
for (const bad of ['0.0.0.0:20241', 'localhost:20241', '127.0.0.1:65536', '127.0.0.1:0', '127.0.0.1:20241/other', '127.0.0.1:20241/metrics.evil']) assert.equal(cloudflareMetricsOrigin(`Starting metrics server on ${bad}/metrics`), undefined);
console.log('PASS strict HTTPS public origins, exact Quick hostname tokens, loopback-only metrics parser');

for (const changes of [{ action: 'init' }, { executable: 'cloudflared' }, { executable: '/definitely-missing/cloudflared' }, { mode: 'remote' }, { token: 'NEVER-ACCEPT' }, { runtimeKey: 'NEVER-ACCEPT' }, { mode: 'named', credentialsFile: named.credentialsFile, publicURL: named.publicURL, tunnelID: '--token' }, { ...named, credentialsFile: 'relative.json' }, { publicURL: origin }]) {
  const h = harness(); await assert.rejects(h.manager.action({ ...quick, ...changes }), /CLOUDFLARE_/); assert.equal(h.launches.length, 0);
}
{
  const h = harness({ active: false });
  await assert.rejects(h.manager.action(quick), /CLOUDFLARE_OAUTH/); assert.equal(h.launches.length, 0);
  const pending = h.manager.action({ ...quick, action: 'doctor' });
  await waitFor(() => h.child); h.child.stdout.write('cloudflared version 2026.10.0 (built fixture)\nTOKEN=SECRET\n'); h.child.finish();
  const result = await pending;
  assert.equal(result.available, true); assert.equal(result.version, '2026.10.0');
  assert.deepEqual(h.launches[0].args, ['--version']); assert.equal(h.requests.length, 0);
  assert.equal(h.manager.snapshot()[0].available, true); assert.equal(JSON.stringify(h.events).includes('SECRET'), false);
  await assert.rejects(fs.access(h.launches[0].options.cwd));
}
{
  const h = harness({ onSpawn: child => child.finish(0) });
  const result = await h.manager.action({ ...quick, action: 'doctor' });
  assert.equal(result.available, false); assert.equal(result.errorCode, 'CLOUDFLARE_VERSION');
}
{
  const h = harness();
  const result = await h.manager.action({ ...quick, action: 'doctor' });
  assert.equal(result.available, false); assert.equal(result.errorCode, 'CLOUDFLARE_VERSION');
  assert.deepEqual(h.child.kills, ['SIGTERM']);
}
{
  const h = harness({ spawnFailure: true });
  await assert.rejects(h.manager.action(quick), /CLOUDFLARE_EXECUTABLE/);
  assert.equal(h.manager.snapshot()[0].running, false);
  assert.equal(JSON.stringify(h.events).includes('SECRET-SPAWN-ERROR'), false);
  await assert.rejects(fs.access(h.launches[0].options.cwd));
}
{
  const h = harness(); const starting = h.manager.action(quick);
  await h.manager.stopAll();
  await assert.rejects(starting, /CLOUDFLARE_CANCELLED/);
  assert.equal(h.launches.length, 0, 'A stop during asynchronous validation prevents later spawn');
}
console.log('PASS no spawn without OAuth, input/path/secret rejection, bounded --version doctor and no raw output');

{
  const h = harness();
  process.env.TUNNEL_TOKEN = 'INHERITED-SECRET'; process.env.TUNNEL_URL = 'http://danger.invalid';
  try {
    const result = await h.manager.action(quick);
    assert.equal(result.ready, false); assert.equal(h.manager.snapshot()[0].ready, false);
    const { args, options } = h.launches[0];
    assert.equal(options.shell, false); assert.equal(options.env.TUNNEL_TOKEN, undefined); assert.equal(options.env.TUNNEL_URL, undefined);
    assert.equal(options.env.HOME, options.cwd);
    assert.equal(args[args.indexOf('--url') + 1], 'http://127.0.0.1:19871');
    assert.equal(args[args.indexOf('--metrics') + 1], '127.0.0.1:0');
    assert.equal(await fs.readFile(args[args.indexOf('--config') + 1], 'utf8'), '{}\n');
    assert.equal((await fs.stat(options.cwd)).mode & 0o777, 0o700);
    assert.equal((await fs.stat(args[args.indexOf('--config') + 1])).mode & 0o777, 0o600);
    await assert.rejects(h.manager.action(quick), /CLOUDFLARE_BUSY/);
    h.child.stderr.write(`SECRET_TOKEN=DO-NOT-LOG\n| ${origin}`);
    await new Promise(resolve => setTimeout(resolve, 20)); assert.equal(h.origins.length, 0, 'Do not accept a partial URL line');
    h.child.stderr.write('.evil.example |\n');
    assert.equal(h.origins.length, 0);
    h.child.stderr.write('x'.repeat(10000) + ` ${origin}\n`);
    assert.equal(h.origins.length, 0, 'Overlong diagnostic lines are discarded');
    h.child.stderr.write(`| ${origin} |\n`);
    assert.deepEqual(h.origins, [origin]);
    assert.equal(h.manager.snapshot()[0].ready, false, 'Public URL alone is not readiness');
    h.child.stderr.write('INF Starting metrics server on 127.0.0.1:20241/metrics\n');
    await waitFor(() => h.manager.snapshot()[0].ready, 'Quick readiness');
    const status = h.manager.snapshot()[0];
    assert.equal(status.publicURL, origin); assert.equal(status.mcpURL, `${origin}/mcp`);
    assert.equal(status.developmentOnly, true); assert.equal(status.oauthVerified, false); assert.equal(status.toolCallVerified, false);
    assert.equal(status.localReady, true); assert.equal(status.publicMetadataReady, true);
    assert.equal(status.configurationFingerprintVersion, 1);
    assert.deepEqual(status.configurationFingerprints, cloudflareConfigurationFingerprints(quick, 19871));
    assert.equal(status.configurationFingerprints.publicURL, configurationFingerprint(['']));
    assert.equal(status.configurationFingerprints.endpoint, configurationFingerprint(['http://127.0.0.1:19871']));
    status.ready = false; assert.equal(h.manager.snapshot()[0].ready, true, 'Snapshots are detached');
    assert.ok(h.requests.every(r => r.init.method === 'GET' && r.init.redirect === 'manual' && r.init.signal));
    assert.ok(h.requests.every(r => r.url === 'http://127.0.0.1:20241/ready' || r.url === `${origin}/.well-known/oauth-protected-resource/mcp`));
    assert.equal(JSON.stringify(h.events).includes('DO-NOT-LOG'), false); assert.equal(JSON.stringify(h.events).includes('INHERITED-SECRET'), false);
    await h.manager.stopAll();
    assert.deepEqual(h.child.kills, ['SIGTERM']); assert.deepEqual(h.origins, [origin, undefined]);
    const stopped = h.manager.snapshot()[0];
    assert.equal(stopped.running, false); assert.equal(stopped.ready, false); assert.equal(stopped.publicURL, undefined); assert.equal(stopped.mcpURL, undefined);
    await assert.rejects(fs.access(options.cwd));
  } finally { delete process.env.TUNNEL_TOKEN; delete process.env.TUNNEL_URL; await h.manager.stopAll(); }
}
console.log('PASS managed Quick process, isolated config/environment, split-output safety, two-stage readiness, fingerprints and cleanup');

{
  let localReady = false, publicReady = false;
  const h = harness({ fetch: async url => url.startsWith('http:') ? new Response(null, { status: localReady ? 200 : 503 }) : publicReady ? json(metadata(named.publicURL)) : new Response(null, { status: 302, headers: { location: 'https://evil.example' } }) });
  try {
    await h.manager.action(named);
    const args = h.launches[0].args;
    assert.ok(args.includes('run')); assert.equal(args[args.indexOf('--credentials-file') + 1], named.credentialsFile);
    assert.equal(args.at(-1), named.tunnelID); assert.ok(!args.includes('--token')); assert.ok(!args.includes('--hostname'));
    assert.deepEqual(h.origins, [named.publicURL]);
    h.child.stderr.write('INF Starting metrics server on 127.0.0.1:20242/metrics\n');
    await waitFor(() => h.requests.length > 0);
    assert.equal(h.manager.snapshot()[0].ready, false); assert.ok(!h.requests.some(r => r.url.startsWith('https:')));
    localReady = true; await waitFor(() => h.requests.some(r => r.url.startsWith('https:')));
    assert.equal(h.manager.snapshot()[0].ready, false, 'Redirected metadata must not be ready');
    publicReady = true; await waitFor(() => h.manager.snapshot()[0].ready);
    assert.equal(h.manager.snapshot()[0].developmentOnly, false);
    publicReady = false; await waitFor(() => h.manager.snapshot()[0].ready === false, 'Readiness downgrade');
    h.setActive(false); await waitFor(() => h.manager.snapshot()[0].running === false, 'Fail closed when guard disappears');
    assert.equal(h.manager.snapshot()[0].errorCode, 'CLOUDFLARE_OAUTH');
    assert.deepEqual(h.origins, [named.publicURL, undefined]);
  } finally { await h.manager.stopAll(); }
}
{
  const h = harness({ setPublicOrigin: value => { if (value) throw new Error('private auth failure'); } });
  await assert.rejects(h.manager.action(named), /CLOUDFLARE_OAUTH/); assert.equal(h.launches.length, 0);
}
{
  const h = harness();
  await h.manager.action(quick); h.child.ignoreTerm = true;
  await h.manager.stopAll(); assert.deepEqual(h.child.kills, ['SIGTERM', 'SIGKILL']);
}
{
  const h = harness();
  await h.manager.action(quick); h.child.stderr.write('secret=DO-NOT-LOG\n'); h.child.finish(1);
  await waitFor(() => h.manager.snapshot()[0].running === false);
  assert.equal(h.manager.snapshot()[0].errorCode, 'CLOUDFLARE_FAILED'); assert.equal(JSON.stringify(h.events).includes('DO-NOT-LOG'), false);
}
{
  const h = harness();
  try {
    await h.manager.action({ ...named, publicURL: named.publicURL + '/' });
    assert.equal(h.manager.snapshot()[0].publicURL, named.publicURL);
    assert.equal(h.manager.snapshot()[0].configurationFingerprints.publicURL, configurationFingerprint([named.publicURL + '/']));
  } finally { await h.manager.stopAll(); }
}
for (const mismatch of [
  { authorization_servers: ['https://wrong-auth.example.com'] },
  { authorization_servers: [issuer + '/'] },
  { authorization_servers: [issuer, 'https://extra-auth.example.com'] },
  { scopes_supported: ['mcp:other'] },
  { scopes_supported: undefined }
]) {
  const h = harness({ fetch: async url => url.startsWith('http:') ? new Response(null, { status: 200 }) : json({ ...metadata(named.publicURL), ...mismatch }) });
  try {
    await h.manager.action(named);
    h.child.stderr.write('INF Starting metrics server on 127.0.0.1:20241/metrics\n');
    await waitFor(() => h.manager.snapshot()[0].localReady === true);
    assert.equal(h.manager.snapshot()[0].ready, false);
    assert.equal(h.manager.snapshot()[0].publicMetadataReady, false, 'Public metadata must match the configured issuer and required scopes');
  } finally { await h.manager.stopAll(); }
}
console.log('PASS named credentials-path arguments, metadata redirects rejected, readiness downgrade, fail-closed OAuth and forced stop');

{
  let called = 0;
  const probe = async response => probeCloudflareMetadata(origin, async (url, init) => { called++; assert.equal(url, `${origin}/.well-known/oauth-protected-resource/mcp`); assert.equal(init.redirect, 'manual'); assert.equal(init.headers.authorization, undefined); return response; });
  assert.equal(await probe(json(metadata())), true);
  assert.equal(await probe(json({ ...metadata(), resource: 'https://different.example.com/mcp' })), false);
  assert.equal(await probe(json({ ...metadata(), authorization_servers: [] })), false);
  assert.equal(await probe(json({ ...metadata(), authorization_servers: ['http://auth.example.com'] })), false);
  assert.equal(await probe(new Response('login page', { headers: { 'content-type': 'text/html' } })), false);
  assert.equal(await probe(new Response(null, { status: 302, headers: { location: 'http://127.0.0.1/admin' } })), false);
  await assert.rejects(probe(new Response('x'.repeat(65537), { headers: { 'content-type': 'application/json' } })), /Metadata size/);
  await assert.rejects(probe(new Response('{}', { headers: { 'content-type': 'application/json', 'content-length': '999999' } })), /Metadata size/);
  await assert.rejects(probeCloudflareMetadata('https://127.0.0.1', async () => { assert.fail('No fetch for a literal private IP'); }));
  assert.equal(called, 8);
}
{
  const h = harness({ fetch: async (_url, init) => new Promise((_resolve, reject) => {
    init.signal.addEventListener('abort', () => reject(new Error('probe timeout')), { once: true });
  }) });
  try {
    await h.manager.action(quick);
    h.child.stderr.write(`| ${origin} |\nINF Starting metrics server on 127.0.0.1:20241/metrics\n`);
    await waitFor(() => h.events.some(e => e.state === 'Waiting for bounded loopback/public OAuth metadata checks'));
    assert.equal(h.manager.snapshot()[0].ready, false);
    await h.manager.stopAll();
    const eventCount = h.events.length;
    await new Promise(resolve => setTimeout(resolve, 80)); assert.equal(h.events.length, eventCount, 'Stopped probes cannot resurrect readiness');
  } finally { await h.manager.stopAll(); }
}
{
  const expected = { issuer, scopes: ['mcp:tools', 'mcp:extra'] };
  const probe = data => probeCloudflareMetadata(origin, async () => json(data), AbortSignal.timeout(100), expected);
  assert.equal(await probe({ ...metadata(), scopes_supported: ['mcp:tools', 'mcp:extra'] }), true);
  assert.equal(await probe(metadata()), false);
  assert.equal(await probe({ ...metadata(), scopes_supported: ['mcp:tools', 'mcp:extra'], authorization_servers: ['https://other.example.com'] }), false);
}
console.log('PASS bounded public metadata, exact resource audience, no redirects or bearer secrets, timeouts and stale-probe cancellation');
console.log('Cloudflare validation used mocked processes/probes only; no real cloudflared, account, credential, public tunnel, or Mac access.');
