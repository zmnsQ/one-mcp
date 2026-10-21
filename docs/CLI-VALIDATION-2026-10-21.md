# CLI service validation — 2026-10-21

Implementation includes a native manual CLI tool editor, backward-compatible saved service type, built-in stdio adapter, gateway routing/capability checks, explicit typed parameters, minimum environment, output/time/concurrency limits, cancellation and process-group cleanup.

Executed in the assistant Linux workspace:
- TypeScript compilation passed using the repository's existing locked dependencies; no new dependency.
- `ONEMCP_SKIP_SOCKET_TEST=1 npm test` passed, including the actual 60-second existing timeout regression and new `cli-service-smoke.mjs`.
- Unix-domain socket checks were explicitly skipped by the supported test flag. This is not a claim that private Unix IPC passed.
- New tests exercise actual MCP stdio and loopback gateway calls with harmless test-owned Node CLI fixtures. They test invalid descriptors, old configuration compatibility, drafts, typed argument validation, literal argv, explicit environment isolation, secret redaction, output bounds after redaction, timeout, cancellation, concurrency, background descendant cleanup, capability marker, tool allowlist routing and stop.
- Independent code review prompted fixes for gateway/CLI timeout alignment, background process cleanup, encoded output growth after redaction, and omitting raw truncated output that could contain a partial secret.
- Swift 6.0.3 syntax parsing of all app/test sources passed; Foundation Models.swift typecheck and executable fixtures for legacy decode, CLI roundtrip/drafts, invalid parameters/limits and fingerprint flattening passed. Native SwiftUI/AppKit compilation, macOS XCTest and visual acceptance remain unverified on Linux.
- `git diff --check` passed.

Not performed: real third-party CLI execution, real tunnels, credential creation, paid builds or manually dispatched GitHub Actions. The feature does not claim sandboxing, automatic help conversion, or cross-platform process-tree support outside the Mac/POSIX target.
