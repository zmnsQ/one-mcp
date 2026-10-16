# Testing and acceptance

## Recorded gateway verification

The [2026-10-15 results](../gateway/validation/RESULTS-2026-10-15.md) record a successful TypeScript build and 35 passing checks against local in-memory MCP fixtures. The fixtures use loopback and do not connect to private services or a real ChatGPT workspace.

```sh
cd gateway
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

Coverage includes startup/shutdown, aggregate and individual routing, allowlists, aliases, tool-list pagination and changes, malformed requests, origin/host rejection, concurrency limits, client disconnection, process crashes and a real 60-second timeout.

## Native verification still required

Run `swift build` and `swift test` on a compatible Mac, then test native import, workspace switching, Keychain save/load, process lifecycle and interrupted flows. Six Swift configuration-discovery test cases are supplied; they were not executed in Linux. Do not treat gateway fixture passes as macOS UI validation.

## End-to-end verification still required

Install the official tunnel client, configure an existing authorized tunnel, verify readiness, and make a safe real tool call in the intended ChatGPT workspace. Test stopped upstreams, expired credentials, network interruption and restored sessions. Do not remove Origin/Host protections simply to make a failing integration work; inspect actual compatibility first.

## CI and history

The macOS workflow is manually dispatched only and does not sign, notarize, launch or deploy. Check runner billing before use. Earlier static and Linux reports are historical records; this document distinguishes them from native and external tests that remain unrun.
