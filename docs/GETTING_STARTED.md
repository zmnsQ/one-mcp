# Getting started

## Build

Use macOS 26+, Xcode 26 / Swift 6.2 and Node.js 22+. Install dependencies from the lockfile with `npm ci --ignore-scripts` in `gateway/`, then run `npm run build`. From the repository root, run `bash scripts/build-macos-app.sh` or open `Package.swift` in Xcode. Native builds remain to be validated. Do not run the app as root.

Install the official [OpenAI tunnel client](https://github.com/openai/tunnel-client/releases/latest) separately if you need a private cloud connection. One MCP manages an existing executable; it does not download a client or create accounts and keys.

## Add a first server

1. In connection settings, set actual absolute paths for Node, `gateway/dist/index.js`, and the optional tunnel client.
2. Start the gateway and confirm the action. It listens on `127.0.0.1` and does not automatically start an MCP server.
3. Add an already-installed trusted stdio MCP program. Use separate arguments rather than a shell command string; no `export`, pipes or `&&`.
4. Supply needed environment values only in the dedicated credential fields. They are session-only unless explicitly saved to Keychain.
5. Discover/start the service. Discovery executes the selected program. Initially no tool is allowed through HTTP.
6. Stop it, choose a harmless read-only tool, and start it again. Confirm the schema and published tool name.

## Connect a tunnel

Choose aggregate or individual mode. For each selected endpoint, provide a distinct profile and the correct tunnel ID. Provision the tunnel and least-privilege credentials yourself using the official Platform settings. Do not paste keys into issue reports or chat.

Initialize the profile, run Doctor, then start the client. Initialization and Doctor success do not by themselves establish a working cloud connection. One MCP checks the official client's loopback readiness endpoint; finish by performing one safe read-only call from the intended ChatGPT workspace.

See [the full operations guide](OPERATIONS.zh-CN.md) for setup fields and the distinction between tunnel use/manage permissions. Official UI names may change; consult current provider documentation.

## Import existing configuration

Choose JSON configuration files explicitly, inspect candidate commands and arguments, and merge selected entries. Strict JSON is supported; JSONC comments are not. Secret environment values are discarded and allowlists reset. Relative commands must be corrected before launching. Full configuration restore is a separate replacement operation, not the merge workflow.

## Update

Preserve local code edits, inspect `git status`, and run `git pull --ff-only`. Rebuild the application. Keep runtime data and credentials outside the repository. The legacy `MCPHarbor` internal paths are retained intentionally.
