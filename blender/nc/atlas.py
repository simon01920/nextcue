"""Label atlas layouts — the contract between Blender UVs and the Flutter
label composer.

Coordinates are millimetres in *image space* (origin top-left, y down) on a
square canvas. ``Region.uv`` converts a local (u, v) in [0, 1]² with v up
(Blender convention) to an atlas UV with v up. The layouts are exported to
``assets/plates/manifest.json`` so Flutter paints artwork into exactly the
rectangles the plates sample.
"""

from __future__ import annotations

from dataclasses import dataclass

# Sleeve outer dimensions (mm), portrait: width x height x depth.
SLEEVE_W, SLEEVE_H, SLEEVE_D = 107.0, 190.5, 28.0


@dataclass(frozen=True)
class Region:
    x: float
    y: float
    w: float
    h: float
    canvas_w: float
    canvas_h: float

    def uv(self, u: float, v: float) -> tuple[float, float]:
        px = self.x + u * self.w
        py = self.y + (1.0 - v) * self.h
        return px / self.canvas_w, 1.0 - py / self.canvas_h

    def as_json(self) -> dict:
        cw, ch = self.canvas_w, self.canvas_h
        return {"x": self.x / cw, "y": self.y / ch, "w": self.w / cw, "h": self.h / ch,
                "mm": [self.w, self.h]}


def _layout(canvas_w: float, canvas_h: float, regions: dict) -> dict[str, Region]:
    return {k: Region(*r, canvas_w, canvas_h) for k, r in regions.items()}


# Full artwork atlas used by the hero / rotation / eject plates. The sleeve
# unfolds back | spine | front like a dust jacket, so art can run across the
# fold; the cassette stickers sit underneath.
HERO_CANVAS = (256.0, 256.0)
HERO = _layout(*HERO_CANVAS, {
    "back": (0.0, 0.0, SLEEVE_W, SLEEVE_H),
    "spine": (SLEEVE_W, 0.0, SLEEVE_D, SLEEVE_H),
    "front": (SLEEVE_W + SLEEVE_D, 0.0, SLEEVE_W, SLEEVE_H),
    "cassette_face": (0.0, 197.0, 79.0, 43.0),
    "cassette_spine": (86.0, 197.0, 147.0, 19.0),
})

# Shelf atlas (one small texture per tape): the spine plus the strip of the
# front cover next to the fold, which shows on pulled-out and end-of-row
# tapes because the shelf camera sits slightly to the right.
FRONT_STRIP = 20.0
SPINE_CANVAS = (SLEEVE_D + FRONT_STRIP, SLEEVE_H)
SPINE = _layout(*SPINE_CANVAS, {
    "spine": (0.0, 0.0, SLEEVE_D, SLEEVE_H),
    "front_strip": (SLEEVE_D, 0.0, FRONT_STRIP, SLEEVE_H),
})


def manifest_json() -> dict:
    return {
        "hero": {"canvas_mm": list(HERO_CANVAS), "regions": {k: r.as_json() for k, r in HERO.items()}},
        "spine": {"canvas_mm": list(SPINE_CANVAS), "regions": {k: r.as_json() for k, r in SPINE.items()}},
        "sleeve_mm": [SLEEVE_W, SLEEVE_H, SLEEVE_D],
    }
