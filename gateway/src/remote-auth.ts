/**
 * MCP 2025-11-25 OAuth resource server, backed by an administrator-selected AS.
 * The external AS owns login, consent, PKCE S256, client registration, refresh
 * tokens and revocation. This module does not implement an authorization server
 * or forward incoming access tokens to tools. It accepts RFC 9068 JWT access
 * tokens only; opaque tokens and ordinary OpenID ID tokens are not supported.
 * https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
 * https://www.rfc-editor.org/rfc/rfc9068.html
 */
import { createPublicKey, verify, type JsonWebKey } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';

export type RemoteAuthConfig = {
  enabled: boolean;
  /** Exact public MCP resource identifier, also the required token audience. */
  publicURL: string;
  /** Exact issuer identifier, including its trailing slash if it has one. */
  issuer: string;
  /** Trusted, public-key-only HTTPS endpoint; never obtained from a token. */
  jwksURL: string;
  /** Space-delimited required OAuth scopes. All are required. */
  scope: string;
};

// Dependency injection is for isolated fixtures, never read from configuration.
export type RemoteAuthDependencies = { fetch?: typeof fetch; now?: () => number };
type RecordValue = Record<string, unknown>;
type State = {
  config: RemoteAuthConfig;
  keys?: RecordValue[];
  fetchedAt: number;
  attemptedAt?: number;
  pending?: Promise<RecordValue[]>;
};
const MAX_TOKEN = 16 * 1024;
const MAX_JWKS = 256 * 1024;
const CACHE_MS = 5 * 60 * 1000;
const REFRESH_COOLDOWN_MS = 30 * 1000;
const JWKS_TIMEOUT_MS = 5000;
const ROOT_METADATA_PATH = '/.well-known/oauth-protected-resource';
const EMPTY: RemoteAuthConfig = { enabled: false, publicURL: '', issuer: '', jwksURL: '', scope: 'mcp:tools' };
const scopePattern = /^[\x21\x23-\x5B\x5D-\x7E]+(?: [\x21\x23-\x5B\x5D-\x7E]+)*$/;

function object(value: unknown): value is RecordValue {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function trustedURL(value: unknown, name: string): string {
  // Configuration is nonsecret and is later used in HTTP headers/metadata.
  if (typeof value !== 'string' || value.length > 2048 || !value || /[\s\x00-\x1F\x7F"\\]/.test(value)) {
    throw new Error(`Remote OAuth ${name} must be an absolute HTTPS URL`);
  }
  let url: URL;
  try { url = new URL(value); } catch { throw new Error(`Remote OAuth ${name} must be an absolute HTTPS URL`); }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash || url.search) {
    throw new Error(`Remote OAuth ${name} requires HTTPS without credentials, query or fragment`);
  }
  return value;
}

/** Validation never fetches a URL, creates credentials or changes network access. */
export function validateRemoteAuthConfig(raw: unknown): RemoteAuthConfig {
  if (raw === undefined || raw === null) return { ...EMPTY };
  if (!object(raw) || typeof raw.enabled !== 'boolean') throw new Error('Invalid remote OAuth configuration');
  if (Object.keys(raw).some(key => !Object.hasOwn(EMPTY, key))) throw new Error('Unknown remote OAuth setting');
  const result = { ...EMPTY, enabled: raw.enabled };
  for (const key of ['publicURL', 'issuer', 'jwksURL', 'scope'] as const) {
    if (raw[key] !== undefined && (typeof raw[key] !== 'string' || raw[key].length > 2048)) throw new Error('Invalid remote OAuth setting');
    result[key] = raw[key] as string | undefined ?? EMPTY[key];
  }
  // Incomplete disabled settings may be saved while onboarding. Nonempty
  // endpoints are still validated so snapshots cannot accidentally hold secrets.
  for (const key of ['publicURL', 'issuer', 'jwksURL'] as const) {
    if (result.enabled || result[key]) result[key] = trustedURL(result[key], key);
  }
  if ((result.enabled || result.scope) && (result.scope.length > 512 || !scopePattern.test(result.scope) || result.scope.split(' ').length > 16)) {
    throw new Error('Remote OAuth requires valid space-delimited scopes');
  }
  return result;
}

function json(res: ServerResponse, status: number, value: unknown, head = false): void {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.end(head ? undefined : JSON.stringify(value));
}

function metadataLocation(config: RemoteAuthConfig): URL {
  const resource = new URL(config.publicURL);
  return new URL(ROOT_METADATA_PATH + (resource.pathname === '/' ? '' : resource.pathname), resource.origin);
}

function decodeSegment(segment: string): Buffer {
  if (!segment || !/^[A-Za-z0-9_-]+$/.test(segment)) throw new Error('Invalid token');
  const bytes = Buffer.from(segment, 'base64url');
  if (bytes.toString('base64url') !== segment) throw new Error('Invalid token');
  return bytes;
}
function decodeObject(segment: string): RecordValue {
  const value: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(decodeSegment(segment)));
  if (!object(value)) throw new Error('Invalid token');
  return value;
}
function numericDate(value: unknown): value is number { return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0; }
function boundedString(value: unknown): value is string { return typeof value === 'string' && value.length > 0 && value.length <= 2048; }

async function fetchKeys(url: string, fetcher: typeof fetch): Promise<RecordValue[]> {
  const controller = new AbortController();
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  // Race the full response body as well as the headers. This is a wall-clock
  // deadline, not an idle timeout that a slow peer can indefinitely extend.
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => { controller.abort(); reject(new Error('Signing keys unavailable')); }, JWKS_TIMEOUT_MS);
    timer.unref();
  });
  const work = async (): Promise<RecordValue[]> => {
    const response = await fetcher(url, { method: 'GET', redirect: 'error', signal: controller.signal,
      headers: { Accept: 'application/jwk-set+json, application/json' }, credentials: 'omit' });
    if (response.status !== 200 || response.redirected || !response.body) throw new Error('Signing keys unavailable');
    const type = response.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase();
    if (type !== 'application/json' && type !== 'application/jwk-set+json') throw new Error('Invalid signing keys');
    if (Number(response.headers.get('content-length') ?? 0) > MAX_JWKS) throw new Error('Oversized signing keys');
    reader = response.body.getReader();
    const chunks: Buffer[] = []; let size = 0;
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      if (size > MAX_JWKS) throw new Error('Oversized signing keys');
      chunks.push(Buffer.from(part.value));
    }
    const data: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
    if (!object(data) || !Array.isArray(data.keys) || !data.keys.length || data.keys.length > 64 || !data.keys.every(object)) {
      throw new Error('Invalid signing keys');
    }
    // Never retain accidentally published private key material, symmetric keys,
    // certificates or unrelated fields, even in this short-lived public cache.
    return data.keys.map(key => {
      if (['d', 'p', 'q', 'dp', 'dq', 'qi', 'oth', 'k'].some(field => Object.hasOwn(key, field))) throw new Error('Invalid signing keys');
      const result: RecordValue = {};
      for (const field of ['kid', 'kty', 'alg', 'use', 'key_ops', 'n', 'e', 'crv', 'x', 'y']) {
        if (key[field] !== undefined) result[field] = key[field];
      }
      return result;
    });
  };
  try { return await Promise.race([work(), timeout]); }
  finally { clearTimeout(timer); controller.abort(); void reader?.cancel().catch(() => undefined); }
}

function publicKey(keys: RecordValue[], kid: string, alg: string) {
  const matches = keys.filter(key => key.kid === kid);
  if (matches.length !== 1) throw new Error('Invalid token');
  const key = matches[0]!;
  if ((key.alg !== undefined && key.alg !== alg) || (key.use !== undefined && key.use !== 'sig') ||
      (key.key_ops !== undefined && (!Array.isArray(key.key_ops) || !key.key_ops.includes('verify') || key.key_ops.some(op => op !== 'verify')))) {
    throw new Error('Invalid token');
  }
  if (alg === 'RS256') {
    if (key.kty !== 'RSA' || typeof key.n !== 'string' || typeof key.e !== 'string') throw new Error('Invalid token');
    const modulus = decodeSegment(key.n); const exponent = decodeSegment(key.e);
    if (modulus.length < 256 || modulus.length > 1024 || !modulus[0] || exponent.length > 8) throw new Error('Invalid token');
  } else if (key.kty !== 'EC' || key.crv !== 'P-256' || typeof key.x !== 'string' || typeof key.y !== 'string' ||
      decodeSegment(key.x).length !== 32 || decodeSegment(key.y).length !== 32) throw new Error('Invalid token');
  const imported = createPublicKey({ key: key as JsonWebKey, format: 'jwk' });
  if (alg === 'RS256' && (imported.asymmetricKeyType !== 'rsa' || (imported.asymmetricKeyDetails?.modulusLength ?? 0) < 2048)) throw new Error('Invalid token');
  return imported;
}

export class RemoteAuth {
  private state: State;
  private readonly fetcher: typeof fetch;
  private readonly now: () => number;
  private pendingAuthorizations = 0;

  constructor(config?: unknown, dependencies: RemoteAuthDependencies = {}) {
    this.state = { config: validateRemoteAuthConfig(config), fetchedAt: 0 };
    this.fetcher = dependencies.fetch ?? globalThis.fetch;
    this.now = dependencies.now ?? Date.now;
  }

  configure(raw: unknown): RemoteAuthConfig {
    // Validate before replacing a working policy. A failed edit cannot disable it.
    this.state = { config: validateRemoteAuthConfig(raw), fetchedAt: 0 };
    return this.snapshot();
  }

  snapshot(): RemoteAuthConfig { return { ...this.state.config }; }

  /** Call after the HTTP host/origin checks, before normal MCP routing. */
  handleMetadata(req: IncomingMessage, res: ServerResponse): boolean {
    const config = this.state.config;
    if (!config.enabled) return false;
    let url: URL;
    try {
      if (!req.url?.startsWith('/') || req.url.startsWith('//')) return false;
      url = new URL(req.url, 'http://127.0.0.1');
    } catch { return false; }
    if (url.pathname !== ROOT_METADATA_PATH && url.pathname !== metadataLocation(config).pathname) return false;
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.setHeader('Allow', 'GET, HEAD'); json(res, 405, { error: 'method_not_allowed' }); return true;
    }
    json(res, 200, { resource: config.publicURL, authorization_servers: [config.issuer],
      bearer_methods_supported: ['header'], scopes_supported: config.scope.split(' '), resource_name: 'One MCP' }, req.method === 'HEAD');
    return true;
  }

  private reject(res: ServerResponse, state: State, status: number, error?: string): false {
    const parts = [`resource_metadata="${metadataLocation(state.config).href}"`, `scope="${state.config.scope}"`];
    if (error) parts.unshift(`error="${error}"`);
    res.setHeader('WWW-Authenticate', `Bearer ${parts.join(', ')}`);
    json(res, status, { error: error ?? 'authorization_required' });
    return false;
  }

  private async keys(state: State, kid: string): Promise<RecordValue[]> {
    const now = this.now();
    if (state.keys && now - state.fetchedAt < CACHE_MS && state.keys.some(key => key.kid === kid)) return state.keys;
    if (state.pending) return state.pending;
    if (state.attemptedAt !== undefined && now - state.attemptedAt < REFRESH_COOLDOWN_MS) {
      // Never extend expired keys after a failed refresh or a key-removal event.
      if (state.keys && now - state.fetchedAt < CACHE_MS) return state.keys;
      throw new Error('Signing keys unavailable');
    }
    state.attemptedAt = now;
    const pending = fetchKeys(state.config.jwksURL, this.fetcher).then(keys => {
      state.keys = keys; state.fetchedAt = this.now(); return keys;
    });
    state.pending = pending;
    try { return await pending; } finally { if (state.pending === pending) state.pending = undefined; }
  }

  /** True permits the MCP request; false has already sent a safe HTTP error. */
  async authorize(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const state = this.state;
    if (!state.config.enabled) return true;
    let query: URLSearchParams;
    try { query = new URL(req.url ?? '', 'http://127.0.0.1').searchParams; }
    catch { return this.reject(res, state, 400, 'invalid_request'); }
    const authorizationCount = req.rawHeaders.filter((_, index) => index % 2 === 0 && req.rawHeaders[index]?.toLowerCase() === 'authorization').length;
    if (query.has('access_token') || authorizationCount > 1 || Array.isArray(req.headers.authorization)) return this.reject(res, state, 400, 'invalid_request');
    const authorization = req.headers.authorization;
    if (authorization === undefined) return this.reject(res, state, 401);
    if (authorization.length > MAX_TOKEN + 7) return this.reject(res, state, 401, 'invalid_token');
    const bearer = /^Bearer ([A-Za-z0-9_.-]+)$/i.exec(authorization);
    if (!bearer) return this.reject(res, state, 400, 'invalid_request');
    if (this.pendingAuthorizations >= 32) {
      res.setHeader('Retry-After', '1'); json(res, 503, { error: 'temporarily_unavailable' }); return false;
    }
    this.pendingAuthorizations++;
    try {
      const segments = bearer[1]!.split('.');
      if (segments.length !== 3 || !segments[0] || !segments[1] || !segments[2]) throw new Error('Invalid token');
      const header = decodeObject(segments[0]); const claims = decodeObject(segments[1]);
      if ((header.alg !== 'RS256' && header.alg !== 'ES256') || typeof header.typ !== 'string' ||
          !['at+jwt', 'application/at+jwt'].includes(header.typ.toLowerCase()) ||
          typeof header.kid !== 'string' || !header.kid || header.kid.length > 256 ||
          ['crit', 'b64', 'jku', 'jwk', 'x5u'].some(field => Object.hasOwn(header, field))) throw new Error('Invalid token');
      const now = Math.floor(this.now() / 1000);
      const audience = typeof claims.aud === 'string' ? [claims.aud] : claims.aud;
      if (claims.iss !== state.config.issuer || !Array.isArray(audience) || audience.length > 16 ||
          !audience.every(boundedString) || !audience.includes(state.config.publicURL) ||
          !numericDate(claims.exp) || claims.exp <= now || !numericDate(claims.iat) || claims.iat > now + 30 || claims.iat >= claims.exp ||
          (claims.nbf !== undefined && (!numericDate(claims.nbf) || claims.nbf > now + 30 || claims.nbf >= claims.exp)) ||
          !boundedString(claims.sub) || !boundedString(claims.client_id) || !boundedString(claims.jti)) throw new Error('Invalid token');
      const signature = decodeSegment(segments[2]);
      if (header.alg === 'ES256' && signature.length !== 64) throw new Error('Invalid token');
      const keys = await this.keys(state, header.kid);
      const key = publicKey(keys, header.kid, header.alg);
      const valid = verify('sha256', Buffer.from(`${segments[0]}.${segments[1]}`, 'ascii'),
        header.alg === 'ES256' ? { key, dsaEncoding: 'ieee-p1363' } : key, signature);
      // Recheck time and policy after network I/O; an edit may have revoked this
      // configuration while JWKS discovery was in flight.
      if (!valid || this.state !== state || claims.exp <= Math.floor(this.now() / 1000)) throw new Error('Invalid token');
      const grantedScopes = typeof claims.scope === 'string' && claims.scope.length <= 4096 && scopePattern.test(claims.scope)
        ? new Set(claims.scope.split(' ')) : new Set<string>();
      if (!state.config.scope.split(' ').every(scope => grantedScopes.has(scope))) {
        return this.reject(res, state, 403, 'insufficient_scope');
      }
      return true;
    } catch {
      // Do not include issuer responses, JWT claims, subject IDs or bearer values
      // in errors/events. Authentication fails closed when keys are unavailable.
      return this.reject(res, state, 401, 'invalid_token');
    } finally { this.pendingAuthorizations--; }
  }
}
