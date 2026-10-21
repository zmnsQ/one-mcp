# Dashboard and tunnel cards: verification, 2026-10-21

## Changes

- Default overview with service/gateway/tunnel summary cards, first-use steps, service controls and independent tunnel cards.
- Provider-neutral “隧道” navigation, provider badges, separate read-only tunnel details, explicit local/public address labels and copy controls.
- Shared status presentation and non-template, pre-rendered colored native menu images. Color is accompanied by a symbol and text; unknown is distinct from stopped.
- Service-stop impact wording follows gateway behavior, including the legacy Cloudflare entry. Confirmations reject changed workspace or gateway controller identity.
- Existing record bindings, credentials, authentication and routing policy are unchanged. No real tunnel or user connection was started, stopped or modified for this work.

## Executed in assistant Linux workspace

- Swift 6.0.3 `swiftc -frontend -parse` for all app and test Swift files: passed. This is syntax parsing, not macOS compilation or type checking.
- `SWIFTC=... python3 scripts/check-dashboard-presentation.py`: passed 12 assertions using the production Foundation-only status enum.
- `git diff --check`: passed.
- Locked existing gateway dependencies were reused after an exact package-lock comparison. TypeScript build passed.
- `npm test`: initial smoke/advanced/workflow checks passed, including the real 60-second fixture timeout. CLI socket startup then failed because this runner could not create the private Unix control socket.
- Remaining suite, starting with CLI, was rerun with the repository-supported `ONEMCP_SKIP_SOCKET_TEST=1`. See caveat below; this is not an unqualified full-suite pass.

## Not yet verified

- Private Unix-domain socket integration skipped where the suite supports it; IPC remains unverified on this runner.
- SwiftUI/AppKit macOS build and XCTest, including new native image rendering tests, have not run. Linux has no macOS SDK.
- Native menu color, light/dark/high-contrast appearance, narrow-window layout, multiple windows and modal cancellation require real macOS acceptance.
- Genuine OpenAI/Cloudflare and ChatGPT end-to-end connectivity was not tested. Fixture tests use mock processes only.
- No GitHub Actions workflow was dispatched. The existing macOS compile workflow remains manual-only.

## Native acceptance checklist

1. Run `swift build` and `swift test` with the supported macOS/Xcode toolchain.
2. Inspect dashboard and tunnel cards in narrow and wide windows; verify long names and large text remain usable.
3. Open read-only details while a tunnel runs. Close with Done/Escape; no config change or process restart should occur.
4. Open/cancel editors, switch workspace in a second window while confirmation is open, and verify stale actions are rejected.
5. Verify real native menu colors are visible in light/dark appearance; labels and symbols must stay understandable without color.
6. Disconnect the UI from a shared gateway: summary should say 未确认, never imply all services stopped.
7. With authorized fixture services, stop one service and verify only dependent record tunnels (plus legacy Cloudflare entry) are withdrawn.
