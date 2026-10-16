/** Original MCP Harbor gateway. Loopback-only; real macOS/tunnel integration requires user acceptance. */
import http, { IncomingMessage, ServerResponse } from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { isAbsolute, dirname } from 'node:path';
import { createInterface } from 'node:readline';
import { parseRequest, serveControl, ControlRequest, ControlResponse } from './control.js';
import { TunnelManager } from './tunnels.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { ListToolsRequestSchema, CallToolRequestSchema, ToolListChangedNotificationSchema, Tool } from '@modelcontextprotocol/sdk/types.js';

type Config = { id: string; name: string; executable: string; arguments: string[];
  environment: Record<string, string>; workingDirectory?: string; allowedTools: string[] };
type Managed = { config: Config; client: Client; transport: StdioClientTransport; tools: Tool[];
  ready: boolean; closing: boolean; calls: number; revision: number; catalogRevision: number; lifetime: AbortController;
  discovery?: Promise<Tool[]>; stopping?: Promise<void> };

const managed = new Map<string, Managed>();
const stopping = new Set<Promise<void>>();
const activeRequests = new Set<Server>();
let closing = false;
let inflight = 0;
const portIndex = process.argv.indexOf('--port');
const port = portIndex >= 0 ? Number(process.argv[portIndex + 1]) : 8787;
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid loopback port');
const recentEvents: Array<{sequence:number; event:object}> = [];
let eventSequence = 0;
const emit = (event: object) => {
  const type = (event as {type?:string}).type;
  if (type !== 'response' && type !== 'tools') {
    recentEvents.push({sequence: ++eventSequence, event});
    if (recentEvents.length > 100) recentEvents.shift();
  }
  process.stdout.write(JSON.stringify(event) + '\n');
};
const MAX_BODY = 1024 * 1024;
const MAX_REQUESTS = 32;
const tunnelManager = new TunnelManager(port, emit, id => managed.get(id)?.ready === true);
const controlIndex = process.argv.indexOf('--control-socket');
const workspaceIndex = process.argv.indexOf('--workspace-id');
const workspaceID = workspaceIndex >= 0 ? process.argv[workspaceIndex + 1] : 'default';
const instanceID = randomUUID();
const controlRoot = controlIndex >= 0 ? realpathSync(dirname(dirname(process.argv[controlIndex + 1] ?? ''))) : null;
let closeControl: (() => Promise<void>) | undefined;
let chain = Promise.resolve();
function dispatch(command: ControlRequest): Promise<ControlResponse> {
  const operation = chain.then(() => perform(command));
  chain = operation.then(() => undefined, () => undefined);
  return operation;
}
if (controlIndex >= 0) {
  try { closeControl = await serveControl(process.argv[controlIndex + 1] ?? '', dispatch); }
  catch { process.stderr.write('Private control socket unavailable; inspect ownership and an existing gateway before retrying.\n'); process.exit(1); }
}

function safeMessage(value: unknown, config?: Config): string {
  let text = value instanceof Error ? value.message : String(value);
  // Sort longest-first so an overlapping short value cannot reveal a longer secret's suffix.
  const secrets = Object.values(config?.environment ?? {}).filter((x): x is string => typeof x === 'string' && x.length > 0);
  for (const secret of secrets.sort((a, b) => b.length - a.length)) text = text.split(secret).join('[redacted]');
  return text.replace(/Bearer\s+\S+/gi, 'Bearer [redacted]')
    .replace(/(api[_-]?key|token|password|secret)([=:]\s*)\S+/gi, '$1$2[redacted]').slice(0, 1000);
}
function validated(raw: unknown): Config {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('Missing server config');
  const c = raw as Config;
  if (typeof c.id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(c.id)) throw new Error('Invalid server id');
  if (typeof c.name !== 'string' || c.name.length > 100) throw new Error('Invalid display name');
  if (typeof c.executable !== 'string' || !isAbsolute(c.executable) || c.executable.includes('\0')) throw new Error('Executable must be an absolute path');
  if (!Array.isArray(c.arguments) || c.arguments.length > 128 || c.arguments.some(x => typeof x !== 'string' || x.length > 8192 || x.includes('\0'))) throw new Error('Invalid arguments');
  if (!Array.isArray(c.allowedTools) || c.allowedTools.length > 500 || c.allowedTools.some(x => typeof x !== 'string' || !x || x.length > 256 || x.includes('\0') || x === '*')) throw new Error('Explicit tool allowlist is required');
  if (!c.environment || Array.isArray(c.environment) || typeof c.environment !== 'object' || Object.keys(c.environment).length > 128) throw new Error('Invalid environment');
  for (const [key, value] of Object.entries(c.environment)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) || typeof value !== 'string' || value.length > 65536 || value.includes('\0')) throw new Error('Invalid environment item');
  }
  if (c.workingDirectory !== undefined && c.workingDirectory !== '' && (typeof c.workingDirectory !== 'string' || !isAbsolute(c.workingDirectory) || c.workingDirectory.includes('\0'))) throw new Error('Working directory must be absolute');
  return c;
}
function isCurrent(m: Managed): boolean { return !closing && !m.closing && managed.get(m.config.id) === m; }
function emitTools(m: Managed): void {
  emit({ type: 'tools', serverId: m.config.id, tools: m.tools.map(t => ({ name: t.name, description: t.description,
    publicName: publicName(m.config.id, t.name), inputSchema: t.inputSchema, outputSchema: t.outputSchema, annotations: t.annotations })) });
}
async function discover(m: Managed): Promise<Tool[]> {
  if (!isCurrent(m)) throw new Error('Server is not running');
  // HTTP clients and the native UI share one bounded refresh per upstream.
  if (m.discovery) return m.discovery.catch(error => { throw new Error(safeMessage(error, m.config)); });
  const pending = (async () => {
    const signal = AbortSignal.any([m.lifetime.signal, AbortSignal.timeout(15000)]);
    for (let revisionAttempt = 0; revisionAttempt < 3; revisionAttempt++) {
      const revision = m.revision;
      const all: Tool[] = []; let cursor: string | undefined;
      const cursors = new Set<string>(); const names = new Set<string>();
      for (let page = 0; page < 20; page++) {
        const result = await m.client.listTools(cursor ? { cursor } : {}, { timeout: 15000, signal });
        for (const tool of result.tools) {
          if (!tool.name || tool.name.length > 256 || names.has(tool.name)) throw new Error('Invalid or duplicate upstream tool name');
          names.add(tool.name); all.push(tool);
        }
        if (all.length > 1000) throw new Error('Tool catalogue exceeds limit');
        cursor = result.nextCursor;
        if (!cursor) break;
        if (cursors.has(cursor)) throw new Error('Repeated tools cursor');
        cursors.add(cursor);
        if (page === 19) throw new Error('Too many tools pages');
      }
      if (!isCurrent(m)) throw new Error('Server stopped during discovery');
      if (revision !== m.revision) continue; // Ignore a result superseded by list_changed.
      m.tools = all; m.catalogRevision = revision;
      if (m.ready) emitTools(m);
      return all;
    }
    throw new Error('Upstream tool catalogue is changing too frequently');
  })();
  m.discovery = pending;
  try { return await pending; }
  catch (error) {
    // Never keep routing a stale catalogue after a failed refresh.
    m.tools = [];
    if (isCurrent(m) && m.ready) emitTools(m);
    throw new Error(safeMessage(error, m.config));
  } finally { if (m.discovery === pending) m.discovery = undefined; }
}
async function stopManaged(m: Managed): Promise<void> {
  if (m.stopping) return m.stopping;
  m.closing = true; m.ready = false; m.tools = []; m.lifetime.abort();
  if (managed.get(m.config.id) === m) managed.delete(m.config.id);
  const pending = (async () => {
    try { await m.client.close(); } finally {
      await m.transport.close().catch(() => undefined);
      emit({ type: 'serverStatus', serverId: m.config.id, status: 'stopped' });
    }
  })();
  m.stopping = pending; stopping.add(pending);
  try { await pending; } finally { stopping.delete(pending); }
}
async function stop(id: string): Promise<void> { const m = managed.get(id); if (m) await stopManaged(m); }
async function start(raw: unknown): Promise<void> {
  const config = validated(raw);
  if (managed.has(config.id)) throw new Error('Server already running; stop before replacing configuration');
  if (managed.size >= 16) throw new Error('At most 16 managed servers');
  const transport = new StdioClientTransport({ command: config.executable, args: config.arguments,
    env: config.environment, cwd: config.workingDirectory || undefined, stderr: 'pipe', maxBufferSize: 4 * 1024 * 1024 });
  const client = new Client({ name: 'mcp-harbor', version: '0.1.0' }, { capabilities: {} });
  const m: Managed = { config, transport, client, tools: [], ready: false, closing: false, calls: 0, revision: 0, catalogRevision: -1, lifetime: new AbortController() };
  // Never forward raw upstream payloads, credentials or tool arguments to UI logs.
  let lastStderrReport = 0;
  transport.stderr?.on('data', () => {
    // Rate-limit diagnostics from noisy or broken processes; always drain stderr.
    if (Date.now() - lastStderrReport < 1000) return;
    lastStderrReport = Date.now();
    emit({ type: 'log', serverId: config.id, message: 'Upstream stderr received; hidden to protect credentials' });
  });
  client.onerror = () => emit({ type: 'log', serverId: config.id, message: 'Upstream protocol error; payload hidden to protect private data' });
  client.onclose = () => {
    if (!m.closing && managed.get(config.id) === m) {
      m.ready = false; m.tools = []; m.lifetime.abort(); managed.delete(config.id);
      emit({ type: 'serverStatus', serverId: config.id, status: 'error', message: 'MCP process or connection closed' });
    }
  };
  client.setNotificationHandler(ToolListChangedNotificationSchema, async () => {
    if (!isCurrent(m)) return;
    m.revision++; m.tools = [];
    if (!m.ready) return; // Initial discovery will retry if this changes its revision.
    emitTools(m);
    try {
      await discover(m);
      if (isCurrent(m) && m.catalogRevision !== m.revision) await discover(m);
    }
    catch { if (isCurrent(m)) emit({ type: 'log', serverId: config.id, message: 'Tool catalogue refresh failed; tools hidden until discovery succeeds' }); }
  });
  managed.set(config.id, m);
  try {
    await client.connect(transport, { timeout: 15000, signal: m.lifetime.signal });
    await discover(m);
    if (!isCurrent(m)) throw new Error('Server stopped during startup');
    m.ready = true;
    emit({ type: 'serverStatus', serverId: config.id, status: 'running' });
    emitTools(m);
  } catch (error) {
    await stopManaged(m);
    throw new Error(safeMessage(error, config));
  }
}
// Stable <64-character aggregate aliases. A hash prevents truncation collisions.
function publicName(id: string, tool: string): string {
  const hash = createHash('sha256').update(id + '\0' + tool).digest('hex').slice(0, 10);
  return `${id.replace(/[^A-Za-z0-9_]/g, '_').slice(0, 10)}__${tool.replace(/[^A-Za-z0-9_]/g, '_').slice(0, 39)}_${hash}`;
}
function catalogue(serverId?: string): Array<{ name: string; tool: Tool; managed: Managed }> {
  const entries: Array<{ name: string; tool: Tool; managed: Managed }> = [];
  for (const m of managed.values()) {
    if (!m.ready || m.closing || (serverId && serverId !== m.config.id)) continue;
    for (const tool of m.tools) {
      if (!m.config.allowedTools.includes(tool.name)) continue;
      entries.push({ name: serverId ? tool.name : publicName(m.config.id, tool.name), tool, managed: m });
    }
  }
  return entries;
}
function json(res: ServerResponse, status: number, value: object): void {
  if (res.destroyed || res.writableEnded) return;
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(value));
}
class BodyError extends Error { constructor(readonly status: number, message: string) { super(message); } }
function body(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let bytes = 0; const parts: Buffer[] = [];
    const cleanup = () => { req.off('data', data); req.off('end', end); req.off('error', failed); req.off('aborted', aborted); };
    const failed = (error: Error) => { cleanup(); reject(error); };
    const aborted = () => failed(new BodyError(400, 'Request aborted'));
    const data = (chunk: Buffer) => {
      bytes += chunk.length;
      if (bytes > MAX_BODY) { cleanup(); req.resume(); reject(new BodyError(413, 'JSON body exceeds limit')); return; }
      parts.push(chunk);
    };
    const end = () => {
      cleanup();
      try { resolve(JSON.parse(Buffer.concat(parts).toString('utf8'))); }
      catch { reject(new BodyError(400, 'Invalid JSON')); }
    };
    req.on('data', data); req.once('end', end); req.once('error', failed); req.once('aborted', aborted);
  });
}
function allowedHost(req: IncomingMessage): boolean {
  const host = req.headers.host?.toLowerCase();
  return host === `127.0.0.1:${port}` || host === `localhost:${port}`;
}
const httpServer = http.createServer((req, res) => {
  void handleHttp(req, res).catch(() => { if (!res.headersSent) json(res, 500, { error: 'MCP request failed' }); else res.destroy(); });
});
async function handleHttp(req: IncomingMessage, res: ServerResponse): Promise<void> {
  if (closing) return json(res, 503, { error: 'Shutting down' });
  if (!allowedHost(req)) return json(res, 403, { error: 'Only local Host headers accepted' });
  // Reject even an empty Origin header. Never expose an unauthenticated browser endpoint.
  if (req.headers.origin !== undefined) return json(res, 403, { error: 'Browser Origin requests are not allowed' });
  let path: string;
  try {
    if (!req.url?.startsWith('/') || req.url.startsWith('//')) throw new Error('Invalid path');
    path = new URL(req.url, 'http://127.0.0.1').pathname;
  } catch { return json(res, 400, { error: 'Invalid request target' }); }
  if (path === '/health' && req.method === 'GET') return json(res, 200, { status: 'ready', managedServers: [...managed.values()].filter(m => m.ready).length });
  const individual = /^\/servers\/([A-Za-z0-9_-]{1,64})\/mcp$/.exec(path);
  if (path !== '/mcp' && !individual) return json(res, 404, { error: 'Unknown endpoint' });
  const serverId = individual?.[1];
  if (serverId && !managed.get(serverId)?.ready) return json(res, 404, { error: 'Server is not running' });
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return json(res, 405, { error: 'Stateless Streamable HTTP accepts POST only; no SSE resumability' }); }
  if (req.headers['content-type']?.split(';', 1)[0]?.trim().toLowerCase() !== 'application/json') return json(res, 415, { error: 'Use application/json' });
  if (Number(req.headers['content-length'] ?? 0) > MAX_BODY) return json(res, 413, { error: 'JSON body exceeds limit' });
  if (inflight >= MAX_REQUESTS) return json(res, 429, { error: 'Busy' });
  inflight++;
  res.once('close', () => { inflight--; });
  let payload: unknown;
  try { payload = await body(req); }
  catch (error) { return json(res, error instanceof BodyError ? error.status : 400, { error: 'Invalid or oversized JSON' }); }
  if (res.destroyed || closing) return;
  if (Array.isArray(payload)) return json(res, 400, { error: 'JSON-RPC batches are not supported' });
  const bridge = new Server({ name: 'mcp-harbor', version: '0.1.0' }, { capabilities: { tools: {} } });
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  activeRequests.add(bridge);
  bridge.setRequestHandler(ListToolsRequestSchema, async () => {
    const sources = [...managed.values()].filter(m => m.ready && (!serverId || m.config.id === serverId));
    const results = await Promise.allSettled(sources.map(m => discover(m)));
    // One unhealthy process must not hide tools from every other managed server.
    if (serverId && results.some(result => result.status === 'rejected')) throw new Error('Upstream tool discovery failed');
    return { tools: catalogue(serverId).map(({ name, tool, managed: m }) => ({ ...tool, name,
      description: `[${m.config.name}] ${tool.description ?? ''}` })) };
  });
  bridge.setRequestHandler(CallToolRequestSchema, async (request, extra) => {
    const route = catalogue(serverId).find(x => x.name === request.params.name);
    if (!route || !isCurrent(route.managed)) throw new Error('Tool is not enabled');
    const m = route.managed;
    if (m.calls >= 4) throw new Error('Upstream concurrency limit reached');
    m.calls++;
    emit({ type: 'log', serverId: m.config.id, message: `Calling enabled tool: ${route.tool.name}` });
    try {
      return await m.client.callTool({ name: route.tool.name, arguments: request.params.arguments ?? {} }, undefined,
        { timeout: 60000, signal: AbortSignal.any([extra.signal, m.lifetime.signal]) });
    } catch (error) {
      return { isError: true, content: [{ type: 'text' as const, text: safeMessage(error, m.config) }] };
    } finally { m.calls--; }
  });
  let disposed = false;
  const dispose = () => {
    if (disposed) return; disposed = true; activeRequests.delete(bridge);
    // Closing the SDK bridge aborts extra.signal and propagates disconnect cancellation upstream.
    void bridge.close().catch(() => undefined);
  };
  res.once('close', dispose);
  try { await bridge.connect(transport); await transport.handleRequest(req, res, payload); }
  catch { if (!res.headersSent) json(res, 500, { error: 'MCP request failed' }); else res.destroy(); dispose(); }
}
httpServer.requestTimeout = 70000;
httpServer.headersTimeout = 10000;
httpServer.on('error', error => { emit({ type: 'log', message: safeMessage(error) }); void shutdown(1); });
httpServer.listen(port, '127.0.0.1', () => { if (!closing) emit({ type: 'ready', port }); });

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on('line', line => {
  if (Buffer.byteLength(line) > MAX_BODY) { emit({ type: 'log', message: 'Oversized control line rejected' }); return; }
  try {
    const command = parseRequest(JSON.parse(line));
    void dispatch(command).then(emit);
  } catch { emit({ type: 'log', message: 'Malformed control JSON' }); }
});
async function perform(command: ControlRequest): Promise<ControlResponse> {
  try {
    if (closing) throw new Error('Gateway is shutting down');
    if (command.params?.expectedInstanceID !== undefined && command.params.expectedInstanceID !== instanceID) throw new Error('Gateway instance changed; reconnect before issuing commands');
    let result: unknown = null;
    const rawID = command.params?.serverId;
    const requireID = () => {
      if (typeof rawID !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(rawID)) throw new Error('Invalid server id');
      return rawID;
    };
    switch (command.method) {
      case 'status': case 'snapshot': result = { protocolVersion: 1, instanceID, controlRoot, pid: process.pid, port, workspaceID,
        servers: [...managed.values()].map(m => ({ id: m.config.id, name: m.config.name, running: m.ready, allowedTools: m.config.allowedTools, toolCount: m.tools.length, ...(command.method === 'snapshot' ? {tools: m.tools.map(t => ({...t, publicName: publicName(m.config.id,t.name)}))} : {}) })),
        ...(command.method === 'snapshot' ? {events: recentEvents, sequence: eventSequence} : {}),
        tunnels: tunnelManager.snapshot() }; break;
      case 'startServer': await start(command.params?.server); break;
      case 'stopServer': { const id = requireID(); await tunnelManager.stopAll(); await stop(id); break; }
      case 'listTools': {
        const m = managed.get(requireID());
        if (!m?.ready) throw new Error('Server is not running');
        await discover(m);
        result = m.tools.map(t => ({ ...t, allowed: m.config.allowedTools.includes(t.name), publicName: publicName(m.config.id, t.name) })); break;
      }
      case 'tunnelAction': result = await tunnelManager.action(command.params); break;
      case 'stopTunnel': {
        const key = command.params?.key;
        if (typeof key !== 'string' || !/^[\w-]{1,64}$/.test(key)) throw new Error('Invalid tunnel key');
        await tunnelManager.stop(key); break;
      }
      case 'stopAllTunnels': await tunnelManager.stopAll(); break;
      case 'shutdown': setTimeout(() => { void shutdown(0); }, 100); break;
      default: throw new Error('Unknown management method');
    }
    return { type: 'response', id: command.id, ok: true, result };
  } catch (error) {
    const server = command.params?.server as Config | undefined;
    const message = command.method === 'tunnelAction' ? 'Tunnel operation rejected; verify executable, unique profile, tunnel ID, session key and running server' : safeMessage(error, server);
    if (command.method === 'startServer' && typeof server?.id === 'string' && !managed.get(server.id)?.ready) {
      emit({ type: 'serverStatus', serverId: server.id, status: 'error', message });
    }
    return { type: 'response', id: command.id, ok: false, error: message };
  }
}
async function shutdown(code = 0): Promise<void> {
  if (closing) return; closing = true;
  httpServer.close();
  const forceExit = setTimeout(() => { httpServer.closeAllConnections(); process.exit(code); }, 8000);
  forceExit.unref();
  await tunnelManager.stopAll();
  await closeControl?.();
  await Promise.all([...activeRequests].map(bridge => bridge.close().catch(() => undefined)));
  await Promise.all([...managed.values()].map(m => stopManaged(m).catch(() => undefined)));
  await Promise.allSettled([...stopping]);
  httpServer.closeAllConnections();
  process.exitCode = code; lines.close(); process.stdin.pause();
}
lines.on('close', () => { if (!closing) void shutdown(); });
process.once('SIGTERM', () => { void shutdown(); });
process.once('SIGINT', () => { void shutdown(); });
