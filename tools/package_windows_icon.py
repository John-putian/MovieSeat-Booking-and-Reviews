"""Pack resized PNGs into a multi-resolution Windows icon (no raster editing)."""
from pathlib import Path
import struct
root = Path(__file__).resolve().parents[1]
sizes = [16, 32, 48, 64, 128, 256]
images = [(root / f'.tools/brand-icons/icon-{size}.png').read_bytes() for size in sizes]
offset = 6 + 16 * len(images)
entries = []
for size, data in zip(sizes, images):
    entries.append(struct.pack('<BBBBHHII', size if size < 256 else 0,
        size if size < 256 else 0, 0, 0, 1, 24 if data[25] == 2 else 32, len(data), offset))
    offset += len(data)
target = root / 'windows/runner/resources/app_icon.ico'
target.write_bytes(struct.pack('<HHH', 0, 1, len(images)) + b''.join(entries) + b''.join(images))
print('Windows multi-resolution icon packaged.')
