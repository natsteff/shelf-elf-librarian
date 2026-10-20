#!/usr/bin/env python3
"""Package pre-sized, unmodified PNG representations into the macOS ICNS container."""
import struct
import sys
from pathlib import Path

iconset, output = map(Path, sys.argv[1:])
representations = [
    (b'icp4', 'icon_16x16.png'), (b'icp5', 'icon_32x32.png'),
    (b'icp6', 'icon_32x32@2x.png'), (b'ic07', 'icon_128x128.png'),
    (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'),
    (b'ic10', 'icon_512x512@2x.png'), (b'ic11', 'icon_16x16@2x.png'),
    (b'ic12', 'icon_32x32@2x.png'), (b'ic13', 'icon_128x128@2x.png'),
    (b'ic14', 'icon_256x256@2x.png'),
]
chunks = []
for kind, name in representations:
    png = (iconset / name).read_bytes()
    if not png.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError(f'Not a PNG: {name}')
    chunks.append(kind + struct.pack('>I', len(png) + 8) + png)
body = b''.join(chunks)
output.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
