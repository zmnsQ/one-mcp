import { spawn, ChildProcess } from 'node:child_process';
import fs from 'node:fs/promises';
import { join, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';
type Target = {
    key: string;
    action: 'init' | 'doctor' | 'run';
    executable: string;
    profile: string;
    tunnelID: string;
    runtimeKey: string;
    profileFile?: string;
};
type Running = {
    target: Omit<Target, 'runtimeKey'>;
    child: ChildProcess;
    closed: Promise<void>;
    ready: boolean;
    timer?: NodeJS.Timeout;
    folder?: string;
    checking: boolean;
};
export class TunnelManager {
    private running = new Map<string, Running>();
    private results = new Map<string, object>();
    constructor(private port: number, private emit: (event: object) => void, private serverReady: (id: string) => boolean) { }
    snapshot(): object[] { return [...this.results.values()]; }
    private event(key: string, data: Record<string, unknown>) {
        const event = { type: 'tunnelStatus', key, ...data };
        this.results.set(key, event);
        this.emit(event);
    }
    async action(raw: unknown): Promise<unknown> {
        const t = raw as Target;
        if (!t || typeof t.key !== 'string' || typeof t.profile !== 'string' || t.profile.length > 256 || typeof t.tunnelID !== 'string' || !['init', 'doctor', 'run'].includes(t.action) || !/^[\w-]{1,64}$/.test(t.key) ||
            (!t.profileFile && !/^[\w-]{1,64}$/.test(t.profile)) || !/^tunnel_[\w-]+$/.test(t.tunnelID) ||
            typeof t.executable !== 'string' || !isAbsolute(t.executable) || t.executable.includes('\0') ||
            typeof t.runtimeKey !== 'string' || !t.runtimeKey || t.runtimeKey.length > 65536 || t.runtimeKey.includes('\0'))
            throw new Error('Invalid tunnel settings; use a configured absolute executable and session key');
        if (t.profileFile !== undefined && typeof t.profileFile !== 'string')
            throw new Error('Invalid profile file');
        if (t.profileFile && (typeof t.profileFile !== 'string' || !isAbsolute(t.profileFile) || t.profileFile.includes('\0')))
            throw new Error('Invalid profile file');
        if (t.profileFile && t.action === 'init')
            throw new Error('Selected existing profile must not be initialized or overwritten');
        if (t.key !== 'aggregate' && t.action !== 'init' && !this.serverReady(t.key))
            throw new Error('Start this MCP server before connecting its tunnel');
        if (this.running.has(t.key))
            throw new Error('Tunnel operation already running');
        if ([...this.running.values()].some(r => r.target.profile === t.profile || r.target.tunnelID === t.tunnelID))
            throw new Error('Profile or tunnel ID is already in use');
        const endpoint = `http://127.0.0.1:${this.port}${t.key === 'aggregate' ? '/mcp' : `/servers/${t.key}/mcp`}`;
        const signature = [t.executable, t.profile, t.tunnelID, endpoint, t.profileFile ?? ''].join('\n');
        const args = t.profileFile ? [t.action, '--profile-file', t.profileFile] : [t.action, '--profile', t.profile];
        let folder: string | undefined;
        if (t.action === 'init')
            args.push('--sample', 'sample_mcp_remote_no_auth', '--tunnel-id', t.tunnelID, '--mcp-server-url', endpoint);
        if (t.action === 'doctor')
            args.push('--explain');
        if (t.action === 'run') {
            folder = await fs.mkdtemp(join(tmpdir(), 'onemcp-health-'));
            await fs.chmod(folder, 0o700);
            args.push('--health.listen-addr', '127.0.0.1:0', '--health.url-file', join(folder, 'url'));
        }
        const child = spawn(t.executable, args, { stdio: ['ignore', 'pipe', 'pipe'], shell: false,
            env: { PATH: process.env.PATH, HOME: process.env.HOME, CONTROL_PLANE_API_KEY: t.runtimeKey, CONTROL_PLANE_TUNNEL_ID: t.tunnelID, MCP_SERVER_URL: endpoint } });
        let resolveClosed!: () => void;
        const r: Running = { target: { key: t.key, action: t.action, executable: t.executable, profile: t.profile, tunnelID: t.tunnelID }, child,
            ready: false, checking: false, folder, closed: new Promise(resolve => { resolveClosed = resolve; }) };
        this.running.set(t.key, r);
        // No raw tunnel stdout/stderr enters logs, as credentials may appear in diagnostics.
        child.stdout?.resume();
        child.stderr?.resume();
        child.once('close', code => {
            clearInterval(r.timer);
            if (this.running.get(t.key) === r)
                this.running.delete(t.key);
            this.event(t.key, { running: false, ready: false, action: t.action, exitCode: code, signature,
                state: t.action === 'run' ? `Stopped (${code ?? 'signal'})` : `${t.action} ${code === 0 ? 'passed' : 'failed'}` });
            if (folder)
                void fs.rm(folder, { recursive: true, force: true });
            resolveClosed();
        });
        try {
            await new Promise<void>((resolve, reject) => { child.once('spawn', resolve); child.once('error', () => reject(new Error('Tunnel executable could not be launched'))); });
        }
        catch (e) {
            await r.closed;
            throw e;
        }
        this.event(t.key, { running: true, ready: false, action: t.action, signature, state: 'Process started; readiness unverified' });
        if (folder)
            r.timer = setInterval(() => { void this.check(r, signature); }, 1000);
        return { key: t.key, action: t.action, submitted: true, ready: false };
    }
    private async check(r: Running, signature: string) {
        if (r.checking || !r.folder)
            return;
        r.checking = true;
        try {
            const file = join(r.folder, 'url');
            if ((await fs.stat(file)).size > 256)
                throw new Error('Invalid health URL');
            const raw = (await fs.readFile(file, 'utf8')).trim();
            const url = new URL(raw);
            if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port || url.username || url.password ||
                url.search || url.hash || (url.pathname !== '/' && url.pathname !== ''))
                throw new Error('Invalid health URL');
            url.pathname = '/readyz';
            const response = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(2500) });
            await response.body?.cancel();
            if (this.running.get(r.target.key) !== r)
                return;
            r.ready = response.status === 200;
            this.event(r.target.key, { running: true, ready: r.ready, action: r.target.action, signature,
                state: r.ready ? 'readyz HTTP 200; ChatGPT call remains unverified' : `Health HTTP ${response.status}` });
        }
        catch {
            if (this.running.get(r.target.key) === r)
                this.event(r.target.key, { running: true, ready: false, action: r.target.action, signature, state: 'Waiting for valid loopback readiness' });
        }
        finally {
            r.checking = false;
        }
    }
    async stop(key: string) {
        const r = this.running.get(key);
        if (!r)
            return;
        clearInterval(r.timer);
        r.child.kill('SIGTERM');
        const force = setTimeout(() => r.child.kill('SIGKILL'), 4000);
        try {
            await r.closed;
        }
        finally {
            clearTimeout(force);
        }
    }
    async stopAll() { await Promise.all([...this.running.keys()].map(key => this.stop(key))); }
}
