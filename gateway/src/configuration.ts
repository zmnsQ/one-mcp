import fs from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, isAbsolute } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { z } from 'zod';
import { privateDirectory } from './control.js';
const identifier = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/);
const cleanString = (max: number) => z.string().max(max).regex(/^[^\0]*$/);
const unique = (values: string[]) => new Set(values).size === values.length;
export const serverSchema = z.object({
    id: identifier, name: cleanString(100).min(1), executable: cleanString(4096), arguments: z.array(cleanString(8191)).max(128),
    workingDirectory: cleanString(4096), environmentKeys: z.array(z.string().regex(/^[A-Za-z_][A-Za-z0-9_]*$/).refine(s => s !== '__tunnel_key')).max(128).refine(unique),
    allowedTools: z.array(cleanString(256).min(1).refine(s => s !== '*')).max(500).refine(unique),
    tunnelID: cleanString(256), profile: cleanString(64), startWithAll: z.boolean().optional()
});
// Public configuration only. Runtime keys and OAuth tokens never enter settings.json.
export const remoteConnectionSchema = z.object({
  preferredTransport: z.enum(['openai', 'cloudflare']).optional(),
  oauth: z.object({enabled: z.boolean(), publicURL: cleanString(4096), issuer: cleanString(4096), jwksURL: cleanString(4096), scope: cleanString(512)}).optional(),
  cloudflare: z.object({executable: cleanString(4096), mode: z.enum(['quick','named']), tunnelID: cleanString(256), credentialsFile: cleanString(4096), publicURL: cleanString(4096)}).optional()
}).strict();
export const tunnelRecordSchema = z.object({
    id: identifier, name: cleanString(100).min(1), serverIDs: z.array(identifier).max(16).refine(unique),
    transport: z.enum(['openai', 'cloudflare']), profile: cleanString(256), tunnelID: cleanString(256),
    profileFile: cleanString(4096).optional(), cloudflare: remoteConnectionSchema.shape.cloudflare,
    startWithAll: z.boolean().optional()
}).strict();
export type TunnelRecord = z.infer<typeof tunnelRecordSchema>;
export const preferencesSchema = z.object({
    nodePath: cleanString(4096), gatewayScript: cleanString(4096), tunnelClientPath: cleanString(4096), port: z.number().int().min(1024).max(65535),
    aggregateTunnelID: cleanString(256), aggregateProfile: cleanString(256), aggregateProfileFile: cleanString(4096).optional(), mode: z.enum(['aggregate', 'individual']),
  remoteConnection: remoteConnectionSchema.optional(),
    tunnelRecords: z.array(tunnelRecordSchema).max(32).refine(records => unique(records.map(r => r.id))).optional(),
    servers: z.array(serverSchema).max(16).refine(s => unique(s.map(x => x.id)))
});
export type Preferences = z.infer<typeof preferencesSchema>;
export type ServerConfig = z.infer<typeof serverSchema>;
const indexSchema = z.object({ activeID: identifier, workspaces: z.array(z.object({ id: identifier, name: cleanString(100).min(1) })).min(1).refine(w => unique(w.map(x => x.id))) })
    .refine(x => x.workspaces.some(w => w.id === x.activeID));
export const defaultRoot = () => join(homedir(), 'Library', 'Application Support', 'MCPHarbor');
export const socketPath = (root: string) => join(root, 'Runtime', 'control.sock');
export const defaults = (): Preferences => ({ nodePath: process.execPath, gatewayScript: '', tunnelClientPath: '', port: 8787, aggregateTunnelID: '', aggregateProfile: 'mcpharbor-aggregate', mode: 'aggregate', servers: [] });
export async function readJSON(path: string): Promise<{
    data: unknown;
    revision: string;
}> {
    const stat = await fs.lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1048576)
        throw new Error('Expected a regular JSON file up to 1 MiB');
    const bytes = await fs.readFile(path);
    if (bytes.length > 1048576)
        throw new Error('JSON exceeds 1 MiB');
    let data: unknown;
    try {
        data = JSON.parse(bytes.toString('utf8'));
    }
    catch {
        throw new Error('Invalid JSON; no changes made');
    }
    return { data, revision: createHash('sha256').update(bytes).digest('hex') };
}
export async function workspace(root: string, chosen?: string) {
    let index: z.infer<typeof indexSchema>;
    try {
        index = indexSchema.parse((await readJSON(join(root, 'workspaces.json'))).data);
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code !== 'ENOENT')
            throw e;
        index = { activeID: 'default', workspaces: [{ id: 'default', name: '默认工作空间' }] };
    }
    const id = chosen ?? index.activeID;
    if (!index.workspaces.some(w => w.id === id))
        throw new Error('Unknown workspace ID');
    const path = id === 'default' ? join(root, 'settings.json') : join(root, 'Workspaces', `${id}.json`);
    let loaded: {
        data: unknown;
        revision: string;
    };
    try {
        loaded = await readJSON(path);
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code !== 'ENOENT')
            throw e;
        loaded = { data: defaults(), revision: 'missing' };
    }
    const parsed = preferencesSchema.parse(loaded.data);
    const config: Preferences = {...parsed, tunnelRecords: configuredTunnelRecords(parsed)};
    return { root, id, path, index, config, revision: loaded.revision };
}
export type Workspace = Awaited<ReturnType<typeof workspace>>;
export async function acquireLease(root: string): Promise<() => Promise<void>> {
    await privateDirectory(root);
    const dir = join(root, '.configuration-lock'), token = randomUUID();
    try {
        await fs.mkdir(dir, { mode: 0o700 });
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code === 'EEXIST')
            throw new Error('Configuration write transaction is busy. Retry after the current writer finishes. Never remove a live lock; inspect config lock for a crashed owner.');
        throw e;
    }
    try {
        await fs.writeFile(join(dir, 'owner.json'), JSON.stringify({ pid: process.pid, token }), { flag: 'wx', mode: 0o600 });
    }
    catch (e) {
        await fs.rmdir(dir).catch(() => undefined);
        throw e;
    }
    return async () => {
        const value = (await readJSON(join(dir, 'owner.json'))).data as {
            token?: string;
        };
        if (value.token === token) {
            await fs.unlink(join(dir, 'owner.json'));
            await fs.rmdir(dir);
        }
    };
}
export async function lockInfo(root: string) {
    const dir = join(root, '.configuration-lock');
    try {
        const stat = await fs.lstat(dir);
        if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid?.() || (stat.mode & 0o077))
            throw new Error('Unsafe configuration lock');
        const value = (await readJSON(join(dir, 'owner.json'))).data as {
            pid?: unknown;
            token?: unknown;
        };
        if (!Number.isInteger(value.pid) || Number(value.pid) < 1 || typeof value.token !== 'string')
            throw new Error('Invalid lock owner; recover manually after inspection');
        let alive = true;
        try {
            process.kill(Number(value.pid), 0);
        }
        catch (e) {
            if ((e as NodeJS.ErrnoException).code === 'ESRCH')
                alive = false;
        }
        return { locked: true, pid: Number(value.pid), alive, token: value.token };
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code === 'ENOENT')
            return { locked: false, alive: false };
        throw e;
    }
}
export async function recoverLock(root: string, expectedToken: string) {
    const value = await lockInfo(root);
    if (!value.locked || value.alive || value.token !== expectedToken)
        throw new Error('Lock changed or owner is alive; no recovery performed');
    await fs.unlink(join(root, '.configuration-lock', 'owner.json'));
    await fs.rmdir(join(root, '.configuration-lock'));
}
export async function writeConfiguration(w: Workspace, config: Preferences, expected: string): Promise<string> {
    const parsed = preferencesSchema.parse(config);
    const release = await acquireLease(w.root);
    try {
        const current = await workspace(w.root, w.id);
        if (current.revision !== expected)
            throw new Error('Configuration changed; read the latest revision and review the diff again');
        // Saved configuration is a future-launch snapshot. Running processes are never reconfigured here.
        const bytes = JSON.stringify(parsed, null, 2) + '\n';
        const temp = w.path + '.' + randomUUID() + '.tmp';
        const handle = await fs.open(temp, 'wx', 0o600);
        try {
            await handle.writeFile(bytes);
            await handle.sync();
        }
        finally {
            await handle.close();
        }
        try {
            await fs.rename(temp, w.path);
        }
        catch (e) {
            await fs.unlink(temp).catch(() => undefined);
            throw e;
        }
        return createHash('sha256').update(bytes).digest('hex');
    }
    finally {
        await release();
    }
}
// Deliberately conservative: never show credential-like arguments in plans or persist them through import.
export function secretLike(value: string): boolean {
    return /(?:bearer\s+|sk-[A-Za-z0-9]|(?:api[-_]?key|token|secret|password|credential|authorization)[=:]|https?:\/\/[^/\s]+@|[?&](?:key|token|secret|signature|password)=)/i.test(value);
}
export function safeArguments(args: string[]): string[] {
    let next = false;
    return args.map(a => { const redact = next || secretLike(a); next = /^--?(api[-_]?key|token|secret|password|credential|authorization)$/i.test(a); return redact ? '[REDACTED]' : a; });
}
export function safeServer(s: ServerConfig) {
    return { ...s, name: secretLike(s.name) ? '[REDACTED]' : s.name, executable: secretLike(s.executable) ? '[REDACTED]' : s.executable,
        workingDirectory: secretLike(s.workingDirectory) ? '[REDACTED]' : s.workingDirectory, arguments: safeArguments(s.arguments) };
}
export function requireSafe(s: ServerConfig) {
    if (JSON.stringify(safeServer(s)) !== JSON.stringify(s))
        throw new Error('Credential-like arguments, names or paths rejected; use environment variable names instead');
}
export function importCandidates(data: unknown, current: Preferences): {
    candidates: ServerConfig[];
    skipped: string[];
} {
    if (!data || typeof data !== 'object' || Array.isArray(data))
        throw new Error('Import expects a JSON object');
    const raw = data as Record<string, unknown>;
    let entries: ServerConfig[] = [];
    const skipped: string[] = [];
    const native = preferencesSchema.safeParse(raw);
    if (native.success)
        entries = native.data.servers.map(s => ({ ...s, id: randomUUID().replaceAll('-', ''), allowedTools: [], tunnelID: '', profile: '' }));
    else {
        const map = raw.mcpServers ?? raw.servers;
        if (!map || typeof map !== 'object' || Array.isArray(map))
            throw new Error('Use native One MCP, mcpServers or VS Code servers JSON');
        for (const [name, v] of Object.entries(map)) {
            if (!v || typeof v !== 'object' || Array.isArray(v)) {
                skipped.push('Invalid entry');
                continue;
            }
            const x = v as Record<string, unknown>;
            if (typeof x.command !== 'string' || x.url || (x.type && x.type !== 'stdio')) {
                skipped.push('Unsupported remote or non-stdio entry');
                continue;
            }
            entries.push(serverSchema.parse({ id: randomUUID().replaceAll('-', ''), name, executable: x.command, arguments: x.args ?? [], workingDirectory: x.cwd ?? '',
                environmentKeys: Object.keys((x.env && typeof x.env === 'object' && !Array.isArray(x.env)) ? x.env : {}).sort(), allowedTools: [], tunnelID: '', profile: '' }));
        }
    }
    const fingerprint = (s: ServerConfig) => JSON.stringify([s.executable, s.arguments, s.workingDirectory, [...s.environmentKeys].sort()]);
    const seen = new Set(current.servers.map(fingerprint)), candidates: ServerConfig[] = [];
    for (const s of entries) {
        requireSafe(s);
        if (seen.has(fingerprint(s))) {
            skipped.push('Duplicate command/configuration');
            continue;
        }
        seen.add(fingerprint(s));
        candidates.push(s);
    }
    if (current.servers.length + candidates.length > 16)
        throw new Error('Import would exceed 16 servers; split the input');
    return { candidates, skipped };
}
export async function runtimeServer(s: ServerConfig): Promise<Record<string, unknown>> {
    requireSafe(s);
    if (!isAbsolute(s.executable))
        throw new Error('Server executable must be absolute; edit the imported command first');
    await fs.access(s.executable, 1);
    if (s.workingDirectory && (!isAbsolute(s.workingDirectory) || !(await fs.stat(s.workingDirectory)).isDirectory()))
        throw new Error('Invalid working directory');
    const environment: Record<string, string> = {};
    for (const key of s.environmentKeys) {
        const value = process.env[key];
        if (!value)
            throw new Error(`Required session environment variable is missing: ${key}`);
        environment[key] = value;
    }
    return { id: s.id, name: s.name, executable: s.executable, arguments: s.arguments, workingDirectory: s.workingDirectory, allowedTools: s.allowedTools, environment };
}


/** Read-only compatibility projection. An explicit empty list means no tunnels.
 * Bindings are a snapshot: adding a server never expands a migrated record. */
export function configuredTunnelRecords(config: Preferences): TunnelRecord[] {
    if (config.tunnelRecords !== undefined) return structuredClone(config.tunnelRecords);
    if (config.remoteConnection?.preferredTransport === 'cloudflare' && config.remoteConnection.cloudflare) {
        return [{id:'cloudflare-default', name:'Cloudflare', serverIDs:config.servers.map(s => s.id), transport:'cloudflare', profile:'', tunnelID:'', cloudflare:config.remoteConnection.cloudflare}];
    }
    if (config.mode === 'individual') return config.servers.map(s => ({id:s.id, name:s.name, serverIDs:[s.id], transport:'openai', profile:s.profile, tunnelID:s.tunnelID, startWithAll:s.startWithAll}));
    if (!config.servers.length && !config.aggregateTunnelID && config.aggregateProfileFile === undefined) return [];
    return [{id:'aggregate', name:'聚合隧道', serverIDs:config.servers.map(s => s.id), transport:'openai', profile:config.aggregateProfile, tunnelID:config.aggregateTunnelID, profileFile:config.aggregateProfileFile}];
}
