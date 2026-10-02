"""Encode turntable frames from renders/_frames into animated WebPs and a
contact sheet per asset.

    python tools/plates/turntable.py            # all assets found
"""

from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FRAMES = ROOT / "renders" / "_frames"
OUT = ROOT / "renders"


def main() -> None:
    groups: dict[str, list[Path]] = defaultdict(list)
    for p in sorted(FRAMES.glob("*_tt_*.png")):
        m = re.match(r"(.+)_tt_(\d+)\.png$", p.name)
        if m:
            groups[m.group(1)].append(p)
    for name, paths in groups.items():
        frames = [Image.open(p).convert("RGB") for p in paths]
        anim = OUT / f"{name}_turntable.webp"
        frames[0].save(anim, save_all=True, append_images=frames[1:], duration=1000 // 12, loop=0,
                       quality=82, method=6)
        cols = 6
        w, h = frames[0].size
        tw, th = w // 2, h // 2
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * th), (12, 12, 13))
        for i, f in enumerate(frames):
            sheet.paste(f.resize((tw, th), Image.LANCZOS), ((i % cols) * tw, (i // cols) * th))
        sheet.save(OUT / f"{name}_turntable_sheet.jpg", quality=88)
        print(f"{anim.name}: {len(frames)} frames, {anim.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
