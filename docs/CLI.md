# One MCP CLI and AI integration

The CLI and native application use the same legacy-compatible `~/Library/Application Support/MCPHarbor` workspace schema. Runtime management travels over an owner-only Unix socket; it is never exposed on the public MCP endpoint. JSON output has `schemaVersion`, `ok`, `action`, and `result` or `error`. Exit codes: 0 success/preview, 1 runtime failure, 2 invalid input, 3 state conflict.

## Install from source

```sh
cd gateway
npm ci
npm run build
cd ..
./bin/onemcp help
```

Add the repository's `bin` directory to your PATH. No global installer or credentials are installed automatically. Copy `skills/one-mcp` into your agent's supported skill directory only when you choose to install it.

## Inspect before modifying

```sh
onemcp status --json
onemcp workspaces --json
onemcp servers list --json
onemcp config validate --json
onemcp environment inspect --json
```

Use `--workspace ID` for an existing workspace. `--home PATH` overrides the application support root for isolated testing; it does not select your shell home directory. Discovered files are bounded, local, read-only metadata. No binary is executed during discovery, no credential value is returned, and version is unknown unless separately verified.

## Configuration

Mutation commands preview by default. Review the plan, then repeat with `--apply`. Saving also requires `--expect-revision` from `config validate` (use `missing` only for initialization).

```sh
onemcp config init
onemcp config init --apply --expect-revision missing
onemcp config import --file ./mcp-config.json
onemcp config import --file ./mcp-config.json --apply --expect-revision SHA256
onemcp config set --field tunnelClientPath --value /opt/homebrew/bin/tunnel-client
onemcp config allow-tools --id SERVER_ID --names read_file,list_directory
```

Supported import: native workspace JSON, `mcpServers` JSON, and VS Code `servers` JSON with stdio commands. Credentials are discarded, tool permissions start empty, duplicate executable/argument/cwd/environment-name identities are skipped. Relative commands need an absolute executable edited in the GUI before starting. Remote transports and JSONC are rejected, not silently converted.

The GUI can remain open during CLI saved edits. GUI and CLI acquire the same short write lease, compare revisions, and atomically replace only the selected workspace. A clean, stopped GUI reloads external updates; unsaved edits remain intact with a conflict banner and explicit discard/reload choice. While GUI-owned services run, external configuration reload is deferred until they stop. Saved edits never stop, restart or reconfigure existing processes: the CLI returns `effect: saved-only` and `runtimeChanged: false`. Starting a newly configured service or restarting an affected service requires explicit approval. Workspace creation/switching remains blocked while a gateway owns this storage root. A crashed owner's lock may be inspected with `config lock`; recovery only removes a verified dead owner's matching lock. Never remove a live lock. Old app versions that still hold a lifetime lease must be closed once when upgrading. Stale socket paths still require inspection rather than blind deletion.

## Runtime lifecycle

```sh
onemcp gateway run --apply
# In another terminal, or while the native GUI's gateway is running:
onemcp servers start --id SERVER_ID --apply
onemcp tools discover --id SERVER_ID --json
onemcp servers stop --id SERVER_ID --apply
onemcp gateway stop --apply
```

`gateway run` is foreground, owns its child and shuts down on SIGINT/SIGTERM. It does not install an autostart service. Servers never autostart. Starting a server reads only its declared environment keys from this CLI session; no Keychain credentials are fetched. GUI-started runtime remains visible to CLI. CLI-started gateway should be stopped before launching the GUI gateway; the second owner is refused rather than duplicated.

## Tunnels

```sh
onemcp tunnel doctor --id aggregate
onemcp tunnel doctor --id aggregate --apply
onemcp tunnel start --id aggregate --apply
onemcp tunnel stop --id aggregate --apply
```

Use an existing server ID for an individual endpoint. `tunnel init` is available only after reviewing creation of a named official profile. `CONTROL_PLANE_API_KEY` must be supplied securely in this session; never put it in an argument or committed file. The official tunnel executable remains supervised by the shared gateway. Status distinguishes submitted, running and real loopback `/readyz` HTTP 200. Doctor exit zero and readiness are not proof of a successful ChatGPT tool call.

Official configuration reference: https://github.com/openai/tunnel-client/blob/master/docs/configuration.md

## Validation limits

Executed Linux checks cover CLI configuration, mock MCP processes, tunnel subprocess lifecycle, private filesystem coordination and bounded discovery. The Unix-socket end-to-end test is shipped but could not execute in the cloud sandbox (listen EPERM); no successful socket integration is claimed. They do not validate the macOS SwiftUI executable, Keychain, Apple signing or a live ChatGPT tunnel. Run the native build on macOS before distributing a binary.

Existing selected aggregate profiles retain an optional `aggregateProfileFile` reference. Doctor/run use that exact file; init refuses to overwrite it. Its credential references stay in the original official profile. Use the Settings “改用命名 Profile” button, or `config set --field aggregateProfileFile --value ""` with normal revision/apply safeguards, before creating a new named profile.

## Packaged app runtime repair

The native app resolves its bundled gateway from the currently running app. Saved references to an older One MCP/MCPHarbor app bundle migrate to the current complete bundle under the existing configuration lock. Explicit external gateway paths remain unchanged. Settings → 自动检查并修复 rechecks existing local Node locations and app resources; it does not install software, start a service, create credentials or change tool grants. Detailed paths remain under Advanced settings.

The macOS build checks both source and copied gateway layouts using `scripts/verify-gateway-package.mjs`, including index/CLI entries, package metadata, dependency resolution and a read-only CLI help invocation. Native path-resolution XCTest cases are included, but require macOS to execute in this project.

## Copy an AI management prompt

In the app, open Settings → 让 AI 管理 One MCP → 查看使用说明. The sheet validates the current Node and packaged CLI, shows an inspectable prompt and copies it with explicit success feedback. Use it only with an agent authorized to run commands on this Mac; cloud chat alone cannot reach local files. The prompt begins with four read-only JSON checks and includes shell-quoted paths and the selected workspace. It contains no configured keys, environment values or full profiles.

The app bundles `skills/one-mcp/SKILL.md` and this document as readable references. Copying does not install the Skill, grant access, start programs or approve later changes. When runtime files are missing, copying is unavailable until Settings repair succeeds. Native clipboard and Swift prompt tests require macOS; source checks do not substitute for that validation.
