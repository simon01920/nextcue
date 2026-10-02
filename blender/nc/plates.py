"""App plates: the images the Flutter compositor samples.

Per plate (see docs/AUDIT.md §5):

  <name>_color.webp  RGBA beauty; label surfaces are black ink under their
                     coat, so the plate carries only their gloss.
  <name>_uv.png      R = U high byte, G = V high byte, B = D (label light,
                     anti-aliased, premultiplied by coverage)
  <name>_uv2.png     R = U low byte,  G = V low byte,  B = 0

U/V are 16-bit image-space atlas coordinates (origin top-left). The shader
computes  out = C + T(uv) * D * tint  — exact on anti-aliased edges because
coverage is already folded into D.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

from . import mats
from .png import read_blender_image, write_png
from .paths import CACHE


@dataclass
class PlateSpec:
    name: str
    uvset: int = 0                    # 0 hero atlas, 1 shelf (spine) atlas
    labels: bool = True               # produce uv/uv2 data images
    samples: int = 256
    transparent: bool = True
    crop: bool = True
    margin_px: int = 6
    crop_px: tuple | None = None      # fixed (x, y, w, h) in frame pixels, no scout
    clamp_px: tuple | None = None     # scout box is intersected with this (x0, y0, x1, y1)
    scout_threshold: float = 0.01
    color_format: str = "WEBP"        # WEBP | JPEG | PNG
    quality: int = 90
    anchor_world: Vector | None = None
    meta: dict = field(default_factory=dict)


def _log(msg: str) -> None:
    print(f"[nc plates {time.strftime('%H:%M:%S')}] {msg}", flush=True)


class _Settings:
    """Snapshot/restore of the render settings each pass changes."""

    def __init__(self, sc):
        self.sc = sc
        c, r, v = sc.cycles, sc.render, sc.view_settings
        self.saved = dict(
            samples=c.samples, denoise=c.use_denoising, filter=c.filter_width,
            adaptive=c.use_adaptive_sampling,
            bounces=(c.max_bounces, c.diffuse_bounces, c.glossy_bounces, c.transmission_bounces,
                     c.volume_bounces),
            transparent=r.film_transparent, view=v.view_transform, look=v.look, exposure=v.exposure,
            border=(r.use_border, r.use_crop_to_border, r.border_min_x, r.border_max_x,
                    r.border_min_y, r.border_max_y),
        )

    def restore(self):
        c, r, v = self.sc.cycles, self.sc.render, self.sc.view_settings
        s = self.saved
        c.samples, c.use_denoising, c.filter_width = s["samples"], s["denoise"], s["filter"]
        c.use_adaptive_sampling = s["adaptive"]
        (c.max_bounces, c.diffuse_bounces, c.glossy_bounces, c.transmission_bounces,
         c.volume_bounces) = s["bounces"]
        r.film_transparent = s["transparent"]
        v.view_transform, v.look, v.exposure = s["view"], s["look"], s["exposure"]
        (r.use_border, r.use_crop_to_border, r.border_min_x, r.border_max_x,
         r.border_min_y, r.border_max_y) = s["border"]


def _render(path: Path, fmt: str, *, depth: str = "8", mode: str = "RGBA", quality: int = 90) -> Path:
    sc = bpy.context.scene
    s = sc.render.image_settings
    s.file_format = fmt
    s.color_mode = mode
    if fmt in ("PNG", "OPEN_EXR"):
        s.color_depth = depth
    if fmt == "OPEN_EXR":
        s.exr_codec = "ZIP"
    if fmt in ("WEBP", "JPEG"):
        s.quality = quality
    path.parent.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def _bbox_from_alpha(alpha: np.ndarray, margin: int, threshold: float = 0.01):
    ys, xs = np.nonzero(alpha > threshold)
    h, w = alpha.shape
    if len(xs) == 0:
        return 0, 0, w, h
    x0 = max(0, int(xs.min()) - margin)
    x1 = min(w, int(xs.max()) + 1 + margin)
    y0 = max(0, int(ys.min()) - margin)
    y1 = min(h, int(ys.max()) + 1 + margin)
    return x0, y0, x1, y1


def _dilate(u, v, valid, iterations: int = 4):
    """Grow valid UVs outward so bilinear filtering at label edges never
    mixes in the zeros of non-label pixels."""
    u, v, valid = u.copy(), v.copy(), valid.copy()
    h, w = valid.shape
    for _ in range(iterations):
        acc_u = np.zeros_like(u)
        acc_v = np.zeros_like(v)
        cnt = np.zeros_like(u)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                sv = np.zeros_like(valid)
                su = np.zeros_like(u)
                svv = np.zeros_like(v)
                ys0, ys1 = max(0, dy), h + min(0, dy)
                xs0, xs1 = max(0, dx), w + min(0, dx)
                sv[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx] = valid[ys0:ys1, xs0:xs1]
                su[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx] = u[ys0:ys1, xs0:xs1]
                svv[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx] = v[ys0:ys1, xs0:xs1]
                acc_u += su * sv
                acc_v += svv * sv
                cnt += sv
        grow = (~valid) & (cnt > 0)
        u[grow] = acc_u[grow] / cnt[grow]
        v[grow] = acc_v[grow] / cnt[grow]
        valid = valid | grow
    return u, v


def _image_size(path: Path) -> tuple[int, int]:
    img = bpy.data.images.load(str(path), check_existing=False)
    try:
        return tuple(img.size)
    finally:
        bpy.data.images.remove(img)


def update_manifest(group: str, entries: list[dict], extra: dict | None = None) -> Path:
    """Merge one group's plates into assets/plates/manifest.json. File names
    become paths relative to assets/plates/ (the app's asset root)."""
    import json
    from .paths import PLATE_DIR
    path = PLATE_DIR / "manifest.json"
    data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"version": 1}
    data.setdefault("plates", {})
    for key in [k for k in data["plates"] if k.startswith(group + "/")]:
        del data["plates"][key]
    for e in entries:
        e = dict(e)
        for k in ("color", "uv", "uv2"):
            if k in e:
                e[k] = f"{group}/{e[k]}"
        data["plates"][f"{group}/{e['name']}"] = e
    if extra:
        data[group] = extra
    path.write_text(json.dumps(data, indent=1, sort_keys=False) + "\n", encoding="utf-8")
    return path


def _hi_lo(x: np.ndarray):
    q = np.clip(np.rint(x * 65535.0), 0, 65535).astype(np.uint32)
    return (q >> 8).astype(np.uint8), (q & 0xFF).astype(np.uint8)


def render_plate(spec: PlateSpec, out_dir: Path, *, view: str = "AgX",
                 look: str = "AgX - Medium High Contrast") -> dict:
    sc = bpy.context.scene
    settings = _Settings(sc)
    W, H = sc.render.resolution_x, sc.render.resolution_y
    cache = CACHE / "plates"
    cache.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    try:
        r, c = sc.render, sc.cycles
        r.film_transparent = spec.transparent
        r.use_border = False
        r.use_crop_to_border = False
        sc.view_settings.view_transform = view
        try:
            sc.view_settings.look = look
        except TypeError:
            sc.view_settings.look = "None"

        # 1. crop box: fixed, or scouted from a cheap beauty render (its
        #    alpha includes shadow-catcher shadows)
        x0, y0, x1, y1 = 0, 0, W, H
        if spec.crop_px is not None:
            cx, cy, cw, ch = spec.crop_px
            x0, y0, x1, y1 = cx, cy, cx + cw, cy + ch
        elif spec.crop and spec.transparent:
            mats.set_mode(mats.MODE_BEAUTY)
            c.samples, c.use_denoising, c.use_adaptive_sampling = 16, False, False
            scout = _render(cache / f"{spec.name}_scout.png", "PNG")
            alpha = read_blender_image(scout)[:, :, 3]
            x0, y0, x1, y1 = _bbox_from_alpha(alpha, spec.margin_px, spec.scout_threshold)
            if spec.clamp_px is not None:
                a0, b0, a1, b1 = spec.clamp_px
                x0, y0, x1, y1 = max(x0, a0), max(y0, b0), min(x1, a1), min(y1, b1)
        if (x0, y0, x1, y1) != (0, 0, W, H):
            r.use_border = True
            r.use_crop_to_border = True
            r.border_min_x, r.border_max_x = x0 / W, x1 / W
            r.border_min_y, r.border_max_y = 1.0 - y1 / H, 1.0 - y0 / H

        entry = {"name": spec.name, "frame": [W, H], "crop": [x0, y0, x1 - x0, y1 - y0]}

        if spec.labels:
            # 2. UV pass: unfiltered, one sample, raw float
            mats.set_mode(mats.MODE_UV, spec.uvset)
            c.samples, c.use_denoising, c.use_adaptive_sampling = 1, False, False
            saved_filter = c.filter_width
            c.filter_width = 0.01
            bounces = (c.max_bounces, c.diffuse_bounces, c.glossy_bounces, c.transmission_bounces)
            c.max_bounces = c.diffuse_bounces = c.glossy_bounces = c.transmission_bounces = 0
            sc.view_settings.view_transform = "Standard"
            sc.view_settings.look = "None"
            uv_exr = _render(cache / f"{spec.name}_uv.exr", "OPEN_EXR", depth="32")
            c.filter_width = saved_filter
            c.max_bounces, c.diffuse_bounces, c.glossy_bounces, c.transmission_bounces = bounces
            sc.view_settings.view_transform = view
            try:
                sc.view_settings.look = look
            except TypeError:
                sc.view_settings.look = "None"

            # 3. label light D
            mats.set_mode(mats.MODE_LABEL_LIGHT, spec.uvset)
            c.samples, c.use_denoising, c.use_adaptive_sampling = spec.samples, True, True
            r.film_transparent = True
            d_png = _render(cache / f"{spec.name}_d.png", "PNG", depth="16")
            r.film_transparent = spec.transparent

        # 4. beauty
        mats.set_mode(mats.MODE_BEAUTY)
        c.samples, c.use_denoising, c.use_adaptive_sampling = spec.samples, True, True
        ext = {"WEBP": "webp", "JPEG": "jpg", "PNG": "png"}[spec.color_format]
        mode = "RGBA" if spec.transparent and spec.color_format != "JPEG" else "RGB"
        color_path = out_dir / f"{spec.name}_color.{ext}"
        _render(color_path, spec.color_format, mode=mode, quality=spec.quality)
        entry["color"] = color_path.name

        if spec.labels:
            # 5. pack
            uvf = read_blender_image(uv_exr)
            u, v, mask = uvf[:, :, 0], uvf[:, :, 1], uvf[:, :, 2]
            d = read_blender_image(d_png)
            gray = d[:, :, :3].mean(axis=2)
            alpha = d[:, :, 3]
            d_pm = np.clip(gray * alpha, 0.0, 1.0)
            valid = mask > 0.5
            label_px = valid & (alpha > 0.9)
            if label_px.any():
                rgb_mean = d[:, :, :3][label_px].mean(axis=0)
                tint = (rgb_mean / max(1e-6, rgb_mean.mean())).tolist()
            else:
                tint = [1.0, 1.0, 1.0]
            u_img = u
            v_img = 1.0 - v               # Blender UV (v up) -> image space (v down)
            u_img = np.where(valid, u_img, 0.0)
            v_img = np.where(valid, v_img, 0.0)
            u_d, v_d = _dilate(u_img, v_img, valid)
            uh, ul = _hi_lo(u_d)
            vh, vl = _hi_lo(v_d)
            d8 = np.clip(np.rint(d_pm * 255.0), 0, 255).astype(np.uint8)
            uv_path = write_png(out_dir / f"{spec.name}_uv.png", np.dstack([uh, vh, d8]))
            uv2_path = write_png(out_dir / f"{spec.name}_uv2.png",
                                 np.dstack([ul, vl, np.zeros_like(ul)]))
            entry.update(uv=uv_path.name, uv2=uv2_path.name, tint=[round(t, 4) for t in tint],
                         uvset=["hero", "spine"][spec.uvset])

        actual = _image_size(color_path)
        if actual != (x1 - x0, y1 - y0):
            _log(f"WARNING {spec.name}: border crop rendered {actual}, expected {(x1 - x0, y1 - y0)}")
        entry["size"] = list(actual)
        if spec.anchor_world is not None:
            p = world_to_camera_view(sc, sc.camera, Vector(spec.anchor_world))
            ax = p.x * W - x0
            ay = (1.0 - p.y) * H - y0
            entry["anchor"] = [round(ax, 2), round(ay, 2)]
        entry.update(spec.meta)
        _log(f"{spec.name}: {entry['size'][0]}x{entry['size'][1]} in {time.time() - t0:.1f}s")
        return entry
    finally:
        settings.restore()
