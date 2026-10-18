# Remote connection validation — 2026-10-18

## Cloud verification

- Installed locked dependencies with `npm ci --ignore-scripts` (temporary cache).
- TypeScript compilation passed with `NODE_OPTIONS=--max-old-space-size=256 npm run build`.
- Regression command `ONEMCP_SKIP_SOCKET_TEST=1 NODE_OPTIONS=--max-old-space-size=256 npm test` passed. The explicit skip applies to real Unix-domain-socket integration only; injected IPC logic and stdin-bound real gateway tests still ran.
- Incoming OAuth fixtures cover RS256/ES256 signatures, RFC9068 token types/required claims, wrong issuer/audience/expiry/nbf/scope/signature, token-controlled key URL rejection, duplicate/query credentials, bounded JWKS responses/timeouts, caching/rotation and concurrent policy changes.
- Cloudflare fixtures use mocked processes and network responses: input/URL checks, command/environment isolation, no auth/no spawn, readiness/metadata stages, redirects, size/time limits, stale checks, termination and redaction.
- Real loopback HTTP gateway fixture verifies saved OAuth startup, protected discovery, hostile Host/Origin rejection, unauthenticated MCP rejection and local health access.
- Shared-runtime fixtures and package component verification passed.
- Changed Swift source syntax parsed successfully with tree-sitter Swift. This is not Swift typechecking or a macOS build.

## Explicitly not verified in cloud

The runner rejects Unix-domain-socket `listen` with EPERM. A normal full test attempt failed at that sandbox boundary, so Unix socket integration was explicitly skipped rather than reported as passing. No actual macOS SwiftUI build, XCTest execution, Keychain access, real OAuth login/grant, Cloudflare account/DNS/credentials or public tunnel was performed.

## Mac acceptance checklist

Use a separate clean worktree for this commit. Preserve existing uncommitted files and diagnostic reports.

1. `cd gateway && npm ci && npm test` without `ONEMCP_SKIP_SOCKET_TEST`; then run the normal macOS app build and XCTest suite.
2. Open existing workspace: legacy settings decode, saved Keychain identity persists, no automatic network publishing on launch/save.
3. Verify API key/help links, program detection, new/existing Profile paths and original OpenAI doctor/run/stop flow.
4. Edit shared settings via AI/CLI: app displays new values immediately, live PID and applied policy remain unchanged, correct restart notices appear.
5. Configure a compatible external OAuth provider manually. Confirm unauthenticated/wrong-audience/expired tokens cannot list or call tools. Confirm a valid consented client can access only aggregate allowlisted tools.
6. Create/authorize Cloudflare setup manually. Named origin and OAuth URL must match. Verify local ready, public metadata, real client login and a harmless tool call separately. Stop connection and verify it closes.
7. Quick mode is development-only: update external audience for the random URL, verify only that session URL is accepted, stop restores saved OAuth resource.
8. Test top Start All for each selected transport, shared GUI/CLI control, explicit stop, failure recovery, app restart and an existing MCP server whose ID is `cloudflare`.

Do not publish a production release until macOS and real-provider acceptance are complete.
