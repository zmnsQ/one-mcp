# Live tool selection validation (2026-10-22)

Scope: Linux fixture processes only. No real MCP services, credentials, accounts, tunnels, user devices, push, or CI were used.

## Implementation

- Private management `updateAllowedTools` validates both explicit arrays and atomically compares the expected set before replacement. Maximum 500 unique nonempty names, each at most 256 UTF-16 code units, no NUL or wildcard `*`; extra parameters are rejected except the standard instance guard.
- Existing upstream process and lifetime remain intact. Already admitted calls finish, but later admission and discovery results use the new policy across individual, aggregate, and tunnel-scoped routes.
- Success returns and emits authoritative allowed names and fingerprints. Runtime capability marker: `liveToolSelectionVersion`. Shared runtime client permits the command and retains its instance guard.
- Stateless HTTP remains POST-only without SSE or advertised list-change push. Success explicitly reports `clientRefreshRequired: true`.

## Tests

`validation/live-allowlist-smoke.mjs` runs real gateway/upstream fixtures and checks:

1. Malformed or missing arrays, duplicate names, wildcard, NUL, overlong names, more than 500 entries, unexpected fields, absent/invalid server, wrong instance, stale expected state, and attempted HTTP management all fail without state mutation.
2. Empty selection immediately hides/blocks individual, aggregate, and scoped tools. A prior call completes without cancellation; a prior discovery returns the new filtered selection. Other services and tunnel processes remain unaffected.
3. Concurrent CAS requests admit only one winner. Re-enabling restores routes and original fingerprints with the same upstream PID. Scoped isolation remains enforced. Initialization does not advertise `listChanged`; GET remains 405.
4. Exactly 500 names are accepted while nonexistent tools remain unrouteable. CLI names must be declared; enable/disable works for CLI wrappers. Updates after stop fail.

`validation/shared-runtime-smoke.mjs` also checks two clients observing and changing the same allowlist with stale CAS rejection. The existing bulk-start source invariant was updated to follow the sidebar component delegation while retaining all safety guard checks.

## Environment limitation

Unix-domain socket listen returns EPERM in the runner. An escalated probe could not launch because of runner read-only mount setup. Accordingly, Unix integration portions in `cli-smoke.mjs`, `runtime-start-smoke.mjs`, and `runtime-snapshot-smoke.mjs` use the existing explicit `ONEMCP_SKIP_SOCKET_TEST=1` switch. Their non-socket checks still run. Real Unix IPC and native macOS behavior remain unverified; stdin and loopback HTTP integration are exercised.

## Executed outcome

TypeScript build passed. The full test script with the explicit Unix skip completed through the workflow tests (including the real 60-second timeout/cancellation case), then exposed the stale sidebar source assertion noted above. After correcting that assertion, all remaining suites passed. A final consolidated run of every suite except that already-passed 60-second workflow suite completed with exit code 0 and the same three explicit Unix skips. The latest live-allowlist test and two-client shared runtime test both passed. `git diff --check` passed.
