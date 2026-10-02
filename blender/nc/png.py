"""Exact 8-bit PNG I/O for data images (no colour management in the path).

Blender's own image writer goes through colour-space conversion; the UV/
lighting data plates must keep their bytes exactly, so they are encoded here
with numpy + zlib. Rows are written top-down.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, rgb: np.ndarray) -> Path:
    """rgb: uint8 array (H, W, 3) or (H, W, 4), row 0 = top."""
    arr = np.ascontiguousarray(rgb, dtype=np.uint8)
    h, w, c = arr.shape
    color_type = {3: 2, 4: 6}[c]
    # Sub filter on every row: data plates are mostly smooth ramps, so the
    # horizontal difference compresses far better than raw bytes.
    flat = arr.reshape(h, w * c).astype(np.int16)
    filt = flat.copy()
    filt[:, c:] = (flat[:, c:] - flat[:, :-c]) & 0xFF
    raw = np.empty((h, w * c + 1), dtype=np.uint8)
    raw[:, 0] = 1  # filter type: Sub
    raw[:, 1:] = filt.astype(np.uint8)
    png = b"\x89PNG\r\n\x1a\n"
    png += _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
    png += _chunk(b"IDAT", zlib.compress(raw.tobytes(), 9))
    png += _chunk(b"IEND", b"")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    return path


def read_blender_image(path, *, channels: int = 4) -> np.ndarray:
    """Load any image Blender can read as raw float32 (H, W, C), row 0 = top,
    bypassing colour management (Non-Color)."""
    import bpy
    img = bpy.data.images.load(str(path), check_existing=False)
    try:
        img.colorspace_settings.name = "Non-Color"
        w, h = img.size
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
    finally:
        bpy.data.images.remove(img)
    arr = buf.reshape(h, w, 4)[::-1]  # Blender stores bottom-up
    return arr[:, :, :channels].copy()
