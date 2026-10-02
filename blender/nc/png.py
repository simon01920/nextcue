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


def _filtered_rows(flat: np.ndarray, c: int) -> np.ndarray:
    """All five PNG filters for every row at once: (5, H, W*C) uint8, in
    filter-type order None, Sub, Up, Average, Paeth."""
    x = flat.astype(np.int16)
    a = np.zeros_like(x)
    a[:, c:] = x[:, :-c]                       # left
    b = np.zeros_like(x)
    b[1:] = x[:-1]                             # up
    cc = np.zeros_like(x)
    cc[1:, c:] = x[:-1, :-c]                   # up-left
    p = a + b - cc
    pa, pb, pc = np.abs(p - a), np.abs(p - b), np.abs(p - cc)
    paeth = np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, cc))
    out = np.stack([x, x - a, x - b, x - ((a + b) >> 1), x - paeth]) & 0xFF
    return out.astype(np.uint8)


def write_png(path, rgb: np.ndarray) -> Path:
    """rgb: uint8 array (H, W, 3) or (H, W, 4), row 0 = top."""
    arr = np.ascontiguousarray(rgb, dtype=np.uint8)
    h, w, c = arr.shape
    color_type = {3: 2, 4: 6}[c]
    # Per-row adaptive filter (the usual minimum-sum-of-absolute-differences
    # heuristic): data plates are smooth ramps, which Sub/Up/Paeth turn into
    # near-constant bytes that deflate well.
    flat = arr.reshape(h, w * c)
    cand = _filtered_rows(flat, c)
    score = np.abs(cand.astype(np.int8).astype(np.int32)).sum(axis=2)    # (5, H)
    best = score.argmin(axis=0)
    raw = np.empty((h, w * c + 1), dtype=np.uint8)
    raw[:, 0] = best
    raw[:, 1:] = cand[best, np.arange(h)]
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
