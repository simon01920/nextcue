"""Single entry point for the NextCue 3D pipeline.

    blender --background --factory-startup --python blender/build.py -- [options]

See blender/README.md (and the repo README) for the full command, options and
what each asset script produces.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import bpy  # noqa: E402

from nc import MM, paths  # noqa: E402
from nc import mats, rig, scene  # noqa: E402


def log(msg: str) -> None:
    print(f"[nc {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def check_version() -> None:
    v = bpy.app.version
    if tuple(v) != paths.TARGET_BLENDER:
        log(f"Blender {bpy.app.version_string} (pipeline targets "
            f"{'.'.join(map(str, paths.TARGET_BLENDER))}; scripts adapt, see README)")
    else:
        log(f"Blender {bpy.app.version_string}")


# --------------------------------------------------------------------------
# Look-dev previews
# --------------------------------------------------------------------------

_SAMPLE_PATH = None


def _load_sample(args) -> None:
    """Remember the showcase artwork; it's (re)loaded after each scene reset
    because reset() starts from an empty file."""
    global _SAMPLE_PATH
    _SAMPLE_PATH = args.sample_art


def _apply_sample() -> None:
    if _SAMPLE_PATH:
        mats.load_sample_image(_SAMPLE_PATH)


def clay_override() -> None:
    mat = mats.matte("NC_Clay", (0.55, 0.55, 0.55, 1.0), roughness=0.6)
    bpy.context.view_layer.material_override = mat


def preview_cassette(args) -> None:
    from assets import cassette
    sc = scene.reset()
    _apply_sample()
    w, h = (960, 640) if args.quick else (1600, 1066)
    scene.setup_cycles(sc, width=w, height=h, samples=96 if args.quick else 384, transparent=False)
    rig.world_gradient()
    cassette.build(progress=0.35)
    rig.studio(target=(0, 0, 0.0125), radius=0.55)
    backdrop = rig.cyclorama(size=1.6)
    mats.set_mode(mats.MODE_SHOWCASE)
    if args.clay:
        clay_override()
    out = paths.RENDERS / "_preview"
    tag = "_clay" if args.clay else ""
    target = (0, 0, 0.0125)
    shots = {
        "hero": (34.0, 28.0, 0.62, 50.0, target),
        "spine": (8.0, 9.0, 0.55, 60.0, target),
        "door": (205.0, 24.0, 0.6, 50.0, target),
        "bottom": (25.0, -38.0, 0.62, 50.0, target),
        "corner": (-38.0, 16.0, 0.16, 50.0, (-0.090, -0.050, 0.0125)),
    }
    for name, (yaw, pitch, dist, lens, tgt) in shots.items():
        cam = scene.camera(f"Cam_{name}", scene.orbit_location(tgt, dist, yaw, pitch), tgt, lens=lens)
        sc.camera = cam
        backdrop.hide_render = pitch < 0  # looking from below the floor
        t0 = time.time()
        scene.render_still(out / f"cassette_{name}{tag}.png", color_mode="RGB")
        log(f"rendered cassette_{name}{tag} in {time.time() - t0:.1f}s")


def preview_sleeve(args) -> None:
    from assets import sleeve
    sc = scene.reset()
    _apply_sample()
    w, h = (800, 1000) if args.quick else (1400, 1750)
    scene.setup_cycles(sc, width=w, height=h, samples=96 if args.quick else 384, transparent=False)
    rig.world_gradient()
    root = sleeve.build(progress=0.35)
    root.location = (0, 0, sleeve.HH * MM)
    rig.studio(target=(0, 0, sleeve.HH * MM), radius=0.8)
    backdrop = rig.cyclorama(size=2.2)
    mats.set_mode(mats.MODE_SHOWCASE)
    if args.clay:
        clay_override()
    sleeve_obj = next(o for o in bpy.data.objects if o.name == "VHS_Sleeve")
    dg = bpy.context.evaluated_depsgraph_get()
    ev = sleeve_obj.evaluated_get(dg).to_mesh()
    ys = [v.co.y for v in ev.vertices]
    log(f"sleeve mesh: {len(ev.polygons)} faces, y range {min(ys):.2f}..{max(ys):.2f} mm")
    out = paths.RENDERS / "_preview"
    tag = "_clay" if args.clay else ""
    t = (0, 0, sleeve.HH * MM)
    shots = {
        "front34": (-28.0, 12.0, 0.75, 55.0, t),
        "open34": (62.0, 14.0, 0.75, 55.0, t),
        "spine": (-90.0, 6.0, 0.7, 55.0, t),
        "top": (-20.0, 55.0, 0.7, 55.0, t),
    }
    for name, (yaw, pitch, dist, lens, tgt) in shots.items():
        sc.camera = scene.camera(f"Cam_{name}", scene.orbit_location(tgt, dist, yaw, pitch), tgt, lens=lens)
        backdrop.hide_render = pitch < 0
        t0 = time.time()
        scene.render_still(out / f"sleeve_{name}{tag}.png", color_mode="RGB")
        log(f"rendered sleeve_{name}{tag} in {time.time() - t0:.1f}s")


PREVIEWS = {"cassette": preview_cassette, "sleeve": preview_sleeve}


def main() -> None:
    args = paths.parse_args()
    paths.ensure_dirs()
    check_version()
    if args.preview is not None:
        for name in args.preview or PREVIEWS:
            _load_sample(args)
            PREVIEWS[name](args)
        return
    log("no build steps implemented yet")


if __name__ == "__main__":
    main()
