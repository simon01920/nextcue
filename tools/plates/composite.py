"""Reference compositor for NextCue plates: the exact maths of
shaders/plate.frag in numpy, used to QA plates before (and independently
of) the app.

    python tools/plates/composite.py shelf  [--rows 2] [--out FILE]
    python tools/plates/composite.py plate shelf/tape_a [--out FILE]

Per pixel:  premultiplied out = C + T(uv) * D * tint,  alpha = C.a
where uv = (hi*256 + lo) / 65535 from the two data images.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
PLATES = ROOT / "assets" / "plates"
FONTS = ROOT / "assets" / "fonts"


def manifest() -> dict:
    return json.loads((PLATES / "manifest.json").read_text(encoding="utf-8"))


def _rgba_premul(path: Path) -> np.ndarray:
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def _bilinear(tex: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    h, w = tex.shape[:2]
    x = np.clip(u * w - 0.5, 0, w - 1)
    y = np.clip(v * h - 0.5, 0, h - 1)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    x1 = np.minimum(x0 + 1, w - 1)
    y1 = np.minimum(y0 + 1, h - 1)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    top = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    bot = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def render_plate(entry: dict, art: np.ndarray | None) -> np.ndarray:
    """Premultiplied RGBA float image of one plate with `art` (H, W, 3
    float, the atlas) applied."""
    c = _rgba_premul(PLATES / entry["color"])
    if "uv" not in entry or art is None:
        return c
    hi = np.asarray(Image.open(PLATES / entry["uv"]).convert("RGB"), dtype=np.uint32)
    lo = np.asarray(Image.open(PLATES / entry["uv2"]).convert("RGB"), dtype=np.uint32)
    u = (hi[..., 0] * 256 + lo[..., 0]) / 65535.0
    v = (hi[..., 1] * 256 + lo[..., 1]) / 65535.0
    d = hi[..., 2] / 255.0
    t = _bilinear(art, u, v)
    tint = np.array(entry.get("tint", [1, 1, 1]), dtype=np.float32)
    out = c.copy()
    out[..., :3] += t * d[..., None] * tint
    return out


def over(dst: np.ndarray, src: np.ndarray, x: int, y: int, clip=None) -> None:
    """Premultiplied source-over of src onto dst at (x, y), optional clip
    rect (x0, y0, x1, y1) in dst pixels."""
    h, w = src.shape[:2]
    X0, Y0, X1, Y1 = clip or (0, 0, dst.shape[1], dst.shape[0])
    dx0, dy0 = max(x, X0), max(y, Y0)
    dx1, dy1 = min(x + w, X1), min(y + h, Y1)
    if dx0 >= dx1 or dy0 >= dy1:
        return
    s = src[dy0 - y:dy1 - y, dx0 - x:dx1 - x]
    d = dst[dy0:dy1, dx0:dx1]
    d[...] = s + d * (1 - s[..., 3:4])


# ---------------------------------------------------------------------------
# Test artwork (stands in for the app's label composer)
# ---------------------------------------------------------------------------

TITLES = ["THE EXPANSE", "Dark", "Hra o tróny", "SEVERANCE", "Fargo", "Twin Peaks", "Chernobyl",
          "Kto chce byť milionárom?", "Slnko v sieti", "Breaking Bad", "Mr. Robot", "Arcane",
          "Stranger Things", "Andor", "Shōgun", "Better Call Saul", "Ted Lasso", "Mindhunter",
          "Pán prsteňov: Prstene moci", "The Bear", "Westworld", "Barry", "Succession", "Fleabag"]
PALETTE = [(0.85, 0.12, 0.10), (0.08, 0.10, 0.12), (0.93, 0.89, 0.80), (0.10, 0.30, 0.55),
           (0.95, 0.70, 0.10), (0.15, 0.45, 0.28), (0.45, 0.10, 0.35), (0.92, 0.45, 0.15),
           (0.20, 0.20, 0.22), (0.70, 0.75, 0.80)]


def spine_art(title: str, seed: int, px_per_mm: float = 4.0) -> np.ndarray:
    m = manifest()["atlas"]["spine"]
    cw, ch = m["canvas_mm"]
    W, H = int(round(cw * px_per_mm)), int(round(ch * px_per_mm))
    rnd = random.Random(seed)
    bg = rnd.choice(PALETTE)
    fg = (0.96, 0.95, 0.92) if sum(bg) < 1.6 else (0.06, 0.06, 0.07)
    accent = rnd.choice([p for p in PALETTE if p != bg])
    im = Image.new("RGB", (W, H), tuple(int(c * 255) for c in bg))
    dr = ImageDraw.Draw(im)
    sw = int(m["regions"]["spine"]["w"] * W)
    # top band + logo block, bottom band
    dr.rectangle([0, 0, sw, int(H * 0.09)], fill=tuple(int(c * 255) for c in accent))
    dr.rectangle([0, int(H * 0.93), sw, H], fill=tuple(int(c * 255) for c in accent))
    font = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), int(sw * 0.52))
    # title reads top-to-bottom: draw horizontally then rotate -90
    tw = int(H * 0.78)
    txt = Image.new("RGBA", (tw, sw), (0, 0, 0, 0))
    td = ImageDraw.Draw(txt)
    size = int(sw * 0.52)
    while size > 8:
        font = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), size)
        if td.textlength(title.upper(), font=font) <= tw * 0.95:
            break
        size -= 1
    td.text((tw / 2, sw / 2), title.upper(), font=font, fill=tuple(int(c * 255) for c in fg) + (255,),
            anchor="mm")
    im.paste(txt.rotate(-90, expand=True), (0, int(H * 0.11)), txt.rotate(-90, expand=True))
    # front strip: a slice of 'poster'
    fx = sw
    for y in range(H):
        t = y / H
        col = tuple(int(255 * (accent[i] * (1 - t) + bg[i] * t * 0.6)) for i in range(3))
        dr.line([(fx, y), (W, y)], fill=col)
    return np.asarray(im, dtype=np.float32) / 255.0


def hero_art(title: str, seed: int, px_per_mm: float = 6.0) -> np.ndarray:
    """Hero atlas: back | spine | front, plus the two cassette stickers."""
    m = manifest()["atlas"]["hero"]
    cw, ch = m["canvas_mm"]
    W, H = int(cw * px_per_mm), int(ch * px_per_mm)
    rnd = random.Random(seed)
    a, b = rnd.sample(PALETTE, 2)
    im = Image.new("RGB", (W, H), (230, 226, 216))
    dr = ImageDraw.Draw(im)

    def rect(name):
        r = m["regions"][name]
        return (int(r["x"] * W), int(r["y"] * H), int((r["x"] + r["w"]) * W), int((r["y"] + r["h"]) * H))

    # poster: vertical gradient a -> b with a big circle 'sun' and stripes
    x0, y0, x1, y1 = rect("back")[0], 0, rect("front")[2], rect("front")[3]
    for y in range(y0, y1):
        t = (y - y0) / (y1 - y0)
        col = tuple(int(255 * (a[i] * (1 - t) + b[i] * t)) for i in range(3))
        dr.line([(x0, y), (x1, y)], fill=col)
    fx0, fy0, fx1, fy1 = rect("front")
    cx, cy, r = (fx0 + fx1) // 2, fy0 + (fy1 - fy0) * 2 // 5, (fx1 - fx0) // 3
    dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(250, 200, 80))
    for k in range(6):
        yy = cy + r // 3 + k * r // 6
        dr.rectangle([fx0, yy, fx1, yy + r // 14], fill=tuple(int(c * 255 * 0.6) for c in b))
    font = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), int((fx1 - fx0) * 0.16))
    dr.text(((fx0 + fx1) / 2, fy1 - (fy1 - fy0) * 0.16), title.upper(), font=font, fill=(250, 248, 240),
            anchor="mm")
    # spine title (top-to-bottom)
    sx0, sy0, sx1, sy1 = rect("spine")
    sw = sx1 - sx0
    txt = Image.new("RGBA", (int((sy1 - sy0) * 0.8), sw), (0, 0, 0, 0))
    td = ImageDraw.Draw(txt)
    size = int(sw * 0.55)
    while size > 8:
        f = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), size)
        if td.textlength(title.upper(), font=f) <= txt.width * 0.95:
            break
        size -= 1
    td.text((txt.width / 2, sw / 2), title.upper(), font=f, fill=(250, 248, 240, 255), anchor="mm")
    rot = txt.rotate(-90, expand=True)
    im.paste(rot, (sx0, sy0 + int((sy1 - sy0) * 0.1)), rot)
    # back cover blurb blocks
    bx0, by0, bx1, by1 = rect("back")
    for k in range(9):
        yy = by0 + (by1 - by0) * (0.45 + k * 0.04)
        dr.rectangle([bx0 + 40, yy, bx1 - 40 - (k % 3) * 60, yy + 10], fill=(240, 236, 228))
    # cassette stickers: cream paper with title
    for name, scale in (("cassette_face", 0.2), ("cassette_spine", 0.6)):
        x0, y0, x1, y1 = rect(name)
        dr.rectangle([x0, y0, x1, y1], fill=(238, 232, 214))
        dr.rectangle([x0, y0, x1, y0 + (y1 - y0) // 6], fill=tuple(int(c * 255) for c in a))
        f = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), int((y1 - y0) * scale))
        dr.text(((x0 + x1) / 2, (y0 + y1) / 2 + (y1 - y0) // 12), title.upper(), font=f, fill=(30, 28, 26),
                anchor="mm")
    return np.asarray(im, dtype=np.float32) / 255.0


def dvd_art(title: str, seed: int, px_per_mm: float = 6.0) -> np.ndarray:
    """DVD insert atlas (back | spine | front), same poster language."""
    m = manifest()["atlas"]["dvd"]
    cw, ch = m["canvas_mm"]
    W, H = int(cw * px_per_mm), int(ch * px_per_mm)
    rnd = random.Random(seed)
    a, b = rnd.sample(PALETTE, 2)
    im = Image.new("RGB", (W, H))
    dr = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        dr.line([(0, y), (W, y)], fill=tuple(int(255 * (a[i] * (1 - t) + b[i] * t)) for i in range(3)))

    def rect(name):
        r = m["regions"][name]
        return (int(r["x"] * W), int(r["y"] * H), int((r["x"] + r["w"]) * W), int((r["y"] + r["h"]) * H))

    fx0, fy0, fx1, fy1 = rect("front")
    cx, cy = (fx0 + fx1) // 2, fy0 + (fy1 - fy0) * 2 // 5
    for k in range(7, 0, -1):
        r = (fx1 - fx0) * k // 18
        shade = tuple(int(255 * min(1, (a[i] + b[i]) * 0.3 + k * 0.08)) for i in range(3))
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=shade, width=max(2, r // 14))
    f = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), int((fx1 - fx0) * 0.14))
    dr.text((cx, fy1 - (fy1 - fy0) * 0.18), title.upper(), font=f, fill=(250, 248, 240), anchor="mm")
    dr.rectangle([fx0, fy0, fx1, fy0 + int((fy1 - fy0) * 0.05)], fill=(18, 18, 20))
    f2 = ImageFont.truetype(str(FONTS / "Figtree-ExtraBold.ttf"), int((fy1 - fy0) * 0.03))
    dr.text((cx, fy0 + int((fy1 - fy0) * 0.025)), "DVD VIDEO", font=f2, fill=(240, 240, 240), anchor="mm")
    sx0, sy0, sx1, sy1 = rect("spine")
    sw = sx1 - sx0
    txt = Image.new("RGBA", (int((sy1 - sy0) * 0.7), sw), (0, 0, 0, 0))
    td = ImageDraw.Draw(txt)
    size = int(sw * 0.6)
    while size > 6:
        f3 = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), size)
        if td.textlength(title.upper(), font=f3) <= txt.width * 0.95:
            break
        size -= 1
    td.text((txt.width / 2, sw / 2), title.upper(), font=f3, fill=(250, 248, 240, 255), anchor="mm")
    rot = txt.rotate(-90, expand=True)
    im.paste(rot, (sx0, sy0 + int((sy1 - sy0) * 0.15)), rot)
    return np.asarray(im, dtype=np.float32) / 255.0


def tag_art(text: str, w_mm: float = 352.0, h_mm: float = 19.0, px_per_mm: float = 4.0) -> np.ndarray:
    W, H = int(w_mm * px_per_mm), int(h_mm * px_per_mm)
    im = Image.new("RGB", (W, H), (236, 230, 214))
    dr = ImageDraw.Draw(im)
    font = ImageFont.truetype(str(FONTS / "Figtree-ExtraBold.ttf"), int(H * 0.46))
    dr.text((int(H * 0.5), H / 2), text, font=font, fill=(30, 28, 26), anchor="lm")
    dr.rectangle([0, H - 3, W, H], fill=(200, 60, 40))
    return np.asarray(im, dtype=np.float32) / 255.0


# ---------------------------------------------------------------------------
# Shelf layout (mirrors lib/shelf/shelf_layout.dart)
# ---------------------------------------------------------------------------

def compose_bay(m: dict, bay_index: int, tapes: list[dict], tag: str) -> np.ndarray:
    """tapes: [{'title', 'seed', 'state': upright|sealed|pulled}] (<= slots)."""
    L = m["groups"]["shelf"]
    P = m["plates"]
    W, H = L["bay_px"]
    slot_px, slot0 = L["slot_px"], L["slot0_left_px"]
    inner = (L["inner_px"][0], 0, L["inner_px"][1], H)
    canvas = np.zeros((H, W, 4), np.float32)
    over(canvas, render_plate(P[f"shelf/{L['bays'][bay_index % len(L['bays'])]}"], None), 0, 0)

    def place(name: str, slot: int, art=None, clip=inner):
        e = P[f"shelf/{name}"]
        x = e["crop"][0] + (slot - e["slot"]) * slot_px
        over(canvas, render_plate(e, art), x, e["crop"][1], clip)

    k = len(tapes)
    lean = 2 <= k <= L["lean_max_tapes"]
    uprights = tapes[:-1] if lean else tapes
    if k and not lean and k < L["slots"]:
        place("tape_end_shadow", k - 1)
    pulled = []
    for i, t in enumerate(uprights):
        art = spine_art(t["title"], t["seed"])
        if t["state"] == "pulled":
            pulled.append((i, art))      # drawn after its neighbours
            continue
        name = "tape_sealed" if t["state"] == "sealed" else L["packed"][t["seed"] % len(L["packed"])]
        place(name, i, art)
    for i, art in pulled:
        place("tape_pulled_shadow", i)
        place("tape_pulled", i, art)
    if lean:
        t = tapes[-1]
        place("tape_lean", len(uprights), spine_art(t["title"], t["seed"]))
    rail = P["shelf/rail"]
    over(canvas, render_plate(rail, tag_art(tag)), rail["crop"][0], rail["crop"][1])
    return canvas


def to_image(canvas: np.ndarray, bg=(0.02, 0.02, 0.022)) -> Image.Image:
    rgb = canvas[..., :3] + np.array(bg, np.float32) * (1 - canvas[..., 3:4])
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["shelf", "plate", "hero", "samples"])
    ap.add_argument("name", nargs="?")
    ap.add_argument("--rows", type=int, default=2)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    m = manifest()
    if a.what == "samples":
        # The two generated showcase images used by blender/build.py beauty
        # renders (see README "Generated images").
        cache = ROOT / "blender" / "_cache"
        cache.mkdir(parents=True, exist_ok=True)
        hero = hero_art("Slnko v sieti", 11, px_per_mm=8.0)
        Image.fromarray((hero * 255 + 0.5).astype(np.uint8)).save(cache / "sample_hero.png")
        cells = [spine_art(TITLES[i], 100 + i * 7) for i in range(16)]
        ch, cw = cells[0].shape[:2]
        grid = np.zeros((ch * 4, cw * 4, 3), np.float32)
        for i, c in enumerate(cells):
            col, row_from_bottom = i % 4, i // 4      # Blender UVs are v-up
            r = 3 - row_from_bottom
            grid[r * ch:(r + 1) * ch, col * cw:(col + 1) * cw] = c
        Image.fromarray((grid * 255 + 0.5).astype(np.uint8)).save(cache / "sample_spines.png")
        dvd = dvd_art("Hra o tróny", 21)
        Image.fromarray((dvd * 255 + 0.5).astype(np.uint8)).save(cache / "sample_dvd.png")
        print(cache / "sample_hero.png", cache / "sample_spines.png", cache / "sample_dvd.png")
        return
    if a.what == "hero":
        art = hero_art("Slnko v sieti", 11)
        P = m["plates"]
        frames = [P[k] for k in sorted(P) if k.startswith("hero/rot_")]
        cas = [P[k] for k in sorted(P) if k.startswith("hero/cassette_")]
        tw, th = m["groups"]["hero"]["size"]
        cols = 6
        rows = (len(frames) + cols - 1) // cols
        sheet = np.zeros((rows * th + th, cols * tw, 4), np.float32)
        for i, e in enumerate(frames):
            over(sheet, render_plate(e, art), (i % cols) * tw, (i // cols) * th)
        for i, e in enumerate(cas):
            c = render_plate(e, art)
            ci = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8), "RGBA")
            ci = ci.resize((tw * cols // len(cas), int(c.shape[0] * tw * cols / len(cas) / c.shape[1])))
            over(sheet, np.asarray(ci, np.float32) / 255.0, i * (tw * cols // len(cas)), rows * th + 40)
        img = to_image(sheet, bg=(0.93, 0.93, 0.94))
        out = Path(a.out or ROOT / "renders" / "_preview" / "composite_hero.png")
        hi = P.get("hero/front_hi")
        if hi:
            to_image(render_plate(hi, art), bg=(0.08, 0.08, 0.09)).save(out.with_name("composite_hero_front.png"))
    elif a.what == "plate":
        e = m["plates"][a.name]
        art = {"spine": spine_art("Hra o tróny", 3), "hero": hero_art("Hra o tróny", 3),
               "tag": tag_art("DRAMA · 12")}.get(e.get("atlas"))
        img = to_image(render_plate(e, art))
        out = Path(a.out or ROOT / "renders" / "_preview" / f"plate_{a.name.replace('/', '_')}.png")
    else:
        L = m["groups"]["shelf"]
        rows = []
        rnd = random.Random(7)
        titles = list(TITLES)
        for r in range(a.rows):
            count = L["slots"] if r == 0 else 9
            tapes = []
            for i in range(count):
                state = "upright"
                if (r, i) in ((0, 3),):
                    state = "pulled"
                elif (r, i) in ((0, 8), (1, 1)):
                    state = "sealed"
                tapes.append({"title": titles[(r * 12 + i) % len(titles)], "seed": rnd.randrange(1000),
                              "state": state})
            rows.append(compose_bay(m, r, tapes, ["DRAMA · 12", "SCI-FI · 9"][r % 2]))
        # stack: row 0 on top
        canvas = np.concatenate(rows, axis=0)
        img = to_image(canvas)
        out = Path(a.out or ROOT / "renders" / "_preview" / "composite_shelf.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
