#!/bin/bash
set -euo pipefail
# Native encoding only: PNG validity alone cannot validate macOS ICNS decoding.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo "App icon packaging requires macOS iconutil and sips." >&2; exit 2; }
[[ $# == 1 && ! -e "$1" && ! -L "$1" ]] || { echo "Provide one new ICNS destination; existing files are not overwritten." >&2; exit 2; }
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
/usr/bin/iconutil --convert icns --output "$TEMP/AppIcon.icns" "$ROOT/Resources/AppIcon.iconset"
/usr/bin/iconutil --convert iconset --output "$TEMP/Verified.iconset" "$TEMP/AppIcon.icns"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=""; [[ "$scale" == 1 ]] || suffix="@2x"
    file="$TEMP/Verified.iconset/icon_${size}x${size}${suffix}.png"
    [[ -s "$file" ]] || { echo "Missing native icon representation: $size $scale" >&2; exit 1; }
    dimensions="$(/usr/bin/sips -g pixelWidth -g pixelHeight "$file")"
    width="$(awk '/pixelWidth:/{print $2}' <<< "$dimensions")"
    height="$(awk '/pixelHeight:/{print $2}' <<< "$dimensions")"
    expected=$((size * scale))
    [[ "$width" == "$expected" && "$height" == "$expected" ]] || { echo "Invalid native icon dimensions: $size $scale" >&2; exit 1; }
  done
done
(set -o noclobber; cat "$TEMP/AppIcon.icns" > "$1")
echo "App icon: native encoding and all 10 standard/Retina representations verified."
