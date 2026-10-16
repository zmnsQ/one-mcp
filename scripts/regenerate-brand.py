#!/usr/bin/env python3
"""Optional maintainer utility. Requires Inkscape and Pillow; not part of app builds."""
from pathlib import Path
import subprocess
import tempfile
import struct
from PIL import Image
root = Path(__file__).resolve().parents[1]
source = root / 'docs/brand/one-mcp-icon.svg'
iconset = root / 'Resources/AppIcon.iconset'
iconset.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as temp:
    for size in (16, 32, 64, 128, 256, 512, 1024):
        subprocess.run(['inkscape', str(source), '--export-type=png',
                        f'--export-filename={temp}/{size}.png',
                        f'--export-width={size}', f'--export-height={size}'], check=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = '@2x' if scale == 2 else ''
            Image.open(f'{temp}/{size * scale}.png').save(iconset / f'icon_{size}x{size}{suffix}.png')
    master = Image.open(f'{temp}/1024.png')
    # PNG-backed Apple icon types include 16 px, plus explicit Retina variants.
    chunks = []
    for tag, size in [('icp4',16),('icp5',32),('icp6',64),('ic07',128),('ic08',256),('ic09',512),('ic10',1024),('ic11',32),('ic12',64),('ic13',256),('ic14',512)]:
        data = Path(f'{temp}/{size}.png').read_bytes()
        chunks.append(tag.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
    body = b''.join(chunks)
    (root / 'Resources/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
    master.save(root / 'docs/brand/one-mcp-icon.png')
