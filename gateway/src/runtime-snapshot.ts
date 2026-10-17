/** Keep GUI snapshots below both the IPC and native line limits without changing live tools. */
export const SNAPSHOT_BYTE_BUDGET = 3 * 1024 * 1024;
type ToolSummary = {name: string; publicName?: string};
type SnapshotServer = {tools?: ToolSummary[]; toolMetadataTruncated?: boolean; toolCatalogOmitted?: boolean};
const bytes = (value: unknown) => Buffer.byteLength(JSON.stringify(value), 'utf8');

/** This is a wire-only projection: never mutate the authoritative runtime catalog or allowlist. */
export function boundRuntimeSnapshot<T extends {servers: SnapshotServer[]}>(snapshot: T, maxBytes = SNAPSHOT_BYTE_BUDGET): T {
    if (!Number.isSafeInteger(maxBytes) || maxBytes < 1) throw new Error('Invalid snapshot byte budget');
    if (bytes(snapshot) <= maxBytes) return snapshot;
    const servers = snapshot.servers.map(server => ({...server,
        ...(server.tools ? {tools: server.tools.map(tool => ({name: tool.name,
            ...(tool.publicName !== undefined ? {publicName: tool.publicName} : {})})), toolMetadataTruncated: true} : {})}));
    const result = {...snapshot, servers};
    let used = bytes(result);
    // The minimum catalog can itself be enormous (many long or escaped Unicode names).
    // Explicit omission must not be confused with an authoritative empty catalog.
    if (used > maxBytes) {
        for (const server of servers) {
            if (server.tools !== undefined) {
                delete server.tools;
                server.toolMetadataTruncated = true;
                server.toolCatalogOmitted = true;
            }
        }
        if (bytes(result) > maxBytes) {
            // Do not silently alter identity, running state or permissions to fit the wire.
            throw new Error('Runtime snapshot state exceeds limit even without tool catalogs');
        }
        return result as T;
    }
    // Start with every tool identity, then spend the remaining budget on whole metadata records.
    // Count UTF-8 serialized bytes rather than characters, including JSON escaping.
    for (let s = 0; s < servers.length; s++) {
        const server = servers[s]!;
        const original = snapshot.servers[s]!.tools;
        if (!original || !server.tools) continue;
        let truncated = false;
        for (let t = 0; t < original.length; t++) {
            const delta = bytes(original[t]) - bytes(server.tools[t]);
            if (used + delta <= maxBytes) {
                server.tools[t] = original[t]!;
                used += delta;
            } else truncated = true;
        }
        if (!truncated) delete server.toolMetadataTruncated;
    }
    return result as T;
}
