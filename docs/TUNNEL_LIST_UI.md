# Simplified tunnel list

The default tunnel page now starts with compact rows. Each row contains its
name, observed runtime status, a short MCP binding summary, one start/stop action
and an Edit button. It no longer repeats credential fields, provider forms,
profile paths, diagnostic panels and destructive controls for every record.

Add and Edit open a scrollable sheet. The user chooses a name and MCP services,
then the connection provider. Custom profile paths and start-all participation
are collapsed by default. Existing records have collapsed runtime details and
authentication/maintenance sections. The page's first-connection/client guide
is also collapsed below the records instead of preceding them.

Edits are local drafts until Save/Add. Cancel does not append an empty record
or modify configuration. Saving validates bindings, rejects stale workspace or
configuration revisions, and preserves all other records. Runtime operations
and persistent credential actions retain explicit confirmation. Authentication
and diagnostic operations require the draft to be saved first. Running records
can be inspected, but their configuration is locked until stopped.

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
