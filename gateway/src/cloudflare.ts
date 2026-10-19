/** Managed Cloudflare child only: never logs raw diagnostics or manages Cloudflare credentials.
 * CLI and readiness contracts: https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/create-local-tunnel/
 * https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
 * https://github.com/cloudflare/cloudflared/blob/master/metrics/metrics.go
 */
import { spawn, ChildProcess, SpawnOptions } from 'node:child_process';
import fs from 'node:fs/promises';
import { constants } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { tmpdir } from 'node:os';
import { isIP } from 'node:net';
import { configurationFingerprint, configurationFingerprintVersion, ConfigurationFingerprints } from './configuration-fingerprints.js';

export type CloudflareTarget = {
  action: 'doctor' | 'run'; executable: string; mode: 'quick' | 'named';
  tunnelID?: string; credentialsFile?: string; publicURL?: string;
};
export type CloudflareOAuthGuard = {
  isActive(): boolean;
  expectedIssuer?(): string;
  expectedScopes?(): readonly string[];
  /** Named origins must already match the configured resource. Quick origins are session-only. */
  setPublicOrigin(origin: string | undefined): void;
};
export type CloudflareDependencies = {
  spawn?: (executable: string, args: string[], options: SpawnOptions) => ChildProcess;
  fetch?: typeof fetch;
  pollIntervalMs?: number;
  probeTimeoutMs?: number;
  doctorTimeoutMs?: number;
  stopTimeoutMs?: number;
};
const messages = {
  CLOUDFLARE_TARGET: 'Invalid Cloudflare operation or mode.',
  CLOUDFLARE_EXECUTABLE: 'Select an absolute path to an installed, executable cloudflared binary.',
  CLOUDFLARE_CREDENTIALS: 'Select an existing readable credentials JSON file for this locally-managed tunnel.',
  CLOUDFLARE_ID: 'A locally-managed Cloudflare tunnel UUID is required.',
  CLOUDFLARE_URL: 'Use a public HTTPS origin with no credentials, port, path, query, or fragment.',
  CLOUDFLARE_OAUTH: 'Enable and configure incoming OAuth before exposing the gateway.',
  CLOUDFLARE_BUSY: 'Cloudflare is already running or starting; stop it before changing configuration.',
  CLOUDFLARE_FAILED: 'cloudflared exited unsuccessfully. Raw output is hidden to protect credentials.',
  CLOUDFLARE_VERSION: 'cloudflared --version did not return a recognized version within the time limit.',
  CLOUDFLARE_CANCELLED: 'Cloudflare startup was cancelled.',
} as const;
export class CloudflareActionError extends Error {
  constructor(readonly code: keyof typeof messages) { super(`[${code}] ${messages[code]}`); }
}
function fail(code: keyof typeof messages): never { throw new CloudflareActionError(code); }
const absolutePath = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.length <= 4096 && isAbsolute(value) && !/[\0\r\n]/.test(value);
export function cloudflarePublicOrigin(value: unknown): string {
  if (typeof value !== 'string' || value.length > 2048 || /[\s\\]/.test(value)) return fail('CLOUDFLARE_URL');
  let url: URL;
  try { url = new URL(value); } catch { return fail('CLOUDFLARE_URL'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port || url.search || url.hash || url.pathname !== '/' ||
      !url.hostname.includes('.') || isIP(url.hostname) || /(?:^|\.)(?:localhost|local|internal|invalid|test)$/.test(url.hostname) ||
      !/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(url.hostname) || url.hostname.split('.').some(label => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) return fail('CLOUDFLARE_URL');
  // Reject URL normalization tricks, including percent-encoded hosts and explicit default ports.
  if (value !== url.origin && value !== `${url.origin}/`) return fail('CLOUDFLARE_URL');
  return url.origin;
}
/** Accept a complete URL token only, never a prefix of an attacker-controlled suffix. */
export function quickTunnelOrigin(line: string): string | undefined {
  for (const token of line.match(/https:\/\/[^\s"'<>|]+/g) ?? []) {
    if (/^https:\/\/[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.trycloudflare\.com\/?$/.test(token)) return new URL(token).origin;
  }
  return undefined;
}
export function cloudflareMetricsOrigin(line: string): string | undefined {
  const match = line.match(/(?:^|\s)Starting metrics server on (127\.0\.0\.1):([1-9][0-9]{0,4})\/metrics(?=$|[\s"'])/);
  if (!match || Number(match[2]) > 65535) return undefined;
  return `http://127.0.0.1:${match[2]}`;
}
async function boundedJSON(response: Response, limit = 65536): Promise<unknown> {
  const length = response.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > limit)) { await response.body?.cancel(); throw new Error('Metadata size'); }
  if (!response.body) throw new Error('Missing metadata');
  const reader = response.body.getReader(); const parts: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new Error('Metadata size');
      parts.push(value);
    }
    return JSON.parse(Buffer.concat(parts).toString('utf8'));
  } finally { await reader.cancel().catch(() => undefined); reader.releaseLock(); }
}
/** Bounded, GET-only, no redirects; never sends bearer credentials to the public endpoint. */
export async function probeCloudflareMetadata(origin: string, fetcher: typeof fetch = fetch, signal: AbortSignal = AbortSignal.timeout(2500), expected: { issuer?: string; scopes?: readonly string[] } = {}): Promise<boolean> {
  origin = cloudflarePublicOrigin(origin);
  const response = await fetcher(`${origin}/.well-known/oauth-protected-resource/mcp`, { method: 'GET', redirect: 'manual', credentials: 'omit', signal, headers: { accept: 'application/json' } });
  if (response.status !== 200 || response.redirected || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '')) { await response.body?.cancel(); return false; }
  const raw = await boundedJSON(response);
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return false;
  const metadata = raw as Record<string, unknown>;
  const servers = metadata.authorization_servers;
  if (expected.issuer !== undefined && (!expected.issuer || !Array.isArray(servers) || servers.length !== 1 || servers[0] !== expected.issuer)) return false;
  if (expected.scopes !== undefined) {
    const scopes = metadata.scopes_supported;
    if (!Array.isArray(scopes) || scopes.length > 64 || !scopes.every(scope => typeof scope === 'string' && scope.length > 0 && scope.length <= 512 && /^[\x21\x23-\x5B\x5D-\x7E]+$/.test(scope)) ||
        !expected.scopes.every(scope => scopes.includes(scope))) return false;
  }
  return metadata.resource === `${origin}/mcp` && Array.isArray(metadata.authorization_servers) && metadata.authorization_servers.length > 0 && metadata.authorization_servers.length <= 16 && metadata.authorization_servers.every(value => {
    if (typeof value !== 'string' || value.length > 2048) return false;
    try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password && !u.hash && !u.search; } catch { return false; }
  });
}

export function cloudflareConfigurationFingerprints(target: CloudflareTarget, port: number): ConfigurationFingerprints {
  return Object.fromEntries(Object.entries({ executable: target.executable, mode: target.mode, tunnelID: target.tunnelID ?? '', credentialsFile: target.credentialsFile ?? '', publicURL: target.publicURL ?? '', endpoint: `http://127.0.0.1:${port}` }).map(([key, value]) => [key, configurationFingerprint([value])]));
}

type Running = {
  target: CloudflareTarget; child: ChildProcess; closed: Promise<void>; lifetime: AbortController;
  folder: string; configurationFingerprints: ConfigurationFingerprints; timer?: NodeJS.Timeout; doctorTimer?: NodeJS.Timeout; checking: boolean;
  publicOrigin?: string; metricsOrigin?: string; version?: string;
  stopping: boolean; stopPromise?: Promise<void>; failure?: keyof typeof messages;
};
export class CloudflareTunnelManager {
  private running?: Running;
  private result?: object;
  private starting = false;
  private generation = 0;
  private readonly launch: NonNullable<CloudflareDependencies['spawn']>;
  private readonly fetcher: typeof fetch;
  constructor(private port: number, private emit: (event: object) => void, private oauth: CloudflareOAuthGuard, private dependencies: CloudflareDependencies = {}, private readonly recordKey = 'transport:cloudflare') {
    if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid loopback port');
    this.launch = dependencies.spawn ?? ((executable, args, options) => spawn(executable, args, options));
    this.fetcher = dependencies.fetch ?? fetch;
  }
  snapshot(): object[] { return this.result ? [structuredClone(this.result)] : []; }
  private event(data: Record<string, unknown>) {
    const event = { type: 'tunnelStatus', key: this.recordKey, provider: 'cloudflare', ...data };
    this.result = event; this.emit(event);
  }
  private status(r: Running, state: string, extra: Record<string, unknown> = {}) {
    this.event({ action: r.target.action, mode: r.target.mode, running: true, ready: false, configurationFingerprintVersion, configurationFingerprints: r.configurationFingerprints,
      oauthVerified: false, toolCallVerified: false, developmentOnly: r.target.mode === 'quick',
      ...(r.publicOrigin ? { publicURL: r.publicOrigin, mcpURL: `${r.publicOrigin}/mcp` } : {}), state, ...extra });
  }
  private active(): boolean { try { return this.oauth.isActive() === true; } catch { return false; } }
  private current(r: Running): boolean { return this.running === r && !r.stopping && !r.lifetime.signal.aborted; }
  private setOrigin(origin: string | undefined) { try { this.oauth.setPublicOrigin(origin); } catch { fail('CLOUDFLARE_OAUTH'); } }
  async start(raw: Omit<CloudflareTarget, 'action'>): Promise<unknown> { return this.action({ ...raw, action: 'run' }); }
  async action(raw: unknown): Promise<unknown> {
    if (this.running || this.starting) return fail('CLOUDFLARE_BUSY');
    this.starting = true;
    const generation = this.generation;
    let folder: string | undefined;
    let originSet = false;
    const cancelled = () => { if (generation !== this.generation) fail('CLOUDFLARE_CANCELLED'); };
    try {
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return fail('CLOUDFLARE_TARGET');
      const input = raw as Record<string, unknown>;
      if (!['doctor', 'run'].includes(String(input.action)) || !['quick', 'named'].includes(String(input.mode)) ||
          Object.keys(input).some(key => !['key', 'action', 'executable', 'mode', 'tunnelID', 'credentialsFile', 'publicURL'].includes(key)) ||
          (input.key !== undefined && input.key !== this.recordKey)) return fail('CLOUDFLARE_TARGET');
      if (!absolutePath(input.executable)) return fail('CLOUDFLARE_EXECUTABLE');
      try { if (!(await fs.stat(input.executable)).isFile()) return fail('CLOUDFLARE_EXECUTABLE'); await fs.access(input.executable, constants.X_OK); } catch { return fail('CLOUDFLARE_EXECUTABLE'); }
      const t: CloudflareTarget = { action: input.action as CloudflareTarget['action'], mode: input.mode as CloudflareTarget['mode'], executable: input.executable };
      if (t.action === 'run') {
        if (!this.active()) return fail('CLOUDFLARE_OAUTH');
        if (t.mode === 'named') {
          if (typeof input.tunnelID !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.tunnelID)) return fail('CLOUDFLARE_ID');
          if (!absolutePath(input.credentialsFile)) return fail('CLOUDFLARE_CREDENTIALS');
          try { if (!(await fs.stat(input.credentialsFile)).isFile()) return fail('CLOUDFLARE_CREDENTIALS'); await fs.access(input.credentialsFile, constants.R_OK); } catch { return fail('CLOUDFLARE_CREDENTIALS'); }
          t.tunnelID = input.tunnelID; t.credentialsFile = input.credentialsFile; t.publicURL = cloudflarePublicOrigin(input.publicURL);
        } else if (input.tunnelID || input.credentialsFile || input.publicURL) return fail('CLOUDFLARE_TARGET');
      }
      cancelled();
      folder = await fs.mkdtemp(join(tmpdir(), 'onemcp-cloudflared-'));
      await fs.chmod(folder, 0o700);
      // An explicit, empty configuration prevents ambient ~/.cloudflared or /etc configuration
      // from changing the origin, credentials, metrics bind address, or ingress routes.
      const config = join(folder, 'config.yml');
      await fs.writeFile(config, '{}\n', { mode: 0o600, flag: 'wx' });
      const args = t.action === 'doctor' ? ['--version'] : ['tunnel', '--config', config, '--no-autoupdate', '--metrics', '127.0.0.1:0', '--loglevel', 'info',
        ...(t.mode === 'quick' ? ['--url', `http://127.0.0.1:${this.port}`] : ['run', '--credentials-file', t.credentialsFile!, '--url', `http://127.0.0.1:${this.port}`, t.tunnelID!])];
      cancelled();
      if (t.action === 'run') {
        if (!this.active()) return fail('CLOUDFLARE_OAUTH');
        if (t.publicURL) { this.setOrigin(t.publicURL); originSet = true; }
        if (!this.active()) return fail('CLOUDFLARE_OAUTH');
      }
      const child = this.launch(t.executable, args, { stdio: ['ignore', 'pipe', 'pipe'], shell: false,
        cwd: folder, env: { PATH: process.env.PATH, HOME: folder, LANG: 'C', LC_ALL: 'C', NO_COLOR: '1' } });
      let resolveClosed!: () => void;
      const r: Running = { target: t, child, folder, configurationFingerprints: cloudflareConfigurationFingerprints({ ...t, publicURL: t.action === 'run' && t.mode === 'named' ? input.publicURL as string : t.publicURL }, this.port), lifetime: new AbortController(), checking: false, stopping: false,
        publicOrigin: t.publicURL, closed: new Promise(resolve => { resolveClosed = resolve; }) };
      this.running = r; folder = undefined;
      const inspect = (line: string) => {
        if (!this.current(r)) return;
        if (t.action === 'doctor') {
          const match = line.match(/^cloudflared version ([0-9]{4}\.[0-9]{1,2}\.[0-9]{1,3}(?:[-+][a-zA-Z0-9.-]{1,64})?)(?:\s|$)/);
          if (match) r.version = match[1];
          return;
        }
        r.metricsOrigin ??= cloudflareMetricsOrigin(line);
        if (t.mode === 'quick' && !r.publicOrigin) {
          const origin = quickTunnelOrigin(line);
          if (origin) {
            try { if (!this.active()) fail('CLOUDFLARE_OAUTH'); this.setOrigin(origin); if (!this.active()) fail('CLOUDFLARE_OAUTH'); r.publicOrigin = origin; }
            catch { r.failure = 'CLOUDFLARE_OAUTH'; void this.stop(); return; }
            this.status(r, 'Quick URL assigned; waiting for readiness and public OAuth metadata. Update the authorization-server audience for this session URL.');
          }
        }
        if (r.metricsOrigin && r.publicOrigin) void this.check(r);
      };
      // Keep only bounded, complete lines privately. Separate streams cannot be joined into a URL.
      const attach = (stream: NodeJS.ReadableStream | null) => {
        let tail = ''; let dropping = false;
        stream?.on('data', (chunk: Buffer) => {
          for (const piece of chunk.toString('utf8').split(/(?<=\n)/)) {
            const ended = piece.endsWith('\n');
            if (!dropping && tail.length + piece.length <= 8192) tail += piece;
            else { tail = ''; dropping = true; }
            if (ended) { if (!dropping) inspect(tail.trimEnd()); tail = ''; dropping = false; }
          }
        });
        stream?.once('end', () => { if (!dropping && tail) inspect(tail); tail = ''; });
      };
      attach(child.stdout); attach(child.stderr);
      child.once('close', code => {
        clearInterval(r.timer); clearTimeout(r.doctorTimer); r.lifetime.abort();
        if (this.running === r) this.running = undefined;
        // Keep authentication engaged until the process is gone, including graceful shutdown.
        if (t.action === 'run') { try { this.setOrigin(undefined); } catch { r.failure ??= 'CLOUDFLARE_OAUTH'; } }
        if (t.action === 'doctor' && (!r.version || code !== 0)) r.failure ??= 'CLOUDFLARE_VERSION';
        if (code !== 0 && !r.stopping) r.failure ??= 'CLOUDFLARE_FAILED';
        this.event({ action: t.action, mode: t.mode, running: false, ready: false, exitCode: code, configurationFingerprintVersion, configurationFingerprints: r.configurationFingerprints,
          ...(r.failure ? { errorCode: r.failure, message: messages[r.failure] } : {}),
          ...(t.action === 'doctor' && !r.failure ? { available: true, version: r.version } : {}),
          state: t.action === 'doctor' ? `Doctor ${r.failure ? 'failed' : 'passed'}` : r.failure ? 'Stopped after failure' : 'Stopped' });
        void fs.rm(r.folder, { recursive: true, force: true }).catch(() => undefined).finally(resolveClosed);
      });
      try {
        await new Promise<void>((resolve, reject) => {
          child.once('spawn', resolve);
          child.once('error', () => { r.failure = 'CLOUDFLARE_EXECUTABLE'; reject(new CloudflareActionError('CLOUDFLARE_EXECUTABLE')); });
        });
      } catch (error) { await r.closed; throw error; }
      if (generation !== this.generation) { await this.stop(); return fail('CLOUDFLARE_CANCELLED'); }
      if (!this.current(r)) return { key: this.recordKey, action: t.action, submitted: true, ready: false };
      this.status(r, t.action === 'doctor' ? 'Checking cloudflared version' : 'Process started; readiness unverified');
      if (t.action === 'doctor') {
        r.doctorTimer = setTimeout(() => { r.failure = 'CLOUDFLARE_VERSION'; void this.stop(); }, this.dependencies.doctorTimeoutMs ?? 5000);
        await r.closed;
        return { key: this.recordKey, action: 'doctor', available: !r.failure, ...(r.failure ? { errorCode: r.failure } : { version: r.version }), ready: false };
      }
      r.timer = setInterval(() => { void this.check(r); }, this.dependencies.pollIntervalMs ?? 1000);
      void this.check(r);
      return { key: this.recordKey, action: 'run', submitted: true, ready: false };
    } catch (error) {
      if (originSet && !this.running) { try { this.setOrigin(undefined); } catch { /* Keep original safe error. */ } }
      if (error instanceof CloudflareActionError) throw error;
      return fail('CLOUDFLARE_FAILED');
    } finally { if (folder) await fs.rm(folder, { recursive: true, force: true }).catch(() => undefined); this.starting = false; }
  }
  private async check(r: Running): Promise<void> {
    if (!this.current(r) || r.checking) return;
    if (!this.active()) { r.failure = 'CLOUDFLARE_OAUTH'; await this.stop(); return; }
    r.checking = true;
    let localReady = false;
    try {
      if (!r.metricsOrigin || !r.publicOrigin) { this.status(r, 'Waiting for a validated public URL and loopback readiness endpoint'); return; }
      const signal = () => AbortSignal.any([r.lifetime.signal, AbortSignal.timeout(this.dependencies.probeTimeoutMs ?? 2500)]);
      const local = await this.fetcher(`${r.metricsOrigin}/ready`, { method: 'GET', redirect: 'manual', credentials: 'omit', signal: signal() });
      await local.body?.cancel();
      if (!this.current(r)) return;
      localReady = local.status === 200 && !local.redirected;
      const publicMetadataReady = localReady && await probeCloudflareMetadata(r.publicOrigin, this.fetcher, signal(), { issuer: this.oauth.expectedIssuer?.(), scopes: this.oauth.expectedScopes?.() });
      if (!this.current(r)) return;
      if (!this.active()) { r.failure = 'CLOUDFLARE_OAUTH'; await this.stop(); return; }
      this.status(r, localReady && publicMetadataReady
        ? (r.target.mode === 'quick' ? 'Tunnel and OAuth metadata reachable. Quick URL audience, OAuth login, and tool call remain unverified.' : 'Tunnel and OAuth metadata reachable; OAuth login and tool call remain unverified.')
        : localReady ? 'Local tunnel ready; waiting for public OAuth metadata' : 'Waiting for Cloudflare connection readiness',
        { ready: localReady && publicMetadataReady, localReady, publicMetadataReady });
    } catch { if (this.current(r)) this.status(r, 'Waiting for bounded loopback/public OAuth metadata checks', { localReady, publicMetadataReady: false }); }
    finally { r.checking = false; }
  }
  async stop(key = this.recordKey): Promise<void> {
    if (key !== this.recordKey) return;
    this.generation++;
    const r = this.running;
    if (!r) return;
    if (r.stopPromise) return r.stopPromise;
    r.stopping = true; r.lifetime.abort(); clearInterval(r.timer); clearTimeout(r.doctorTimer);
    this.status(r, 'Stopping');
    r.child.kill('SIGTERM');
    const force = setTimeout(() => r.child.kill('SIGKILL'), this.dependencies.stopTimeoutMs ?? 4000);
    r.stopPromise = r.closed.finally(() => clearTimeout(force));
    return r.stopPromise;
  }
  async stopAll(): Promise<void> { await this.stop(); }
}
