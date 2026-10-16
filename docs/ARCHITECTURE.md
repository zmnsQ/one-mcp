# Architecture

## Components

| Layer | Responsibility |
| --- | --- |
| SwiftUI application | Workspaces, configuration previews, explicit process control, Keychain access and visible diagnostics |
| Node sidecar | Management IPC, local stdio MCP lifecycle, tool discovery, allowlists and aliases |
| Loopback gateway | Stateless Streamable HTTP POST/JSON access for selected tools |
| Official tunnel client | Private outbound transport from the configured local endpoint to the linked service |

The app never silently starts imported services. A workspace change requires stopping processes; imported environment values are not persisted as plain configuration. Each active MCP server has one local process/session shared by allowed callers.

## Routing

The aggregate route is `/mcp`; an individual server is available at `/servers/{id}/mcp`. Both route families exist at loopback, independent of which tunnel arrangement is selected in the interface. A tool list or annotation is descriptive metadata, not permission by itself.

## Lifecycle

Services are not exposed until initialization and discovery complete. A changed tool list invalidates old routing until refreshed. Stop and crash paths remove routes. The gateway propagates cancellation when the original HTTP request disconnects or its managed service stops; this is not a guarantee that upstream side effects are reversible.

Tunnel process launch, profile initialization, Doctor status and readiness are distinct states. Readiness checks stay on loopback and reject redirects. A successful end-to-end ChatGPT call remains the integration acceptance test.

## Security boundaries

The gateway is for a single user running trusted local programs. Host and Origin checks and per-tool allowlists are defensive controls, not a multi-user authorization layer or process sandbox. Child processes retain the user's operating-system permissions. Secret values default to memory, optional persistence uses Keychain, and exported logs require review despite best-effort redaction.

## Not implemented

Resources, prompts, roots, sampling, elicitation, remote HTTP upstream management, durable SSE replay, multi-user OAuth and isolation are outside the current proxy scope. Native process cleanup, real tunnel headers and credentials, and actual third-party MCP behavior require testing beyond the provided fixtures.

## Unified operator plane

`onemcp` and SwiftUI use one settings/workspace schema. A shared exclusive directory lease serializes configuration owners. CLI atomic writes require a content revision; GUI detects outside edits and asks to reload. The running gateway is managed over standard input by its owner and an owner-only Unix socket by CLI clients. Both feed one serialized management dispatcher and one tunnel process manager. HTTP MCP clients cannot access these management commands.

The discovery module reads a bounded set of official configuration locations and returns whitelisted metadata. Existing aggregate profiles are referenced by file path; they are never copied or reinitialized. Candidate executable paths do not establish publisher trust or version. The GUI's five navigation sections use the same store rather than independent state copies.
