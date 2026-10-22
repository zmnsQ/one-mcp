#!/usr/bin/env python3
"""Linux-safe source checks; not a native iconutil or macOS rendering test."""
from pathlib import Path
import plistlib
import subprocess
from PIL import Image
root = Path(__file__).resolve().parents[1]
iconset = root / 'Resources/AppIcon.iconset'
expected = set()
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        expected.add(name)
        with Image.open(iconset / name) as image:
            image.load()
            assert image.size == (size * scale, size * scale), name
            assert image.mode == 'RGBA', name
            assert image.getchannel('A').getextrema() == (0, 255), name
            # The brand is navy/mint/white; red corruption is not in source pixels.
            assert not any(r > g + 40 and r > b + 40 and a > 128 for r, g, b, a in image.getdata()), name
assert {p.name for p in iconset.glob('*.png')} == expected
with (root / 'Resources/Info.plist').open('rb') as file:
    assert plistlib.load(file)['CFBundleIconFile'] == 'AppIcon'
build = (root / 'scripts/build-macos-app.sh').read_text()
assert 'bash "$ROOT/scripts/build-app-icon.sh" "$APP/Contents/Resources/AppIcon.icns"' in build
assert 'cp "$ROOT/Resources/AppIcon.icns"' not in build
assert not (root / 'Resources/AppIcon.icns').exists()
assert 'struct.pack' not in (root / 'scripts/regenerate-brand.py').read_text()
helper = (root / 'scripts/build-app-icon.sh').read_text()
for contract in ('/usr/bin/iconutil --convert icns', '/usr/bin/iconutil --convert iconset', '/usr/bin/sips', 'for size in 16 32 128 256 512', 'for scale in 1 2', '! -e "$1"', '! -L "$1"', 'set -o noclobber'):
    assert contract in helper, contract
for file in ('build-macos-app.sh', 'build-app-icon.sh'):
    subprocess.run(['bash', '-n', str(root / 'scripts' / file)], check=True)
print('PASS 10 source PNGs, size/alpha/palette, plist, native packaging contracts and shell syntax (not native rendering)')
