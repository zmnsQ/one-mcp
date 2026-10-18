import assert from 'node:assert/strict';
import http from 'node:http';
import {generateKeyPairSync, sign} from 'node:crypto';
import {RemoteAuth, validateRemoteAuthConfig} from '../dist/remote-auth.js';

// Ephemeral fixture keys only. No OAuth account, consent, credentials or live AS.
const rsa = generateKeyPairSync('rsa', {modulusLength: 2048});
const ec = generateKeyPairSync('ec', {namedCurve: 'P-256'});
const wrong = generateKeyPairSync('rsa', {modulusLength: 2048});
const weak = generateKeyPairSync('rsa', {modulusLength: 1024});
const jwk = (pair, kid, alg) => ({...pair.publicKey.export({format: 'jwk'}), kid, alg, use: 'sig', key_ops: ['verify']});
const rsaJwk = jwk(rsa, 'rsa-fixture', 'RS256');
const ecJwk = jwk(ec, 'ec-fixture', 'ES256');
const config = {enabled: true, publicURL: 'https://resource.example/mcp', issuer: 'https://issuer.example/tenant',
  jwksURL: 'https://keys.example/jwks.json', scope: 'mcp:tools'};
let now = 1_800_000_000_000;
const claims = () => ({iss: config.issuer, aud: config.publicURL, exp: now / 1000 + 300, iat: now / 1000 - 1,
  sub: 'fixture-owner', client_id: 'fixture-client', jti: 'fixture-id', scope: config.scope});
const encoded = value => Buffer.from(JSON.stringify(value)).toString('base64url');
function token(overrides = {}, headerOverrides = {}, pair = rsa) {
  const alg = headerOverrides.alg ?? 'RS256';
  const h = encoded({alg, typ: 'at+jwt', kid: 'rsa-fixture', ...headerOverrides});
  const p = encoded({...claims(), ...overrides});
  const signature = sign('sha256', Buffer.from(`${h}.${p}`), alg === 'ES256' ? {key: pair.privateKey, dsaEncoding: 'ieee-p1363'} : pair.privateKey);
  return `${h}.${p}.${signature.toString('base64url')}`;
}
function fixtureResponse() {
  return {statusCode: 0, headers: {}, body: '', setHeader(key, value) {this.headers[key.toLowerCase()] = value;},
    end(value) {this.body = value ?? '';}};
}
function fixtureRequest(authorization, url = '/mcp', rawHeaders) {
  return {url, method: 'POST', headers: authorization === undefined ? {} : {authorization},
    rawHeaders: rawHeaders ?? (authorization === undefined ? [] : ['Authorization', authorization])};
}
let fetchCount = 0;
let keySet = [rsaJwk, ecJwk];
let responseMode = 'ok';
let release;
const fetchedURLs = [];
async function fakeFetch(url, options) {
  fetchCount++; fetchedURLs.push(url);
  assert.equal(url, config.jwksURL);
  assert.equal(options.method, 'GET'); assert.equal(options.redirect, 'error');
  assert.equal(options.credentials, 'omit'); assert.ok(options.signal instanceof AbortSignal);
  assert.deepEqual(Object.keys(options.headers), ['Accept']);
  if (responseMode === 'wait') await new Promise(resolve => {release = resolve;});
  if (responseMode === 'stall-headers') await new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(new Error('aborted')), {once: true}));
  if (responseMode === 'stall-body') return new Response(new ReadableStream({start(controller) {controller.enqueue(Buffer.from('{'));}}), {headers: {'content-type': 'application/json'}});
  if (responseMode === 'offline') throw new Error('upstream-private-diagnostics');
  if (responseMode === 'redirect') return new Response('', {status: 302, headers: {location: 'https://untrusted.example/keys'}});
  if (responseMode === 'mime') return new Response('{}', {headers: {'content-type': 'text/html'}});
  if (responseMode === 'malformed') return new Response('{', {headers: {'content-type': 'application/json'}});
  if (responseMode === 'large-header') return new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '262145'}});
  if (responseMode === 'large-body') return new Response(' '.repeat(262145), {headers: {'content-type': 'application/json'}});
  return new Response(JSON.stringify({keys: keySet}), {headers: {'content-type': 'application/jwk-set+json'}});
}
const make = () => new RemoteAuth(config, {fetch: fakeFetch, now: () => now});
let guard = make();
async function check(accessToken, status, error, target = guard, request = {}) {
  const res = fixtureResponse();
  const authorization = accessToken === undefined ? undefined : `Bearer ${accessToken}`;
  const result = await target.authorize({...fixtureRequest(authorization), ...request}, res);
  assert.equal(result, status === 200, `Unexpected authorization result for ${error ?? status}`);
  if (status !== 200) {
    assert.equal(res.statusCode, status); assert.equal(JSON.parse(res.body).error, error);
    if (status !== 503) assert.ok(res.headers['www-authenticate'].includes('resource_metadata="https://resource.example/.well-known/oauth-protected-resource/mcp"'));
    assert.equal(res.headers['cache-control'], 'no-store');
    if (accessToken) assert.equal(JSON.stringify(res).includes(accessToken), false);
    assert.equal(JSON.stringify(res).includes('upstream-private-diagnostics'), false);
  }
  return res;
}

assert.deepEqual(validateRemoteAuthConfig(undefined), {enabled: false, publicURL: '', issuer: '', jwksURL: '', scope: 'mcp:tools'});
assert.equal(validateRemoteAuthConfig({enabled: false}).scope, 'mcp:tools');
assert.equal(new RemoteAuth().handleMetadata(fixtureRequest(), fixtureResponse()), false);
assert.equal(await new RemoteAuth().authorize(fixtureRequest(), fixtureResponse()), true);
for (const field of ['publicURL', 'issuer', 'jwksURL']) {
  for (const value of ['', 'http://issuer.example', 'https://user:password@issuer.example', 'https://issuer.example/#x', 'https://issuer.example/?secret=x', 'https://issuer.example/\r\nInjected: x']) {
    assert.throws(() => validateRemoteAuthConfig({...config, [field]: value}));
  }
}
for (const scope of ['', 'x\"injected', 'x\\injected', 'x\ny', 'x  y', 'x'.repeat(513)]) assert.throws(() => validateRemoteAuthConfig({...config, scope}));
assert.throws(() => guard.configure({...config, secret: 'never-echo'}));
assert.deepEqual(guard.snapshot(), config);
const copy = guard.snapshot(); copy.enabled = false; assert.equal(guard.snapshot().enabled, true);

for (const path of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp']) {
  const res = fixtureResponse();
  assert.equal(guard.handleMetadata({url: path, method: 'GET', headers: {host: 'attacker.example'}}, res), true);
  assert.deepEqual(JSON.parse(res.body), {resource: config.publicURL, authorization_servers: [config.issuer],
    bearer_methods_supported: ['header'], scopes_supported: ['mcp:tools'], resource_name: 'One MCP'});
}
let res = fixtureResponse();
assert.equal(guard.handleMetadata({url: '/.well-known/oauth-protected-resource', method: 'HEAD'}, res), true);
assert.equal(res.body, '');
res = fixtureResponse(); guard.handleMetadata({url: '/.well-known/oauth-protected-resource', method: 'POST'}, res);
assert.equal(res.statusCode, 405); assert.equal(res.headers.allow, 'GET, HEAD');
assert.equal(guard.handleMetadata({url: '/unrelated', method: 'GET'}, fixtureResponse()), false);
assert.equal(guard.handleMetadata({url: '//attacker.example/.well-known/oauth-protected-resource', method: 'GET'}, fixtureResponse()), false);

await check(undefined, 401, 'authorization_required');
assert.equal(fetchCount, 0);
await check(token(), 200);
assert.equal(fetchCount, 1);
await check(token({}, {alg: 'ES256', kid: 'ec-fixture'}, ec), 200);
await check(token({aud: ['https://other.example', config.publicURL]}), 200);
await check(token({}, {typ: 'application/at+JWT'}), 200);
assert.equal(fetchCount, 1);
for (const override of [
  {iss: 'https://untrusted.example'}, {aud: 'https://other.example'}, {aud: []}, {aud: [config.publicURL, 4]},
  {exp: now / 1000}, {exp: '9999999999'}, {exp: undefined}, {iat: now / 1000 + 31}, {iat: undefined},
  {nbf: now / 1000 + 31}, {nbf: 'later'}, {sub: ''}, {client_id: undefined}, {jti: undefined}
]) await check(token(override), 401, 'invalid_token');
for (const header of [{alg: 'HS256'}, {alg: 'none'}, {typ: 'JWT'}, {typ: undefined}, {kid: ''},
  {crit: ['unknown']}, {b64: false}, {jku: 'https://attacker.example'}, {jwk: rsaJwk}, {x5u: 'https://attacker.example'}]) {
  await check(token({}, header), 401, 'invalid_token');
}
await check(token({}, {}, wrong), 401, 'invalid_token');
for (const value of ['a.b.c', 'opaque-token', 'a.b.c.d', 'a'.repeat(16385)]) await check(value, 401, 'invalid_token');
await check(token({scope: 'mcp:read'}), 403, 'insufficient_scope');
await check(token({scope: undefined}), 403, 'insufficient_scope');
await check(token({scope: 'mcp:tools-other'}), 403, 'insufficient_scope');
await check(token(), 400, 'invalid_request', guard, {url: '/mcp?access_token=never-accept'});
await check(token(), 400, 'invalid_request', guard, {rawHeaders: ['Authorization', 'Bearer one', 'authorization', 'Bearer two']});
await check(undefined, 400, 'invalid_request', guard, {headers: {authorization: 'Basic whatever'}, rawHeaders: ['Authorization', 'Basic whatever']});
assert.equal(fetchCount, 1, 'malformed/unknown-provider tokens must not select arbitrary keys or trigger unbounded fetches');

// Cache misses are throttled, rotation is supported after cooldown, stale keys
// are never accepted after expiry when their refresh fails.
await check(token({}, {kid: 'missing'}), 401, 'invalid_token'); assert.equal(fetchCount, 1);
now += 31_000;
keySet = [rsaJwk, ecJwk, {...rsaJwk, kid: 'rotated'}];
await check(token({}, {kid: 'rotated'}), 200); assert.equal(fetchCount, 2);
now += 301_000; responseMode = 'offline';
await check(token(), 401, 'invalid_token'); assert.equal(fetchCount, 3);
await check(token(), 401, 'invalid_token'); assert.equal(fetchCount, 3);
responseMode = 'ok'; now += 31_000;
await check(token(), 200); assert.equal(fetchCount, 4);

for (const mode of ['redirect', 'mime', 'malformed', 'large-header', 'large-body']) {
  responseMode = mode;
  await check(token(), 401, 'invalid_token', make());
}
responseMode = 'ok';
for (const invalidKeys of [[{...rsaJwk, d: 'private-material'}], [{...rsaJwk, alg: 'HS256'}],
  [{...rsaJwk, use: 'enc'}], [{...rsaJwk, key_ops: ['sign']}], [rsaJwk, rsaJwk], [],
  [{...rsaJwk, n: 'AA'}], [{...ecJwk, crv: 'P-384'}]]) {
  keySet = invalidKeys;
  await check(token(), 401, 'invalid_token', make());
}
keySet = [rsaJwk, ecJwk];
keySet = [jwk(weak, 'rsa-fixture', 'RS256')];
await check(token({}, {}, weak), 401, 'invalid_token', make());
keySet = [{...ecJwk, crv: 'P-384'}];
await check(token({}, {alg: 'ES256', kid: 'ec-fixture'}, ec), 401, 'invalid_token', make());
keySet = Array.from({length: 65}, (_, index) => ({...rsaJwk, kid: `key-${index}`}));
await check(token(), 401, 'invalid_token', make());
keySet = [rsaJwk, ecJwk];
responseMode = 'wait'; guard = make();
const before = fetchCount;
const waiting = Array.from({length: 32}, () => check(token(), 200));
await check(token(), 503, 'temporarily_unavailable');
assert.equal(fetchCount, before + 1); release(); await Promise.all(waiting);
responseMode = 'wait'; guard = make();
const revokedDuringFetch = check(token(), 401, 'invalid_token');
guard.configure({...config, scope: 'mcp:other'}); release(); await revokedDuringFetch;
responseMode = 'wait'; guard = make();
const expiresDuringFetch = check(token({exp: now / 1000 + 1}), 401, 'invalid_token');
now += 2000; release(); await expiresDuringFetch;
responseMode = 'ok';
assert.ok(fetchedURLs.every(url => url === config.jwksURL));

// Real IncomingMessage/ServerResponse exercise of the exported handler surface.
guard = make();
const server = http.createServer((req, res) => {
  void (async () => {
    if (guard.handleMetadata(req, res)) return;
    if (!await guard.authorize(req, res)) return;
    res.setHeader('content-type', 'application/json'); res.end('{"authorized":true}');
  })().catch(() => {res.statusCode = 500; res.end();});
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  const base = `http://127.0.0.1:${server.address().port}`;
  const metadata = await fetch(base + '/.well-known/oauth-protected-resource/mcp');
  assert.equal(metadata.status, 200); assert.equal((await metadata.json()).resource, config.publicURL);
  const challenge = await fetch(base + '/mcp', {method: 'POST'});
  assert.equal(challenge.status, 401); assert.match(challenge.headers.get('www-authenticate'), /^Bearer /);
  const allowed = await fetch(base + '/mcp', {method: 'POST', headers: {authorization: `Bearer ${token()}`}});
  assert.equal(allowed.status, 200); assert.deepEqual(await allowed.json(), {authorized: true});
  const expired = await fetch(base + '/mcp', {method: 'POST', headers: {authorization: `Bearer ${token({exp: now / 1000 - 1})}`}});
  assert.equal(expired.status, 401);
  for (const mode of ['stall-headers', 'stall-body']) {
    responseMode = mode; const started = Date.now();
    await check(token(), 401, 'invalid_token', make());
    assert.ok(Date.now() - started < 6500, 'JWKS headers and response bodies need a wall-clock deadline');
  }
} finally {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}

console.log('PASS incoming OAuth resource metadata/challenges, RS256/ES256 signatures, RFC9068 token typing, issuer/audience/time/scope, rejection/privacy, bounded fixed-endpoint JWKS, rotation/cache, concurrent and policy-change races, real HTTP handler fixtures');
