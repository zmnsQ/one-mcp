/** Read-only discovery. Official schema/precedence reference:
 * https://github.com/openai/tunnel-client/blob/master/docs/configuration.md
 * This is metadata inspection, NOT tunnel-client validation, authentication or readiness.
 */
import fs from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve, isAbsolute, relative, delimiter, basename } from 'node:path';

export type DiscoveryOptions = { home?: string; env?: NodeJS.ProcessEnv; platform?: string };
export type BinaryCandidate = { name: 'node' | 'tunnel-client'; path: string; source: string; confidence: 'candidate'; available: boolean };
export type ProfileMetadata = {
  path: string; name: string; source: string; selected: boolean;
  status: 'inspected' | 'missing' | 'skipped'; reason?: string;
  tunnelID?: string; mcpTransport?: 'http' | 'stdio'; mcpOrigin?: string;
  hasCredentialConfiguration?: boolean; parser?: 'conservative-scalar-yaml';
};
export type EnvironmentDiscovery = {
  schemaVersion: 1; readOnly: true; platform: string;
  clients: { id: string; path: string; source: string; version?: string }[];
  profiles: { id: string; path: string; name: string; tunnelID?: string; endpoint?: string; source: string }[];
  warnings: string[];
  binaries: BinaryCandidate[];
  tunnel: { profileDirectory: string; directorySource: string; selectedProfile: string | null; selectionSource: string | null; profiles: ProfileMetadata[]; configFiles: ProfileMetadata[]; warnings: string[] };
  limits: { maxProfiles: number; maxFileBytes: number; maxTotalBytes: number; maxPathDirectories: number };
};
const limits = { maxProfiles: 64, maxFileBytes: 131072, maxTotalBytes: 1048576, maxPathDirectories: 32 };
const safePath = (s: string | undefined): s is string => !!s && s.length <= 4096 && !/[\x00-\x1f\x7f]|sk-[A-Za-z0-9]|(?:token|password|secret|api_key)=/i.test(s);
const safeName = (s: string) => /^[A-Za-z0-9_.-]{1,128}$/.test(s) && !s.startsWith('.') && !/sk-/i.test(s);
const inside = (root: string, path: string) => { const r = relative(root, path); return r === '' || (!r.startsWith('..') && !isAbsolute(r)); };

// Deliberately not a general YAML parser. Only simple, single-line scalar keys
// in known sections are interpreted; aliases, tags, flow maps and block strings
// cannot inject metadata. Credentials and command arguments are never emitted.
function metadata(text: string): Pick<ProfileMetadata, 'tunnelID' | 'mcpTransport' | 'mcpOrigin' | 'hasCredentialConfiguration' | 'parser'> {
  const out: ReturnType<typeof metadata> = { parser: 'conservative-scalar-yaml', hasCredentialConfiguration: false };
  let section = '';
  for (const line of text.split(/\r?\n/)) {
    if (line.length > 8192) continue;
    const top = /^([a-z_]+):\s*(?:#.*)?$/.exec(line);
    if (top) { section = top[1]!; continue; }
    if (/^\S/.test(line) && !/^#/.test(line)) { section = ''; continue; }
    const m = /^  ([a-z_]+):\s*(.*?)\s*$/.exec(line);
    if (!m || !['control_plane', 'mcp'].includes(section)) continue;
    const key = m[1]!;
    if (/^(api_key|client_key|client_cert|authorization|headers)$/.test(key)) { out.hasCredentialConfiguration = true; continue; }
    let value = m[2]!.replace(/\s+#.*$/, '').trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    if (section === 'control_plane' && key === 'tunnel_id' && /^tunnel_[A-Za-z0-9_-]{1,128}$/.test(value)) out.tunnelID = value;
    if (section === 'mcp' && key === 'command' && value && !/^[&*!>|{[]/.test(value)) out.mcpTransport = 'stdio';
    if (section === 'mcp' && key === 'server_url') {
      try {
        const url = new URL(value);
        if (['http:', 'https:'].includes(url.protocol)) {
          out.mcpTransport = 'http';
          // Origin only; userinfo/path/query/fragments may contain credentials.
          if (!url.username && !url.password && !/sk-|token|secret|password/i.test(url.hostname)) out.mcpOrigin = url.origin;
        }
      } catch { /* env/file indirection intentionally not resolved */ }
    }
  }
  return out;
}

export async function discoverEnvironment(options: DiscoveryOptions = {}): Promise<EnvironmentDiscovery> {
  const env = options.env ?? process.env;
  const home = options.home ?? homedir();
  const warnings: string[] = [];
  const candidates: BinaryCandidate[] = [];
  const add = (name: BinaryCandidate['name'], path: string | undefined, source: string) => {
    if (!safePath(path) || !isAbsolute(path) || candidates.some(c => c.name === name && c.path === path)) return;
    candidates.push({ name, path, source, confidence: 'candidate', available: false });
  };
  add('tunnel-client', env.TUNNEL_CLIENT_BIN, 'TUNNEL_CLIENT_BIN');
  // The running Node is known to exist, but no other discovered binary is run.
  if (!options.env) add('node', process.execPath, 'current-process');
  const dirs = (env.PATH ?? '').split(delimiter).filter(p => safePath(p) && isAbsolute(p));
  if (dirs.length > limits.maxPathDirectories) warnings.push('PATH inspection truncated to 32 absolute directories.');
  for (const dir of dirs.slice(0, limits.maxPathDirectories)) for (const name of ['node', 'tunnel-client'] as const) add(name, join(dir, name), 'PATH');
  for (const dir of ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', join(home, '.local/bin')]) {
    for (const name of ['node', 'tunnel-client'] as const) add(name, join(dir, name), 'conventional-path');
  }
  for (const c of candidates) {
    try { const stat = await fs.stat(c.path); if (stat.isFile()) { await fs.access(c.path, constants.X_OK); c.available = true; } } catch { /* missing/inaccessible candidate */ }
  }
  let profileDirectory = join(home, '.config/tunnel-client');
  let directorySource = 'home-default';
  if (safePath(env.XDG_CONFIG_HOME) && isAbsolute(env.XDG_CONFIG_HOME)) { profileDirectory = join(env.XDG_CONFIG_HOME, 'tunnel-client'); directorySource = 'XDG_CONFIG_HOME'; }
  if (safePath(env.TUNNEL_CLIENT_PROFILE_DIR)) { profileDirectory = resolve(env.TUNNEL_CLIENT_PROFILE_DIR); directorySource = 'TUNNEL_CLIENT_PROFILE_DIR'; }
  const selections = ['TUNNEL_CLIENT_CONFIG', 'TUNNEL_CLIENT_PROFILE', 'TUNNEL_CLIENT_PROFILE_FILE'].filter(k => !!env[k]);
  const conflict = selections.length > 1;
  if (conflict) warnings.push('Conflicting CONFIG/PROFILE/PROFILE_FILE environment selectors; no active selection assumed.');
  const selector = conflict ? null : (selections[0] ?? null);
  const selectedName = selector === 'TUNNEL_CLIENT_PROFILE' && safeName(env[selector]!) ? env[selector]! : null;
  if (selector === 'TUNNEL_CLIENT_PROFILE' && !selectedName) warnings.push('Invalid profile selector omitted.');
  const profiles: ProfileMetadata[] = []; const configFiles: ProfileMetadata[] = [];
  let total = 0;
  async function inspect(path: string, source: string, selected: boolean, directory?: string): Promise<ProfileMetadata> {
    const result: ProfileMetadata = { path, name: basename(path), source, selected, status: 'skipped' };
    try {
      const original = await fs.lstat(path);
      if (original.isSymbolicLink() && directory) {
        const target = await fs.readlink(path);
        if (isAbsolute(target)) { result.reason = 'Named profile symlink must be relative.'; return result; }
      }
      const real = await fs.realpath(path);
      if (directory && !inside(directory, real)) { result.reason = 'Profile resolves outside profile directory.'; return result; }
      const handle = await fs.open(real, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      try {
        const stat = await handle.stat();
        if (!stat.isFile() || stat.size > limits.maxFileBytes || total + stat.size > limits.maxTotalBytes) { result.reason = 'Not a regular file or inspection size limit reached.'; return result; }
        const buffer = Buffer.alloc(Math.min(limits.maxFileBytes, limits.maxTotalBytes - total) + 1);
        const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
        total += bytesRead;
        if (bytesRead > limits.maxFileBytes || total > limits.maxTotalBytes) { result.reason = 'Inspection size limit reached.'; return result; }
        Object.assign(result, metadata(buffer.subarray(0, bytesRead).toString('utf8')), { status: 'inspected' });
      } finally { await handle.close(); }
    } catch (e) { result.status = (e as NodeJS.ErrnoException).code === 'ENOENT' ? 'missing' : 'skipped'; result.reason = result.status === 'missing' ? 'Not found.' : 'Could not safely inspect file.'; }
    return result;
  }
  // No recursive walk: bounded directory iteration, not readdir on an unbounded tree.
  try {
    const realDirectory = await fs.realpath(profileDirectory);
    const dir = await fs.opendir(realDirectory);
    let seen = 0;
    for await (const entry of dir) {
      if (++seen > 256) { warnings.push('Profile directory entry inspection truncated.'); break; }
      if (!safeName(entry.name) || !/\.ya?ml$/.test(entry.name)) continue;
      if (profiles.length >= limits.maxProfiles) { warnings.push('Profile inspection truncated to 64 files.'); break; }
      const name = entry.name.replace(/\.ya?ml$/, '');
      profiles.push(await inspect(join(profileDirectory, entry.name), 'profile-directory', selectedName === name, realDirectory));
    }
  } catch { warnings.push('Profile directory not found or not readable.'); }
  for (const key of ['TUNNEL_CLIENT_CONFIG', 'TUNNEL_CLIENT_PROFILE_FILE']) {
    if (!env[key]) continue;
    if (!safePath(env[key])) { warnings.push(`${key} path omitted because it is invalid or credential-like.`); continue; }
    configFiles.push(await inspect(resolve(env[key]!), key, selector === key));
  }
  profiles.sort((a, b) => a.name.localeCompare(b.name));
  if (selectedName && !profiles.some(p => p.selected)) warnings.push('Selected named profile was not found within inspection limits.');
  warnings.push('Binary paths are unverified candidates. Metadata is not full YAML validation, live process state, credential validation or tunnel readiness. No commands were executed.');
  return { schemaVersion: 1, readOnly: true, platform: options.platform ?? process.platform,
    clients: candidates.filter(c => c.available && c.name === 'tunnel-client').map(c => ({ id: `${c.name}:${c.path}`, path: c.path, source: `${c.name}: ${c.source} (unverified candidate)` })),
    profiles: [...profiles, ...configFiles].filter(p => p.status === 'inspected').map(p => ({ id: p.path, path: p.path, name: p.name.replace(/\.ya?ml$/, ''), tunnelID: p.tunnelID, endpoint: p.mcpOrigin, source: `${p.source}${p.selected ? ' (selected)' : ''}; metadata only` })),
    warnings, binaries: candidates, tunnel: { profileDirectory, directorySource, selectedProfile: selectedName, selectionSource: selector, profiles, configFiles, warnings }, limits: { ...limits } };
}
