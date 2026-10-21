# UI usability repair · 2026-10-21

## Evidence and scope

The supplied macOS screenshots were actually inspected before implementation. They show status text markedly dimmer than actionable tray items, a large runtime instance block above loosely separated settings disclosures, and an always-present bulk-start result region above page content. The accompanying interaction report identifies disclosure arrows as the only responsive click targets.

The supplied screenshots are not republished here. There is **no new native screenshot** in this change: this environment cannot run macOS SwiftUI. The diagram below is an implementation map, not a screenshot or pixel-accuracy claim.

## Implemented layout

```text
Main window (minimum 1020 × 700)
├─ Sidebar (minimum 245, ideal 265)
│  ├─ Workspace selector
│  ├─ Overview / MCP services / Tunnels / Settings
│  └─ Fixed bottom status and controls
│     ├─ Gateway state, confirmed MCP/tunnel running counts
│     ├─ Current errors / previous start failures or skipped steps
│     ├─ Start all | Stop all (vertical fallback when needed)
│     └─ Start gateway only, when not running
│        Clicking status opens current state + last startup results.
└─ Page area
   ├─ Page title, unsaved/pending notices (no global start/results block)
   └─ Settings: 16-point spacing between grouped surfaces
      ├─ Runtime environment (instance list expandable)
      ├─ AI management instructions
      ├─ Components and advanced settings
      ├─ Credentials and login information
      ├─ Backup and recovery
      └─ Diagnostics and tool documentation
```

### Tray

- A window-style MenuBarExtra replaces disabled-looking static NSMenu entries.
- Read-only rows remain actual text, not fake clickable buttons. Both names and status use primary system text color and a 13-point font; status symbols use semantic green/orange/red/neutral colors and distinct shapes.
- Text and accessibility labels name every state. Color is supplementary, not the only signal.
- Long names wrap, the service/tunnel list scrolls (280-point maximum), and the panel uses an opaque dynamic system background.
- Opening One MCP targets a single identified main Window instead of selecting the first NSApp window or creating duplicate WindowGroup windows.
- Stop-all confirmation and quit/save handling remain intact.

### Expandable sections

`FullRowDisclosureStyle` applies at the root, including service editors, tunnel settings and sheets. Each title is a real button with a full-width hit area, minimum 44-point height, visible focus outline, expanded/collapsed accessibility value, native Space activation and left/right-arrow collapse/expand.

Expanded contents are siblings of the header button, not its descendants. No parent tap gesture wraps TextFields, Toggles, copy buttons, destructive actions, or nested disclosures.

### Settings and navigation

Six consistent surfaces group settings, each with 16-point padding, a 12-point radius and system separator border. Advanced cards have icons, clear titles and summaries before opening. Shared runtime instances remain available inside their own disclosure instead of dominating the initial page.

Global startup controls and results are removed from the shared page header. Startup details appear only on request in a closable sheet. Current error counts and previous failures/skips remain visible in the sidebar. Unknown/disconnected runtime states say “状态待确认”, rather than implying that everything has stopped. Current state is explicitly distinguished from historical startup results.

The Overview log shortcut opens both the diagnostics section and its nested logs disclosure. Narrow sidebar controls use a horizontal/vertical `ViewThatFits` fallback; labels are not intentionally truncated.

## Preserved behavior

- Original start-all confirmation and captured plan/workspace/revision guards.
- Stop-all dependency warning, cancellation of queued starts and shutdown behavior.
- Independent service and tunnel stop confirmations and controls.
- Node/script/port settings and running-state editing guards.
- Environment checks, repair, AI-management instructions, Keychain save/load/delete, backup/restore, tool/log exports and live logs.
- CLI-to-MCP editor, gateway code, configuration models/migration, allowlists and security defaults are unchanged.
- No remote-service launches, provider calls, new credentials, automatic installs, automatic Actions runs or user-Mac operations are introduced.

## Validation performed

Passed in the assistant's Linux workspace, using a lightweight Swift 6.0.3 compiler:

1. `swiftc -frontend -parse Sources/MCPHarbor/*.swift Tests/MCPHarborTests/*.swift`
2. `SWIFTC=... python3 scripts/check-dashboard-presentation.py`: existing 12 production status assertions.
3. `SWIFTC=... python3 scripts/check-ui-usability.py`: 12 tests covering source structure, settings/action guards, tray readability contract, single-window targeting, root disclosure style, keyboard/focus contract, bulk controls placement, scroll bounds, diagnostics expansion, palette mapping, plus compiled production status/summary/startup-result models.
4. Independent read-only review: controls remain independent; settings actions preserved; unknown counts, window reopening and narrow controls reviewed and corrected.
5. Source/test baseline compared by Git blob hashes against `dd64bf25e4c8bd4cc0e5c360314d0b92439eb71a`: 49 pre-existing files matched before editing.

New macOS XCTest model coverage is included in `UIStatusPresentationTests.swift`, but **the native XCTest target has not run**. Linux parsing is not macOS compilation or UI validation. The structural checks test code contracts, not real mouse/keyboard event delivery.

No heavy build, GitHub Actions dispatch, native app launch, VoiceOver session or real screenshot capture was performed. The repository's macOS workflow remains manual-only and unchanged.

## Native acceptance checklist (not yet executed)

- Build with the project's supported macOS 26 / Swift 6.2 toolchain; run XCTest.
- Light, dark, Increase Contrast and Reduce Transparency: read tray names, all eight states, empty lists and long names.
- Tray Open twice, close the main window, then reopen: exactly one main window; quit still honors unsaved configuration and process handling.
- Every disclosure: click arrow, title and trailing whitespace; repeated collapse/expand; Tab/Space and left/right arrows; visible focus and VoiceOver expanded/collapsed announcement.
- Within expanded content: Toggle, TextField, picker, button, text selection and nested disclosure do not toggle their parent.
- Sidebar at 245 points and main window at 1020 × 700: all navigation and controls accessible, no clipped button labels; horizontal/vertical fallback works.
- Start success, partial failure, skipped steps, cancellation and retry: no results block on each page, details open/close correctly, failures stay discoverable; confirmation cancellation never starts/stops anything.
- Switch workspaces during confirmation: stale actions still rejected; disconnected state never claims known stopped counts.
- Overview → logs opens both disclosure levels; every original settings operation remains accessible.
