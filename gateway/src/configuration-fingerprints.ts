import type {CLIServiceConfiguration} from './cli-descriptor.js';
import { createHash } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { resolve } from 'node:path';

/** Wire contract shared with the native saved-versus-running comparison. */
export const configurationFingerprintVersion = 1;
export type ConfigurationFingerprints = Record<string, string>;

/**
 * SHA-256 of concatenated UTF-8 byte-length-prefixed strings. No JSON escaping,
 * locale sorting, Unicode normalization, or inter-item delimiters are involved.
 * Callers pass only persisted fields, never session credential values.
 * A scalar is a singleton list; the empty list differs from the empty string.
 */
export function configurationFingerprint(values: readonly string[]): string {
    const hash = createHash('sha256');
    for (const value of values) {
        const bytes = Buffer.from(value, 'utf8');
        hash.update(String(bytes.length) + ':');
        hash.update(bytes);
    }
    return hash.digest('hex');
}

function field(value: string): string { return configurationFingerprint([value]); }
function set(values: readonly string[]): string {
    return configurationFingerprint([...new Set(values)].sort((a, b) => Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'))));
}

type ServerConfiguration = {
    kind?: string; cli?: CLIServiceConfiguration;
    name: string;
    executable: string;
    arguments: readonly string[];
    workingDirectory?: string;
    environment: Record<string, string>;
    allowedTools: readonly string[];
};

export function serverConfigurationFingerprints(config: ServerConfiguration): ConfigurationFingerprints {
    return {
        // The running name is also embedded in published tool descriptions.
        name: field(config.name),
        executable: field(config.executable),
        arguments: configurationFingerprint(config.arguments),
        workingDirectory: field(config.workingDirectory ?? ''),
        // Capture only explicitly supplied keys, before the MCP transport inherits
        // its default environment. Neither secret values nor their hashes leave here.
        environmentKeys: set(Object.keys(config.environment)),
        allowedTools: set(config.allowedTools),
        ...(config.kind === 'cli' ? {kind: field('cli'), cli: configurationFingerprint(cliFingerprintValues(config.cli!))} : {})
    };
}

type TunnelConfiguration = { executable: string; profile: string; tunnelID: string; profileFile?: string; serverIDs?: readonly string[] };
export function tunnelConfigurationFingerprints(config: TunnelConfiguration, endpoint: string): ConfigurationFingerprints {
    const profileFile = config.profileFile?.trim() ? config.profileFile : '';
    return {
        executable: field(config.executable),
        // --profile is not passed when --profile-file is selected.
        profile: field(profileFile ? '' : config.profile),
        tunnelID: field(config.tunnelID),
        profileFile: field(profileFile),
        endpoint: field(endpoint),
        ...(config.serverIDs !== undefined ? {serverIDs: set(config.serverIDs)} : {})
    };
}

export function canonicalRuntimePath(path: string): string {
    try { return realpathSync(path); }
    catch { return resolve(path); }
}

export function gatewayConfigurationFingerprints(nodePath: string, gatewayScript: string, port: number): ConfigurationFingerprints {
    return {
        nodePath: field(canonicalRuntimePath(nodePath)),
        gatewayScript: field(canonicalRuntimePath(gatewayScript)),
        port: field(String(port))
    };
}

export function cliFingerprintValues(cli:CLIServiceConfiguration):string[] {
 const values=[String(cli.timeoutMs),String(cli.maxOutputBytes),String(cli.maxConcurrent),String(cli.tools.length)];
 for(const tool of cli.tools){values.push(tool.name,tool.description,String(tool.arguments.length));for(const a of tool.arguments)values.push(a.name,a.type,a.flag??'',String(a.required),String(a.enumValues?.length??0),...(a.enumValues??[]));}
 return values;
}
