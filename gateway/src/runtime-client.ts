/** Shared-runtime identity validation; injectable RPC allows protocol tests without socket support. */
export type RuntimeIdentity = {protocolVersion:number; instanceID:string; controlRoot:string; workspaceID:string; pid:number; port:number};
export function validateIdentity(raw: unknown, root: string, workspace: string, expected?: string): RuntimeIdentity {
  const s = raw as RuntimeIdentity;
  if (!s || s.protocolVersion !== 1 || typeof s.instanceID !== 'string' || !/^[a-f0-9-]{36}$/i.test(s.instanceID) ||
      s.controlRoot !== root || s.workspaceID !== workspace || !Number.isInteger(s.pid) || s.pid < 1 ||
      !Number.isInteger(s.port) || s.port < 1024 || s.port > 65535 || (expected && s.instanceID !== expected))
    throw new Error('Shared gateway identity/workspace changed or unsupported; reconnect explicitly');
  return s;
}
export class RuntimeClient {
  private identity?: RuntimeIdentity;
  constructor(private root:string, private workspace:string, private rpc:(method:string,params?:Record<string,unknown>)=>Promise<unknown>) {}
  async snapshot() {
    const s = await this.rpc('snapshot');
    this.identity = validateIdentity(s,this.root,this.workspace,this.identity?.instanceID);
    return s;
  }
  async command(method:string,params:Record<string,unknown>={}) {
    if (!this.identity) throw new Error('Gateway has not been attached');
    if (!['startServer','stopServer','listTools','tunnelAction','stopTunnel','stopAllTunnels','shutdown'].includes(method)) throw new Error('Unsupported shared command');
    return this.rpc(method,{...params,expectedInstanceID:this.identity.instanceID});
  }
}

/** Fixed diagnostics only: never forward paths, credentials, or arbitrary upstream error text. */
export function sharedDisconnectReason(error: unknown): string {
  const code = (error as {code?:unknown})?.code;
  if (code === 'ECONNREFUSED' || code === 'ENOENT') return 'socket-unavailable';
  const message = error instanceof Error ? error.message : '';
  if (/identity|Unsupported|Unknown management/.test(message)) return 'identity-mismatch';
  if (/exceeds limit|state exceeds limit/.test(message)) return 'snapshot-too-large';
  if (/timed out/i.test(message)) return 'timeout';
  if (/permissions or owner/.test(message)) return 'unsafe-socket';
  return 'connection-lost';
}
