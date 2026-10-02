"""Hero plates: the inspect view that opens when a tape is tapped.

rot_00 .. rot_35   the sleeve (cassette inside) turning on a studio floor in
                   10 degree steps. Frame 0 shows the spine, as on the
                   shelf; frame 9 the front cover; 18 the open side with
                   the cassette's spine sticker; 27 the back cover.
front_hi           frame 9 at twice the resolution, for the settled view.
cassette_pNNN      the cassette lying face-up, with the reels wound to
                   NNN percent watched: the progress cue of the panel.

All share one camera per group, so frames line up without offsets; the
floor is a shadow catcher, so the plates float on any background with
their contact shadow. Labels use the hero atlas (uvset 0).
"""

from __future__ import annotations

import math
import time

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

from nc import MM, mats, plates, rig, scene

from . import cassette, sleeve

GROUP = "hero"
STEPS = 36
STEP_DEG = 360.0 / STEPS
FRONT = 9
SIZE = (640, 900)
LENS = 100.0
PITCH = 8.0
PROGRESS = (0, 25, 50, 75, 100)


def _log(msg: str) -> None:
    print(f"[nc hero {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _floor(size_mm: float = 1200.0) -> bpy.types.Object:
    import bmesh
    from nc import geo
    bm = bmesh.new()
    h = size_mm / 2
    vs = [bm.verts.new(p) for p in ((-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0))]
    bm.faces.new(vs)
    obj = geo.to_object(bm, "Floor", smooth=False)
    obj.scale = (MM, MM, MM)
    obj.data.materials.append(mats.matte("Floor", (0.4, 0.4, 0.4, 1.0), roughness=0.6))
    obj.is_shadow_catcher = True
    return obj


def _px(sc, cam, p) -> list[float]:
    v = world_to_camera_view(sc, cam, Vector(p))
    return [round(v.x * sc.render.resolution_x, 2), round((1 - v.y) * sc.render.resolution_y, 2)]


def render_rotation(args, out_dir) -> tuple[list[dict], dict]:
    sc = scene.reset()
    w, h = SIZE
    samples = 48 if args.quick else 320
    scene.setup_cycles(sc, width=w, height=h, samples=samples, transparent=True)
    rig.world_gradient()
    root = sleeve.build(with_cassette=True, progress=0.35)
    root.location = (0, 0, sleeve.HH * MM)
    _floor()
    target = (0, 0, sleeve.HH * MM)
    rig.studio(target=target, radius=0.75)
    # Vertical strip softboxes 60 degrees either side of the camera: a face
    # turned ~30 degrees catches one as a soft streak that sweeps across the
    # laminate while the sleeve turns (seen only in reflections).
    for side, strength in ((-1, 1.3), (1, 0.7)):
        rig.light_card(f"Strip{side:+d}", (side * 0.52, -0.30, target[2] + 0.03), target,
                       size=(0.10, 0.6), strength=strength)
    # frame the sleeve at ~80 % of the height
    fov = 2 * math.atan(18.0 / LENS)
    dist = (sleeve.SLEEVE_H * 1.25 * MM) / (2 * math.tan(fov / 2))
    cam = scene.camera("HeroCam", scene.orbit_location(target, dist, 0.0, PITCH), target, lens=LENS)
    sc.camera = cam
    entries = []
    frames = range(0, STEPS, 4) if args.quick else range(STEPS)
    for i in frames:
        root.rotation_euler = (0, 0, math.radians(90.0 - i * STEP_DEG))
        entries.append(plates.render_plate(plates.PlateSpec(
            name=f"rot_{i:02d}", uvset=0, samples=samples, crop=False, uv_bits=13,
            meta={"index": i, "deg": i * STEP_DEG}), out_dir))
    # hi-res settled front view
    root.rotation_euler = (0, 0, math.radians(90.0 - FRONT * STEP_DEG))
    sc.render.resolution_x, sc.render.resolution_y = w * 2, h * 2
    entries.append(plates.render_plate(plates.PlateSpec(
        name="front_hi", uvset=0, samples=samples, crop=False, uv_bits=13,
        meta={"index": FRONT, "deg": FRONT * STEP_DEG, "scale": 2}), out_dir))
    sc.render.resolution_x, sc.render.resolution_y = w, h
    layout = {
        "frames": STEPS, "step_deg": STEP_DEG, "front": FRONT, "size": [w, h],
        "available": [i for i in frames],
        # where the sleeve stands, in frame pixels, for the shelf hand-off
        "floor_center_px": _px(sc, cam, (0, 0, 0)),
        "top_center_px": _px(sc, cam, (0, 0, sleeve.SLEEVE_H * MM)),
        "mm_per_px_at_center": round(sleeve.SLEEVE_H / abs(
            _px(sc, cam, (0, 0, sleeve.SLEEVE_H * MM))[1] - _px(sc, cam, (0, 0, 0))[1]), 4),
        "atlas": "hero",
    }
    return entries, layout


def render_cassettes(args, out_dir) -> tuple[list[dict], dict]:
    entries = []
    samples = 48 if args.quick else 320
    layout = {}
    for p in PROGRESS:
        sc = scene.reset()
        scene.setup_cycles(sc, width=900, height=620, samples=samples, transparent=True)
        rig.world_gradient()
        # spine sticker (-Y) toward the camera, take-up reel on the right
        cassette.build(progress=p / 100.0)
        _floor()
        target = (0, 0.004, cassette.T * 0.5 * MM)
        rig.studio(target=target, radius=0.55)
        # a soft card straight above lights the reels through the window
        rig.area_light("WindowTop", (0.0, 0.0, 0.45), (0, 0, 0), size=(0.25, 0.12),
                       power=rig.power_for(1.6, 0.45))
        cam = scene.camera("CassetteCam", scene.orbit_location(target, 0.52, 0.0, 52.0), target, lens=85.0)
        sc.camera = cam
        entries.append(plates.render_plate(plates.PlateSpec(
            name=f"cassette_p{p:03d}", uvset=0, samples=samples, crop=False, uv_bits=13,
            meta={"progress": p / 100.0}), out_dir))
        layout = {"progress": [p / 100.0 for p in PROGRESS], "size": [900, 620], "atlas": "hero"}
    return entries, layout


def render_all(args) -> list[dict]:
    out_dir = plates.staging(GROUP)
    t0 = time.time()
    rot, layout = render_rotation(args, out_dir)
    cas, cas_layout = render_cassettes(args, out_dir)
    layout["cassette"] = cas_layout
    plates.publish(out_dir, GROUP)
    plates.update_manifest(GROUP, rot + cas, layout)
    _log(f"{len(rot) + len(cas)} hero plates in {time.time() - t0:.0f}s")
    return rot + cas
