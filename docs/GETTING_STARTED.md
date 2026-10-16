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

### First connection without an existing profile
In **ChatGPT 连接**, start the local gateway from the first-step card. Enter the existing OpenAI Tunnel ID and a new local connection name, then choose **创建新连接配置** and review the confirmation. OneMCP invokes the official client's `init` command; it does not create an OpenAI tunnel or key. Then choose **检查连接** and **启动隧道**, reviewing their separate confirmations. If a named profile already exists, skip creation. Reusing a profile file is an optional collapsed path, not a first-run prerequisite.

When the local gateway is stopped, dependent actions are disabled and the first-step card explains the next action. A selected existing file disables creation to prevent overwriting it. Runtime credentials still follow the official client's existing profile or explicit session mechanism.

### Global controls and official tunnel status

The persistent top bar starts/stops the shared local gateway. Settings contains configuration and environment repair, not a second start control. Add MCP is inside the MCP services page.

After an explicitly started official tunnel publishes its private per-run health URL, One MCP reads `GET /health?details=true` and displays native component status and observation times. This is the official [health contract](https://github.com/openai/tunnel-client/blob/master/docs/health.md), not a simulated dashboard. Only bounded status metadata is retained; no raw detail objects, credentials, logs, tool arguments, or results. Older clients returning 404 show an unsupported-detail notice rather than a false failure or success. Stop/disconnect clears this view. The application does not embed the official `/ui` management surface, which includes login and other actions.

A healthy process or `/readyz` 200 does not prove a ChatGPT tool call. Component observations are historical; `unknown`, `degraded`, and missing evidence remain visibly distinct. Native macOS compilation/rendering has not been performed in the Linux development environment.
