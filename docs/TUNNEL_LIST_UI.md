# Simplified tunnel list

The default tunnel page now starts with compact rows. Each row contains its
name, observed runtime status, a short MCP binding summary, one start/stop action
and an Edit button. It no longer repeats credential fields, provider forms,
profile paths, diagnostic panels and destructive controls for every record.

Add and Edit open a scrollable sheet. OpenAI setup is ordered as account and
safe credential reference, explicit MCP bindings, then local Profile setup.
New records use one “Create and save local Profile” primary action: persist the
stable record first, invoke init, then wait for its correlated terminal result.
No advanced section contains a required creation step. Existing profiles and
Cloudflare use save-only mode; initialization never starts a tunnel.

Edits remain drafts until the primary action. Before submission Cancel discards
them; after a successful configuration save, Close preserves that record and any
submitted creation. Running/creating records are locked, but Close stays available.
Existing records default to save-only, so migration cannot initialize old profiles.
See [creation and credential reuse](TUNNEL_CREATION-2026-10-21.md) for recovery,
account association, tests and the difference from Platform remote creation.

Verification in the Linux cloud workspace:
- Changed Swift source and XCTest files passed tree-sitter syntax parsing.
  This is not native compilation, type checking or visual verification.
- Existing tunnel-records and Cloudflare-records smoke tests use local fixtures;
  no real tunnel/provider or user computer is involved.
- New native tests cover short binding summaries, draft isolation, preserving
  other records, invalid/missing/duplicate bindings, stale edits and capacity.
  XCTest execution and SwiftUI rendering still require macOS.

Mac acceptance: add then cancel; edit then cancel; save/reopen; change workspace
or configuration while editing; inspect a running record; stop/start one record;
verify profile and Keychain confirmation flows; check the sheet at increased
text size. No native screenshot is claimed by this document.

Runtime keys typed in the editor are also staged locally and only applied to
session memory after successful Save. Cancel does not replace the live key.
Keychain Load/Forget/Save remain explicit operations, with persistent changes
confirmed separately; do not treat Cancel as undo for an explicitly executed
Keychain operation. Source checks confirm the list has no credential fields,
Add only opens a sheet, and the key field binds to local state.
