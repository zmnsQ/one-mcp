/** Runtime-only, explicit service allowlists. Never infer all services from an empty list. */
export type TunnelBinding = { key: string; serverIDs: readonly string[]; provider: 'openai' | 'cloudflare' };
const identifier = /^[A-Za-z0-9_-]{1,64}$/;
export function validateTunnelBinding(key: unknown, ids: unknown, provider: TunnelBinding['provider']): TunnelBinding {
  if (typeof key !== 'string' || !identifier.test(key) || !Array.isArray(ids) || ids.length < 1 || ids.length > 16 ||
      ids.some(id => typeof id !== 'string' || !identifier.test(id)) || new Set(ids).size !== ids.length) {
    throw new Error('Select one or more unique MCP services for this tunnel record.');
  }
  return Object.freeze({key, serverIDs: Object.freeze([...ids].sort()), provider});
}
export function scopedTunnelEndpoint(port: number, key: string): string {
  if (!identifier.test(key)) throw new Error('Invalid tunnel record ID');
  return `http://127.0.0.1:${port}/tunnels/${key}/mcp`;
}
