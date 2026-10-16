#!/bin/bash
set -euo pipefail
# Explicit user-invoked build. No install, launch, login item, public listener, or notarization.
if [[ "$(uname -s)" != Darwin ]]; then
  echo "One MCP uses SwiftUI/AppKit. Build this app on macOS 26 with Xcode 26; Linux cannot provide these frameworks." >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v swift >/dev/null || { echo "Install Xcode 26 and select its toolchain." >&2; exit 2; }
command -v npm >/dev/null || { echo "Install Node.js 22+ from its official source." >&2; exit 2; }
cd "$ROOT/gateway"
if [[ -f package-lock.json ]]; then npm ci --ignore-scripts; else npm install --ignore-scripts; fi
npm run build
node "$ROOT/scripts/verify-gateway-package.mjs" "$ROOT/gateway"
cd "$ROOT"
swift build --configuration release
BIN="$(swift build --configuration release --show-bin-path)"
# Unique destination: never delete or overwrite an existing user artifact.
OUT="$ROOT/dist/MCPHarbor-$(date +%Y%m%d-%H%M%S)-$$"
APP="$OUT/One MCP.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/gateway"
cp "$BIN/MCPHarbor" "$APP/Contents/MacOS/MCPHarbor"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/gateway/dist" "$ROOT/gateway/node_modules" "$APP/Contents/Resources/gateway/"
cp "$ROOT/gateway/package.json" "$APP/Contents/Resources/gateway/"
# Validate the exact packaged layout, including cli.js and transitive package resolution.
node "$ROOT/scripts/verify-gateway-package.mjs" "$APP/Contents/Resources/gateway"
mkdir -p "$APP/Contents/Resources/skills/one-mcp" "$APP/Contents/Resources/docs"
cp "$ROOT/skills/one-mcp/SKILL.md" "$APP/Contents/Resources/skills/one-mcp/SKILL.md"
cp "$ROOT/docs/CLI.md" "$APP/Contents/Resources/docs/CLI.md"
test -s "$APP/Contents/Resources/skills/one-mcp/SKILL.md"
test -s "$APP/Contents/Resources/docs/CLI.md"
cp "$ROOT/README.md" "$OUT/README.md"
# Signing is opt-in and uses an identity the user already has. No credentials are created.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP"
  codesign --verify --strict "$APP"
fi
printf '\nCreated: %s\nNot launched. No notarization performed. Node and tunnel-client remain separately installed.\n' "$APP"
