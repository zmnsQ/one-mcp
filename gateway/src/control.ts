/** Private, owner-only IPC. Management is deliberately never exposed over the MCP HTTP port. */
import net from 'node:net';
import fs from 'node:fs/promises';
import { dirname, isAbsolute } from 'node:path';
export const CONTROL_LIMIT = 1024 * 1024;
export type ControlRequest = {
    id: string;
    method: string;
    params?: Record<string, unknown>;
};
export type ControlResponse = {
    type: 'response';
    id: string;
    ok: boolean;
    result?: unknown;
    error?: string;
};
export function parseRequest(value: unknown): ControlRequest {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        throw new Error('Invalid control request');
    const c = value as ControlRequest;
    if (typeof c.id !== 'string' || !/^[\w-]{1,128}$/.test(c.id) || typeof c.method !== 'string' || c.method.length > 64 ||
        (c.params !== undefined && (!c.params || typeof c.params !== 'object' || Array.isArray(c.params))))
        throw new Error('Invalid control request');
    return c;
}
export async function privateDirectory(path: string): Promise<void> {
    await fs.mkdir(path, { recursive: true, mode: 0o700 });
    const s = await fs.lstat(path);
    if (!s.isDirectory() || s.isSymbolicLink() || s.uid !== process.getuid?.() || (s.mode & 0o077))
        throw new Error('Runtime directory must be owned by this user and mode 0700');
}
export async function checkSocket(path: string): Promise<void> {
    const dir = await fs.lstat(dirname(path));
    const s = await fs.lstat(path);
    if (!dir.isDirectory() || dir.isSymbolicLink() || dir.uid !== process.getuid?.() || (dir.mode & 0o077) ||
        !s.isSocket() || s.uid !== process.getuid?.() || (s.mode & 0o077))
        throw new Error('Unsafe control socket permissions or owner');
}
export async function serveControl(path: string, dispatch: (c: ControlRequest) => Promise<ControlResponse>): Promise<() => Promise<void>> {
    if (!isAbsolute(path) || Buffer.byteLength(path) > 100)
        throw new Error('Control socket path must be absolute and at most 100 bytes');
    await privateDirectory(dirname(path));
    // Never unlink an existing path (it could be another live gateway or an untrusted file).
    try {
        await fs.lstat(path);
        throw new Error('Control socket already exists; inspect status before recovering it');
    }
    catch (e) {
        if ((e as NodeJS.ErrnoException).code !== 'ENOENT')
            throw e;
    }
    const connections = new Set<net.Socket>();
    const server = net.createServer(socket => {
        connections.add(socket);
        socket.once('close', () => connections.delete(socket));
        if (connections.size > 16) {
            socket.destroy();
            return;
        }
        socket.setTimeout(70000, () => socket.destroy());
        let data = Buffer.alloc(0), handled = false;
        socket.on('error', () => undefined);
        socket.on('data', chunk => {
            if (handled) {
                socket.destroy();
                return;
            }
            data = Buffer.concat([data, chunk]);
            if (data.length > CONTROL_LIMIT) {
                socket.destroy();
                return;
            }
            const newline = data.indexOf(10);
            if (newline < 0)
                return;
            handled = true;
            if (data.subarray(newline + 1).length) {
                socket.destroy();
                return;
            }
            void (async () => {
                try {
                    const request = parseRequest(JSON.parse(data.subarray(0, newline).toString('utf8')));
                    const response = await dispatch(request);
                    if (!socket.destroyed)
                        socket.end(JSON.stringify(response) + '\n');
                }
                catch {
                    if (!socket.destroyed)
                        socket.end(JSON.stringify({ type: 'response', id: '', ok: false, error: 'Invalid management request' }) + '\n');
                }
            })();
        });
    });
    await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(path, () => resolve()); });
    await fs.chmod(path, 0o600);
    return async () => {
        for (const s of connections)
            s.destroy();
        await new Promise<void>(resolve => server.close(() => resolve()));
        // net.Server.close removes its own Unix socket. Do not unlink a replacement path.
    };
}
export async function controlRequest(path: string, method: string, params?: Record<string, unknown>): Promise<unknown> {
    await checkSocket(path);
    const id = crypto.randomUUID();
    const payload = JSON.stringify({ id, method, params }) + '\n';
    if (Buffer.byteLength(payload) > CONTROL_LIMIT)
        throw new Error('Management request is too large');
    return new Promise((resolve, reject) => {
        const socket = net.createConnection(path);
        let data = Buffer.alloc(0), settled = false;
        const finish = (error?: Error, result?: unknown) => { if (settled)
            return; settled = true; socket.destroy(); error ? reject(error) : resolve(result); };
        socket.setTimeout(65000, () => finish(new Error('Management timed out; operation outcome is unknown. Inspect status before retrying.')));
        socket.on('connect', () => socket.write(payload));
        socket.on('error', e => finish(e));
        socket.on('end', () => { if (!settled)
            finish(new Error('Incomplete management response; inspect status before retrying')); });
        socket.on('data', chunk => {
            data = Buffer.concat([data, chunk]);
            if (data.length > CONTROL_LIMIT * 4) {
                finish(new Error('Management response exceeds limit'));
                return;
            }
            const newline = data.indexOf(10);
            if (newline < 0)
                return;
            try {
                const r = JSON.parse(data.subarray(0, newline).toString('utf8')) as ControlResponse;
                if (r.id !== id || r.type !== 'response' || typeof r.ok !== 'boolean')
                    throw new Error('Invalid management response');
                r.ok ? finish(undefined, r.result ?? null) : finish(new Error(r.error || 'Management operation failed'));
            }
            catch (e) {
                finish(e instanceof Error ? e : new Error('Invalid management response'));
            }
        });
    });
}
