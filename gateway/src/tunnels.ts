import { validateTunnelBinding, scopedTunnelEndpoint } from './tunnel-bindings.js';
import { readTunnelHealth } from './tunnel-health.js';
import { spawn, ChildProcess } from 'node:child_process';
import fs from 'node:fs/promises';
import { join, isAbsolute } from 'node:path';
import { TunnelActionError, classifyTunnelDiagnostic, tunnelErrors, TunnelErrorCode } from './tunnel-errors.js';
import { constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { configurationFingerprintVersion, ConfigurationFingerprints, tunnelConfigurationFingerprints } from './configuration-fingerprints.js';
type Target = {
    key: string;
    action: 'init' | 'doctor' | 'run';
    executable: string;
    profile: string;
    tunnelID: string;
    runtimeKey: string;
    profileFile?: string;
    serverIDs?: string[];
};
type Running = {
    target: Omit<Target, 'runtimeKey'>;
    child: ChildProcess;
    closed: Promise<void>;
    ready: boolean;
    timer?: NodeJS.Timeout;
    folder?: string;
    checking: boolean;
    configurationFingerprints: ConfigurationFingerprints;
};
export function profileLocationEnvironment(source:NodeJS.ProcessEnv):Record<string,string> {
    const result:Record<string,string>={};
    for(const name of ['TUNNEL_CLIENT_PROFILE_DIR','XDG_CONFIG_HOME']) {
        const value=source[name];
        if(value && isAbsolute(value) && !value.includes('\0'))result[name]=value;
    }
    return result;
}
export function profileSelection(profile:string,file:string|undefined,source:NodeJS.ProcessEnv) {
 if(file)return {profileMode:'file',profileLocation:file,profileLocationSource:'explicit-file'};
 const locations=profileLocationEnvironment(source);
 const directory=locations.TUNNEL_CLIENT_PROFILE_DIR ?? (locations.XDG_CONFIG_HOME?join(locations.XDG_CONFIG_HOME,'tunnel-client'):source.HOME&&isAbsolute(source.HOME)?join(source.HOME,'.config','tunnel-client'):undefined);
 return {profileMode:'named',profileLocation:directory?join(directory,profile+'.yaml'):undefined,profileLocationSource:locations.TUNNEL_CLIENT_PROFILE_DIR?'TUNNEL_CLIENT_PROFILE_DIR':locations.XDG_CONFIG_HOME?'XDG_CONFIG_HOME':'HOME default'};
}
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
        const input = raw as Target;
        const t = input && typeof input === 'object' ? {...input, profileFile: typeof input.profileFile === 'string' && !input.profileFile.trim() ? undefined : input.profileFile} : input;
        if (!t || typeof t.key !== 'string' || !/^[\w-]{1,64}$/.test(t.key) || !['init','doctor','run'].includes(t.action)) throw new TunnelActionError('TUNNEL_TARGET');
        if (typeof t.profile !== 'string' || t.profile.length > 256 || (!t.profileFile && !/^[\w-]{1,64}$/.test(t.profile))) throw new TunnelActionError('TUNNEL_PROFILE');
        if (typeof t.tunnelID !== 'string' || !/^tunnel_[\w-]+$/.test(t.tunnelID)) throw new TunnelActionError('TUNNEL_ID');
        if (typeof t.executable !== 'string' || !isAbsolute(t.executable) || t.executable.includes('\0')) throw new TunnelActionError('TUNNEL_EXECUTABLE');
        try { await fs.access(t.executable, constants.X_OK); } catch { throw new TunnelActionError('TUNNEL_EXECUTABLE'); }
        if (t.runtimeKey !== undefined && (typeof t.runtimeKey !== 'string' || t.runtimeKey.length > 65536 || t.runtimeKey.includes('\0'))) throw new TunnelActionError('TUNNEL_KEY_FORMAT');
        if (t.profileFile !== undefined && (typeof t.profileFile !== 'string' || !isAbsolute(t.profileFile) || t.profileFile.includes('\0'))) throw new TunnelActionError('TUNNEL_PROFILE_FILE');
        this.emit({type:'tunnelProfile',key:t.key,...profileSelection(t.profile,t.profileFile,process.env)});
        if (t.profileFile && t.action === 'init') throw new TunnelActionError('TUNNEL_EXISTING_INIT');
        if (t.profileFile) { try { if (!(await fs.stat(t.profileFile)).isFile()) throw new Error(); await fs.access(t.profileFile, constants.R_OK); } catch { throw new TunnelActionError('TUNNEL_PROFILE_FILE'); } }
        const binding = t.serverIDs === undefined ? undefined : validateTunnelBinding(t.key, t.serverIDs, 'openai');
        if (binding && t.action !== 'init' && binding.serverIDs.some(id => !this.serverReady(id))) throw new TunnelActionError('TUNNEL_BACKEND');
        if (!binding && t.key !== 'aggregate' && t.action !== 'init' && !this.serverReady(t.key)) throw new TunnelActionError('TUNNEL_BACKEND');
        if (this.running.has(t.key)) throw new TunnelActionError('TUNNEL_BUSY');
        const profileIdentity = t.profileFile ? await fs.realpath(t.profileFile) : undefined;
        if ([...this.running.values()].some(r => r.target.tunnelID === t.tunnelID || (profileIdentity ? r.target.profileFile === profileIdentity : !r.target.profileFile && r.target.profile === t.profile))) throw new TunnelActionError('TUNNEL_DUPLICATE');
        const endpoint = binding ? scopedTunnelEndpoint(this.port, t.key) : `http://127.0.0.1:${this.port}${t.key === 'aggregate' ? '/mcp' : `/servers/${t.key}/mcp`}`;
        const signature = [t.executable, t.profile, t.tunnelID, endpoint, t.profileFile ?? '', ...(binding ? [binding.serverIDs.join(',')] : [])].join('\n');
        const configurationFingerprints = tunnelConfigurationFingerprints(t, endpoint);
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
            env: { PATH: process.env.PATH, HOME: process.env.HOME, ...profileLocationEnvironment(process.env), ...(t.runtimeKey ? {CONTROL_PLANE_API_KEY: t.runtimeKey} : {}), CONTROL_PLANE_TUNNEL_ID: t.tunnelID, MCP_SERVER_URL: endpoint } });
        let resolveClosed!: () => void;
        const r: Running = { target: { key: t.key, action: t.action, executable: t.executable, profile: t.profile, tunnelID: t.tunnelID, profileFile: profileIdentity, ...(binding ? {serverIDs: [...binding.serverIDs]} : {}) }, child,
            configurationFingerprints, ready: false, checking: false, folder, closed: new Promise(resolve => { resolveClosed = resolve; }) };
        this.running.set(t.key, r);
        // No raw tunnel stdout/stderr enters logs, as credentials may appear in diagnostics.
        let diagnostic: TunnelErrorCode | undefined;
        let diagnosticTail = '';
        const inspect = (chunk: Buffer) => { diagnosticTail = (diagnosticTail + chunk.toString('utf8')).slice(-4096); diagnostic = classifyTunnelDiagnostic(diagnosticTail) ?? diagnostic; };
        child.stdout?.on('data', inspect); child.stderr?.on('data', inspect);
        child.once('close', code => {
            clearInterval(r.timer);
            if (this.running.get(t.key) === r)
                this.running.delete(t.key);
            const failure = code === 0 ? undefined : (diagnostic ?? 'TUNNEL_FAILED');
            diagnosticTail = '';
            this.event(t.key, { ...(failure ? {errorOrigin:'official-client', errorCode: failure, message: tunnelErrors[failure]} : {}), running: false, ready: false, action: t.action, exitCode: code, signature, configurationFingerprintVersion, configurationFingerprints,
                state: t.action === 'run' ? `Stopped (${code ?? 'signal'})` : `${t.action} ${code === 0 ? 'passed' : 'failed'}` });
            if (folder)
                void fs.rm(folder, { recursive: true, force: true });
            resolveClosed();
        });
        try {
            await new Promise<void>((resolve, reject) => { child.once('spawn', resolve); child.once('error', () => reject(new TunnelActionError('TUNNEL_EXECUTABLE'))); });
        }
        catch (e) {
            await r.closed;
            throw e;
        }
        this.event(t.key, { running: true, ready: false, action: t.action, signature, configurationFingerprintVersion, configurationFingerprints, state: 'Process started; readiness unverified' });
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
            const health = await readTunnelHealth(url).catch(() => ({available:false,reason:'unavailable'}));
            if (this.running.get(r.target.key) !== r) return;
            this.event(r.target.key, { running: true, ready: r.ready, action: r.target.action, signature, configurationFingerprintVersion, configurationFingerprints: r.configurationFingerprints, healthURL: new URL('/', url).href, health,
                state: r.ready ? 'readyz HTTP 200; ChatGPT call remains unverified' : `Health HTTP ${response.status}` });
        }
        catch {
            if (this.running.get(r.target.key) === r)
                this.event(r.target.key, { running: true, ready: false, action: r.target.action, signature, configurationFingerprintVersion, configurationFingerprints: r.configurationFingerprints, state: 'Waiting for valid loopback readiness' });
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
    async stopForServer(id: string) {
        await Promise.all([...this.running].filter(([key, r]) => r.target.serverIDs ? r.target.serverIDs.includes(id) : key === 'aggregate' || key === id).map(([key]) => this.stop(key)));
    }
    async stopAll() { await Promise.all([...this.running.keys()].map(key => this.stop(key))); }
}
