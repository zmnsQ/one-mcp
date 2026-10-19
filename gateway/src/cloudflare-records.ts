/** Record-scoped Cloudflare processes. Only MCP and its OAuth discovery are exposed. */
import { realpath } from 'node:fs/promises';
import { resolve } from 'node:path';
import http, { IncomingHttpHeaders, Server } from 'node:http';
import { configurationFingerprint } from './configuration-fingerprints.js';
import { CloudflareActionError, CloudflareDependencies, CloudflareOAuthGuard, CloudflareTarget, CloudflareTunnelManager } from './cloudflare.js';

export type CloudflareRecordTarget = CloudflareTarget & { key: string; serverIDs: string[] };
export function cloudflareRecordKey(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(value)) throw new CloudflareActionError('CLOUDFLARE_TARGET');
  return value;
}
const hopHeaders = new Set(['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade']);
function safeHeaders(headers: IncomingHttpHeaders): IncomingHttpHeaders {
  const connectionTokens = String(headers.connection ?? '').toLowerCase().split(',').map(token => token.trim());
  return Object.fromEntries(Object.entries(headers).filter(([key]) => !hopHeaders.has(key) && !connectionTokens.includes(key) && !key.startsWith('x-forwarded-') && key !== 'forwarded' && key !== 'host'));
}
export type CloudflareRecordProxy = { port: number; close(): Promise<void> };
/** Raw request targets are matched without URL normalization, so encoded/path traversal cannot escape. */
export async function createCloudflareRecordProxy(gatewayPort: number, key: string): Promise<CloudflareRecordProxy> {
  key = cloudflareRecordKey(key);
  if (!Number.isInteger(gatewayPort) || gatewayPort < 1024 || gatewayPort > 65535) throw new Error('Invalid loopback port');
  const base = `/tunnels/${encodeURIComponent(key)}`;
  const upstreams = new Set<http.ClientRequest>();
  const server: Server = http.createServer((request, response) => {
    if (request.headers.origin !== undefined) { response.writeHead(403); response.end(); request.resume(); return; }
    if (upstreams.size >= 64) { response.writeHead(503); response.end(); request.resume(); return; }
    const maxBody = 8 * 1024 * 1024;
    if (Number(request.headers['content-length'] ?? 0) > maxBody) { response.writeHead(413); response.end(); request.resume(); return; }
    const raw = request.url ?? '';
    const queryIndex = raw.indexOf('?');
    const path = queryIndex < 0 ? raw : raw.slice(0, queryIndex);
    const query = queryIndex < 0 ? '' : raw.slice(queryIndex);
    let target: string;
    if (path === '/mcp' && ['GET', 'POST', 'DELETE'].includes(request.method ?? '')) target = `${base}/mcp${query}`;
    else if (['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp'].includes(path) && ['GET', 'HEAD'].includes(request.method ?? '') && !query) target = `/.well-known/oauth-protected-resource${base}/mcp`;
    else { response.writeHead(404, { 'content-type': 'text/plain' }); response.end('Not found'); request.resume(); return; }
    const upstream = http.request({ hostname: '127.0.0.1', port: gatewayPort, path: target, method: request.method, headers: safeHeaders(request.headers) }, result => {
      response.writeHead(result.statusCode ?? 502, safeHeaders(result.headers));
      result.on('error', () => response.destroy());
      result.pipe(response);
    });
    upstreams.add(upstream);
    upstream.on('close', () => upstreams.delete(upstream));
    upstream.on('error', () => { if (!response.headersSent) response.writeHead(502); response.end(); });
    let bytes = 0;
    request.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > maxBody) { upstream.destroy(); if (!response.headersSent) response.writeHead(413); response.end(); request.destroy(); }
    });
    upstream.setTimeout(300000, () => upstream.destroy());
    request.on('aborted', () => upstream.destroy());
    response.on('close', () => upstream.destroy());
    request.pipe(upstream);
  });
  // Cloudflared cannot use upgrades/CONNECT to reach other local services.
  server.on('upgrade', (_request, socket) => socket.destroy());
  server.on('connect', (_request, socket) => socket.destroy());
  server.headersTimeout = 15000;
  server.requestTimeout = 30000;
  server.maxHeadersCount = 100;
  server.maxConnections = 128;
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => { server.removeListener('error', reject); resolve(); });
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Missing loopback listener');
  let closing: Promise<void> | undefined;
  return { port: address.port, close: () => closing ??= new Promise<void>(resolve => {
    for (const upstream of upstreams) upstream.destroy();
    server.close(() => resolve()); server.closeAllConnections();
  }) };
}

type Entry = { record: CloudflareRecordTarget; credentialsPath?: string; manager?: CloudflareTunnelManager; proxy?: CloudflareRecordProxy; cancelled: boolean; pending?: Promise<unknown> };
/** OAuth factory must return a record-local guard; never mutate the gateway-wide audience. */
export class CloudflareRecordPool {
  private entries = new Map<string, Entry>();
  private results = new Map<string, object>();
  constructor(private gatewayPort: number, private emit: (event: object) => void,
    private guardForRecord: (record: CloudflareRecordTarget) => CloudflareOAuthGuard,
    private dependencies: CloudflareDependencies = {}) {}
  snapshot(): object[] { return [...this.results.values()].map(value => structuredClone(value)); }
  async action(raw: unknown): Promise<unknown> {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new CloudflareActionError('CLOUDFLARE_TARGET');
    const input = raw as Record<string, unknown>;
    const key = cloudflareRecordKey(input.key);
    if (!['doctor', 'run'].includes(String(input.action)) || !['quick', 'named'].includes(String(input.mode)) ||
      Object.keys(input).some(field => !['key', 'serverIDs', 'action', 'executable', 'mode', 'tunnelID', 'credentialsFile', 'publicURL'].includes(field))) throw new CloudflareActionError('CLOUDFLARE_TARGET');
    if (!Array.isArray(input.serverIDs) || (input.action !== 'doctor' && !input.serverIDs.length) || input.serverIDs.length > 256 || input.serverIDs.some(id => typeof id !== 'string' || !id || id.length > 256 || /[\x00-\x1f\x7f]/.test(id)) || new Set(input.serverIDs).size !== input.serverIDs.length) throw new CloudflareActionError('CLOUDFLARE_TARGET');
    if (this.entries.has(key)) throw new CloudflareActionError('CLOUDFLARE_BUSY');
    const record = structuredClone(raw) as CloudflareRecordTarget;
    if (record.mode === 'named' && record.action === 'run') {
      for (const existing of this.entries.values()) {
        if (existing.record.mode === 'named' && existing.record.action === 'run' && (
          typeof record.tunnelID === 'string' && typeof existing.record.tunnelID === 'string' && record.tunnelID.toLowerCase() === existing.record.tunnelID.toLowerCase() ||
          typeof record.credentialsFile === 'string' && typeof existing.record.credentialsFile === 'string' && resolve(record.credentialsFile) === resolve(existing.record.credentialsFile)
        )) throw new CloudflareActionError('CLOUDFLARE_BUSY');
      }
    }
    const entry: Entry = { record, cancelled: false };
    this.entries.set(key, entry);
    entry.pending = (async () => {
      try {
        if (record.action === 'run' && record.mode === 'named' && typeof record.credentialsFile === 'string') {
          entry.credentialsPath = await realpath(record.credentialsFile).catch(() => undefined);
          if (entry.credentialsPath && [...this.entries.values()].some(other => other !== entry && other.credentialsPath === entry.credentialsPath)) throw new CloudflareActionError('CLOUDFLARE_BUSY');
        }
        if (entry.cancelled) throw new CloudflareActionError('CLOUDFLARE_CANCELLED');
        const guard = this.guardForRecord(record);
        entry.proxy = await createCloudflareRecordProxy(this.gatewayPort, key);
        if (entry.cancelled) throw new CloudflareActionError('CLOUDFLARE_CANCELLED');
        entry.manager = new CloudflareTunnelManager(entry.proxy.port, event => {
          const fingerprints = (event as { configurationFingerprints?: Record<string, string> }).configurationFingerprints;
          const status = { ...event, serverIDs: [...record.serverIDs], ...(fingerprints ? { configurationFingerprints: {
            ...fingerprints,
            endpoint: configurationFingerprint([`http://127.0.0.1:${this.gatewayPort}/tunnels/${key}/mcp`]),
            serverIDs: configurationFingerprint([...record.serverIDs].sort((a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'))))
          } } : {}) };
          this.results.set(key, status); this.emit(status);
          if ((event as { running?: boolean }).running === false) {
            void entry.proxy?.close();
            if (this.entries.get(key) === entry) this.entries.delete(key);
          }
        }, guard, this.dependencies, key);
        const { serverIDs: _serverIDs, ...target } = record;
        const result = await entry.manager.action(target);
        if (record.action === 'doctor' || !entry.manager.snapshot().some(event => (event as { running?: boolean }).running)) {
          await entry.proxy.close(); if (this.entries.get(key) === entry) this.entries.delete(key);
        }
        return result;
      } catch (error) {
        await entry.manager?.stopAll(); await entry.proxy?.close();
        if (this.entries.get(key) === entry) this.entries.delete(key);
        throw error;
      }
    })();
    return entry.pending;
  }
  async stop(key: string): Promise<void> {
    const entry = this.entries.get(key);
    if (!entry) return;
    entry.cancelled = true;
    await entry.manager?.stopAll();
    await entry.pending?.catch(() => undefined);
    await entry.proxy?.close();
    if (this.entries.get(key) === entry) this.entries.delete(key);
  }
  async stopAll(): Promise<void> { await Promise.all([...this.entries.keys()].map(key => this.stop(key))); }
}
