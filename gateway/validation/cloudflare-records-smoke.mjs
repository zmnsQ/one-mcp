import assert from 'node:assert/strict';
import http from 'node:http';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { configurationFingerprint } from '../dist/configuration-fingerprints.js';
import { createCloudflareRecordProxy, CloudflareRecordPool, cloudflareRecordKey } from '../dist/cloudflare-records.js';

const seen = [];
const gateway = http.createServer((req, res) => {
  seen.push({ path: req.url, host: req.headers.host, authorization: req.headers.authorization, forwarded: req.headers['x-forwarded-host'] });
  let body = ''; req.on('data', chunk => { body += chunk; });
  req.on('end', () => { res.setHeader('content-type', 'application/json'); res.end(JSON.stringify({ path: req.url, body })); });
});
await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
const gatewayPort = gateway.address().port;
const proxy = await createCloudflareRecordProxy(gatewayPort, 'alpha_record');
const base = `http://127.0.0.1:${proxy.port}`;
const rawGet = path => new Promise((resolve, reject) => {
  const req = http.get({ hostname: '127.0.0.1', port: proxy.port, path }, res => { res.resume(); res.on('end', () => resolve(res.statusCode)); }); req.on('error', reject);
});
try {
  for (const bad of ['', '../alpha', 'alpha/../beta', '%2e%2e', 'alpha?x', 'alpha#x', 'alpha\\x', 'a\n', 'a'.repeat(65), 'cloudflare:alpha']) assert.throws(() => cloudflareRecordKey(bad));
  const result = await fetch(`${base}/mcp?cursor=1`, { method: 'POST', headers: { authorization: 'Bearer fixture', 'x-forwarded-host': 'evil.example' }, body: 'hello' });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { path: '/tunnels/alpha_record/mcp?cursor=1', body: 'hello' });
  assert.deepEqual(seen[0], { path: '/tunnels/alpha_record/mcp?cursor=1', host: `127.0.0.1:${gatewayPort}`, authorization: 'Bearer fixture', forwarded: undefined });
  for (const path of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp']) {
    const r = await fetch(`${base}${path}`); assert.equal(r.status, 200);
    assert.equal((await r.json()).path, '/.well-known/oauth-protected-resource/tunnels/alpha_record/mcp');
  }
  const count = seen.length;
  for (const path of ['/', '/status', '/events', '/tunnels/beta/mcp', '/mcp/../status', '/%6dcp', '//mcp', '/mcp%2f..%2fstatus', '/.well-known/oauth-protected-resource/other', 'http://evil.example/mcp', '/mcp\\x', '/mcp#fragment']) assert.equal(await rawGet(path), 404, path);
  assert.equal((await fetch(`${base}/mcp`, { method: 'PUT' })).status, 404);
  assert.equal(seen.length, count, 'Rejected paths never reach the gateway');
} finally { await proxy.close(); await new Promise(resolve => gateway.close(resolve)); }
console.log('PASS record proxy allowlist, exact path encoding, auth/header forwarding, and control-plane isolation');

class MockChild extends EventEmitter {
  stdout = new PassThrough(); stderr = new PassThrough(); ended = false;
  kill() { this.finish(); return true; }
  finish(code = 0) { if (this.ended) return; this.ended = true; this.stdout.end(); this.stderr.end(); queueMicrotask(() => this.emit('close', code)); }
}
const events = [], launches = [], guards = new Map();
const pool = new CloudflareRecordPool(gatewayPort, event => events.push(event), record => {
  const guard = { origin: undefined, active: true, origins: [] }; guards.set(record.key, guard);
  return { isActive: () => guard.active, setPublicOrigin: value => { guard.origin = value; guard.origins.push(value); } };
}, {
  spawn: (_executable, args) => {
    const child = new MockChild(); launches.push({ child, args }); queueMicrotask(() => child.emit('spawn')); return child;
  }, pollIntervalMs: 100, stopTimeoutMs: 50,
  fetch: async () => { throw new Error('No network probes expected without metrics'); }
});
const target = { action: 'run', mode: 'quick', executable: process.execPath };
const alpha = { ...target, key: 'alpha', serverIDs: ['server-a'] };
const beta = { ...target, key: 'beta', serverIDs: ['server-b', 'server-c'] };
const originA = 'https://alpha.trycloudflare.com', originB = 'https://beta.trycloudflare.com';
const waitFor = async predicate => { const end = Date.now() + 2000; while (!predicate()) { assert.ok(Date.now() < end); await new Promise(resolve => setTimeout(resolve, 5)); } };
try {
  for (const extra of [{ serverIDs: [] }, { serverIDs: ['same', 'same'] }, { key: '../other' }, { serverIDs: ['bad\n'] }]) await assert.rejects(pool.action({ ...alpha, ...extra }), /CLOUDFLARE_TARGET/);
  await pool.action(alpha); await pool.action(beta);
  assert.equal(launches.length, 2);
  assert.equal(pool.snapshot().find(event => event.key === 'beta').configurationFingerprints.endpoint, configurationFingerprint([`http://127.0.0.1:${gatewayPort}/tunnels/beta/mcp`]));
  assert.equal(pool.snapshot().find(event => event.key === 'beta').configurationFingerprints.serverIDs, configurationFingerprint(['server-b', 'server-c']));
  const endpoints = launches.map(({ args }) => args[args.indexOf('--url') + 1]);
  assert.notEqual(endpoints[0], endpoints[1]);
  assert.ok(endpoints.every(url => new URL(url).hostname === '127.0.0.1' && new URL(url).port !== String(gatewayPort)));
  await assert.rejects(pool.action(alpha), /CLOUDFLARE_BUSY/);
  launches[0].child.stderr.write(`${originA}\n`); launches[1].child.stderr.write(`${originB}\n`);
  assert.equal(guards.get('alpha').origin, originA); assert.equal(guards.get('beta').origin, originB);
  assert.deepEqual(pool.snapshot().find(event => event.key === 'beta').serverIDs, ['server-b', 'server-c']);
  await pool.stop('alpha');
  assert.equal(guards.get('alpha').origin, undefined); assert.equal(guards.get('beta').origin, originB);
  assert.equal(pool.snapshot().find(event => event.key === 'beta').running, true);
  await assert.rejects(fetch(endpoints[0] + '/mcp'));
  launches[1].child.finish(1);
  await waitFor(() => pool.snapshot().find(event => event.key === 'beta').running === false);
  await assert.rejects(fetch(endpoints[1] + '/mcp'));
  await pool.action(beta); // Unexpected process exit releases the record for restart.
  await pool.stop('beta');
  const named = { ...alpha, mode: 'named', tunnelID: '12345678-1234-1234-1234-123456789abc', credentialsFile: new URL('../package.json', import.meta.url).pathname, publicURL: 'https://named.example.com' };
  await pool.action(named);
  await assert.rejects(pool.action({ ...named, key: 'beta' }), /CLOUDFLARE_BUSY/);
  await assert.rejects(pool.action({ ...named, key: 'beta', tunnelID: '22345678-1234-1234-1234-123456789abc' }), /CLOUDFLARE_BUSY/);
  await pool.stop('alpha');
  const pending = pool.action(alpha); await pool.stop('alpha'); await assert.rejects(pending, /CLOUDFLARE_CANCELLED/);
  assert.equal(events.some(event => event.key === 'transport:cloudflare'), false);
} finally { await pool.stopAll(); }
console.log('PASS independent record keys, server bindings, audiences, stops, child-exit cleanup, restart and startup cancellation');
console.log('Mock processes only; no cloudflared, Cloudflare account, credentials, public tunnels, or Mac access.');
