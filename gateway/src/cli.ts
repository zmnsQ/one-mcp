#!/usr/bin/env node
import fs from 'node:fs/promises';
import { discoverEnvironment } from './discovery.js';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { controlRequest, privateDirectory } from './control.js';
import { defaultRoot, workspace, socketPath, safeServer, readJSON, importCandidates, writeConfiguration, runtimeServer, lockInfo, recoverLock, preferencesSchema, secretLike, acquireLease } from './configuration.js';
const argv = process.argv.slice(2), positional: string[] = [], opts: Record<string, string | boolean> = {};
const boolean = new Set(['json', 'apply', 'help']);
const valued = new Set(['home', 'workspace', 'expect-revision', 'file', 'id', 'names', 'field', 'value', 'token']);
let action = 'help';
function output(result: unknown) { process.stdout.write(JSON.stringify({ schemaVersion: 1, ok: true, action, result }, null, opts.json ? 0 : 2) + '\n'); }
function failure(message: string, code = 1) { process.stdout.write(JSON.stringify({ schemaVersion: 1, ok: false, action, error: { code, message } }) + '\n'); process.exitCode = code; }
try {
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i]!;
        if (!a.startsWith('--')) {
            positional.push(a);
            continue;
        }
        const key = a.slice(2);
        if (boolean.has(key)) {
            opts[key] = true;
            continue;
        }
        if (!valued.has(key) || argv[i + 1] === undefined || argv[i + 1]!.startsWith('--'))
            throw new Error('Unknown option or missing value');
        opts[key] = argv[++i]!;
    }
    const [group = 'help', verb = 'status'] = positional;
    action = group + ' ' + verb;
    const root = resolve(String(opts.home ?? defaultRoot()));
    if (group === 'help' || opts.help) {
        output({ usage: 'onemcp <command> [--json] [--home PATH] [--workspace ID]', commands: ['status', 'environment inspect', 'workspaces', 'servers list|start|stop --id ID', 'tools discover --id ID', 'config validate|init|lock', 'config import --file PATH', 'config allow-tools --id ID --names tool1,tool2', 'config set --field nodePath|gatewayScript|tunnelClientPath|port|aggregateTunnelID|aggregateProfile|mode --value VALUE', 'config recover-lock --token TOKEN', 'gateway run|stop', 'tunnel init|doctor|start|stop --id aggregate|SERVER_ID'], mutation: 'Commands preview unless --apply. Saved configuration changes also require --expect-revision SHA (or missing). Runtime actions use the existing private gateway. Credentials are read from explicit session environment only; no Keychain reads.' });
    }
    else if (group === 'environment' && verb === 'inspect')
        output(await discoverEnvironment());
    else {
        const w = await workspace(root, typeof opts.workspace === 'string' ? opts.workspace : undefined);
        const rpc = async (method: string, params: Record<string, unknown> = {}) => controlRequest(socketPath(root), method, params);
        const live = async () => { const s = await rpc('status') as {
            workspaceID: string;
        }; if (s.workspaceID !== w.id)
            throw new Error('Running gateway belongs to another workspace'); return s; };
        const mutation = async (plan: unknown, run: () => Promise<unknown>) => { if (!opts.apply)
            output({ preview: true, plan });
        else
            output(await run()); };
        const save = async (config: typeof w.config) => { if (typeof opts['expect-revision'] !== 'string')
            throw new Error('Read config validate and provide --expect-revision before applying'); return { revision: await writeConfiguration(w, config, opts['expect-revision']) }; };
        const server = () => { const s = w.config.servers.find(s => s.id === opts.id); if (!s)
            throw new Error('Unknown --id; use servers list'); return s; };
        if (group === 'status') {
            let runtime: unknown;
            try {
                runtime = await live();
            }
            catch {
                runtime = { connected: false, message: 'No verified gateway connection; inspect running application or start gateway run.' };
            }
            output({ workspace: w.id, revision: w.revision, runtime });
        }
        else if (group === 'workspaces')
            output(w.index);
        else if (group === 'servers' && verb === 'list')
            output({ workspace: w.id, revision: w.revision, servers: w.config.servers.map(safeServer) });
        else if (group === 'config' && verb === 'validate')
            output({ valid: true, workspace: w.id, revision: w.revision, serverCount: w.config.servers.length });
        else if (group === 'config' && verb === 'lock')
            output(await lockInfo(root));
        else if (group === 'config' && verb === 'recover-lock')
            await mutation({ recoverDeadOwner: true }, async () => { if (typeof opts.token !== 'string')
                throw new Error('--token required from config lock'); await recoverLock(root, opts.token); return { recovered: true }; });
        else if (group === 'config' && verb === 'init')
            await mutation({ create: w.path, revision: w.revision }, async () => { if (w.revision !== 'missing')
                throw new Error('Configuration already exists'); w.config.gatewayScript = join(dirname(fileURLToPath(import.meta.url)), 'index.js'); return save(w.config); });
        else if (group === 'config' && verb === 'import') {
            if (typeof opts.file !== 'string')
                throw new Error('--file required');
            const imported = importCandidates((await readJSON(resolve(opts.file))).data, w.config);
            await mutation({ revision: w.revision, ...imported }, () => save({ ...w.config, servers: [...w.config.servers, ...imported.candidates] }));
        }
        else if (group === 'config' && verb === 'allow-tools') {
            const s = server();
            if (typeof opts.names !== 'string')
                throw new Error('--names required; use none to deny all');
            const names = opts.names === 'none' ? [] : opts.names.split(',');
            const config = preferencesSchema.parse({ ...w.config, servers: w.config.servers.map(x => x.id === s.id ? { ...x, allowedTools: names } : x) });
            await mutation({ id: s.id, before: s.allowedTools, after: names, revision: w.revision }, () => save(config));
        }
        else if (group === 'config' && verb === 'set') {
            const fields = ['nodePath', 'gatewayScript', 'tunnelClientPath', 'port', 'aggregateTunnelID', 'aggregateProfile', 'aggregateProfileFile', 'mode'];
            const field = String(opts.field);
            if (!fields.includes(field) || typeof opts.value !== 'string')
                throw new Error('Unsupported field or missing --value');
            if (secretLike(opts.value))
                throw new Error('Credential-like configuration value rejected');
            const config = preferencesSchema.parse({ ...w.config, [field]: field === 'port' ? Number(opts.value) : opts.value });
            await mutation({ field, revision: w.revision }, () => save(config));
        }
        else if (group === 'gateway' && verb === 'run')
            await mutation({ workspace: w.id, port: w.config.port, foreground: true }, async () => { const release = await acquireLease(root); try {
                const current = await workspace(root, w.id);
                await privateDirectory(join(root, 'Runtime'));
                const child = spawn(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), 'index.js'), '--port', String(current.config.port), '--workspace-id', current.id, '--control-socket', socketPath(root)], { stdio: ['pipe', 'ignore', 'inherit'] });
                const stop = () => child.stdin.write(JSON.stringify({ id: 'cli-shutdown', method: 'shutdown', params: {} }) + '\n');
                process.once('SIGINT', stop);
                process.once('SIGTERM', stop);
                await new Promise<void>((yes, no) => { child.once('error', no); child.once('exit', code => code === 0 ? yes() : no(new Error('Gateway exited unsuccessfully'))); });
                return { stopped: true };
            }
            finally {
                await release();
            } });
        else if (group === 'gateway' && verb === 'stop')
            await mutation({ stopGateway: true }, async () => { await live(); return rpc('shutdown'); });
        else if (group === 'servers' && ['start', 'stop'].includes(verb)) {
            const s = server();
            await mutation({ operation: verb, id: s.id }, async () => { await live(); return verb === 'start' ? rpc('startServer', { server: await runtimeServer(s) }) : rpc('stopServer', { serverId: s.id }); });
        }
        else if (group === 'tools' && verb === 'discover') {
            const s = server();
            await live();
            output(await rpc('listTools', { serverId: s.id }));
        }
        else if (group === 'tunnel' && ['init', 'doctor', 'start', 'stop'].includes(verb)) {
            const key = String(opts.id ?? 'aggregate');
            const s = key === 'aggregate' ? undefined : server();
            await mutation({ operation: verb, key, profile: s?.profile ?? w.config.aggregateProfile }, async () => { await live(); if (verb === 'stop')
                return rpc('stopTunnel', { key }); const runtimeKey = process.env.CONTROL_PLANE_API_KEY; if (!runtimeKey)
                throw new Error('CONTROL_PLANE_API_KEY is required in this session environment'); return rpc('tunnelAction', { key, action: verb === 'start' ? 'run' : verb, executable: w.config.tunnelClientPath, profile: s?.profile ?? w.config.aggregateProfile, tunnelID: s?.tunnelID ?? w.config.aggregateTunnelID, runtimeKey, profileFile: key === 'aggregate' ? w.config.aggregateProfileFile : undefined }); });
        }
        else
            throw new Error('Unknown command; use onemcp help');
    }
}
catch (e) {
    const message = e instanceof Error ? e.message : 'Operation failed';
    const safe = message.includes('Zod') || message.startsWith('[') ? 'Invalid configuration or arguments' : message;
    failure(safe, /Unknown|missing|required|Invalid|Unsupported/i.test(safe) ? 2 : /lock|changed|workspace|already|Stop the gateway/i.test(safe) ? 3 : 1);
}
