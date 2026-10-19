# Tunnel records validation — 2026-10-19

Baseline: upstream `661bd2f334e4938141563e98e1a73513d75e52eb`.
All tests below ran in the cloud Linux workspace, with local fixtures only.

- `npm run build`: passed (TypeScript).
- `ONEMCP_SKIP_SOCKET_TEST=1 npm test`: exit 0, 82 PASS output groups.
- Three Unix-socket integration blocks were explicitly skipped. A standalone
  Unix socket probe returned `listen EPERM` in this runner; this is not a pass.
- `git diff --check`: passed.
- New record tests additionally exercise read-only configuration migration,
  round-trip fixed bindings, distinct profile files, empty/duplicate bindings,
  cross-record tool denial, unrelated-service survival, stopped endpoints,
  separate Cloudflare audiences/metadata, unchanged shared OAuth policy,
  and fail-closed Quick endpoints before an origin is assigned.
- New Cloudflare pool tests use fake children and fixture HTTP servers. They
  cover proxy path restrictions, credentials/header forwarding, per-record
  lifecycle, failure/restart, cancellation and duplicate named identities.
- App and CLI require the `tunnelRecordsVersion=1` fingerprint before sending
  scoped operations. Old runtimes cannot silently ignore selected bindings.
- New native XCTest cases and existing source-level checks were added/updated.
  Swift/macOS compilation, SwiftUI rendering, Keychain dialogs and native
  XCTest execution were not available in Linux and remain unverified.
- No real OpenAI/Cloudflare tunnel, provider account, credential grant, DNS or
  user's running gateway was created or changed. Genuine provider calls and
  OAuth end-to-end authorization remain separate acceptance work.

## Mac acceptance

1. Open old aggregate, individual and Cloudflare settings without saving. Verify
   records show the previous selected services and no file or process changes.
2. Add two records sharing some services; save/reopen. Add a new service and
   verify it is not automatically bound.
3. Stop one record or one backend; unrelated records should remain running.
4. Confirm old gateway attachment blocks scoped startup with an upgrade/restart
   explanation, and a freshly built gateway enables it.
5. Verify record-specific Keychain save/load/forget, missing-service handling,
   Start All cancellation, and per-record readiness/failure display.
6. Only after reviewing targets and permissions, test actual provider/OAuth
   setup and a trusted read-only tool call on each selected route.

## Menu-bar status update

- Chinese menu groups now list configured MCP services and tunnel records,
  including additional active shared-runtime entries. Names and icons come from
  existing observed state, with no extra timer, network request or process.
- Structured tunnel events distinguish running, ready, stopped, checking and
  errors. Submitted commands show starting/stopping until runtime evidence;
  failed responses and timeouts clear misleading in-progress labels.
- Disconnected/connecting controllers show “状态未确认”, rather than claiming
  shared services stopped. Owned gateway exit and workspace/snapshot changes
  discard stale tunnel presentation states. Ready is explicitly not an
  end-to-end tool-call claim. Raw error messages and credentials are not printed
  in the tray.
- Added MenuBarStatusTests for localized mappings, unknown states, disconnect,
  readiness and structured errors. Native XCTest and menu rendering still need
  macOS acceptance. Tree-sitter syntax parsing passed for the changed Swift
  sources/tests; it is not a Swift compiler or type checker.
- macOS acceptance: open tray with no services, then multiple records; exercise
  start/stop, doctor, rejected start, timeout, backend crash, detach/reconnect,
  workspace switch and gateway restart. Check labels update without reopening
  the main window, Chinese layout remains readable, and stop/quit confirmations
  retain their behavior.

For this tray-only increment, TypeScript build and both tunnel-records and
Cloudflare-records smoke suites passed again. An attempted full-suite rerun lost
its runner session before a terminal result, so it is not counted as a new full
pass; the 82-group result above belongs to the preceding records revision.
