"""Portfolio renders: turntables and beauty stills of every asset, with the
generated sample artwork on the label surfaces (showcase mode).

  renders/cassette_hero.png      cassette, three-quarter, dark studio
  renders/cassette_macro.png     window and reels close-up
  renders/sleeve_eject.png       sleeve with the cassette half out
  renders/shelf_wall.png         two rows of three bays, perspective
  renders/_frames/<asset>_tt_NN  turntable frames (encoded to animated
                                 WebP by tools/plates/turntable.py)
"""

from __future__ import annotations

import math
import random
import time

import bpy
from mathutils import Matrix

from nc import MM, mats, rig, scene
from nc.paths import CACHE, RENDERS

from . import cassette, shelf, sleeve


def _log(msg: str) -> None:
    print(f"[nc beauty {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _samples():
    mats.load_sample_image(CACHE / "sample_hero.png")
    mats.load_sample_image(CACHE / "sample_spines.png", name="NC_SAMPLE_SPINES")


def _studio_scene(w: int, h: int, samples: int):
    sc = scene.reset()
    _samples()
    scene.setup_cycles(sc, width=w, height=h, samples=samples, transparent=False)
    rig.world_gradient()
    return sc


def _shoot(path, t0=None):
    scene.render_still(path, color_mode="RGB")
    _log(f"{path.name} in {time.time() - (t0 or time.time()):.0f}s")


def cassette_shots(args) -> None:
    q = args.quick
    sc = _studio_scene(960 if q else 1920, 640 if q else 1280, 64 if q else 512)
    cassette.build(progress=0.62)
    target = (0, 0.004, 0.0125)
    rig.studio(target=target, radius=0.55)
    rig.cyclorama(size=1.6)
    mats.set_mode(mats.MODE_SHOWCASE)
    t0 = time.time()
    sc.camera = scene.camera("Hero", scene.orbit_location(target, 0.44, -32.0, 27.0), target, lens=60.0)
    _shoot(RENDERS / "cassette_hero.png", t0)
    t0 = time.time()
    macro_t = (0.012, 0.010, 0.019)       # the take-up reel, seen through the window
    sc.camera = scene.camera("Macro", scene.orbit_location(macro_t, 0.26, 18.0, 50.0), macro_t, lens=100.0)
    sc.camera.data.dof.use_dof = True
    sc.camera.data.dof.focus_distance = 0.26
    sc.camera.data.dof.aperture_fstop = 11.0
    _shoot(RENDERS / "cassette_macro.png", t0)


def sleeve_shots(args) -> None:
    q = args.quick
    sc = _studio_scene(960 if q else 1920, 640 if q else 1280, 64 if q else 512)
    root = sleeve.build(with_cassette=True, progress=0.62)
    # stand the sleeve, front cover three-quarter to the camera, cassette half out
    tape = bpy.data.objects[root["nc_cassette"]]
    tape.matrix_world = Matrix.Translation((62.0 * MM, 0, 0)) @ tape.matrix_world
    root.location = (0, 0, sleeve.HH * MM)
    root.rotation_euler = (0, 0, math.radians(-28.0))
    target = (0.02, 0, sleeve.HH * MM)
    rig.studio(target=target, radius=0.8)
    for side, strength in ((-1, 1.2), (1, 0.6)):
        rig.light_card(f"Strip{side:+d}", (side * 0.6, -0.35, target[2] + 0.04), target,
                       size=(0.12, 0.7), strength=strength)
    rig.cyclorama(size=2.4)
    mats.set_mode(mats.MODE_SHOWCASE)
    t0 = time.time()
    sc.camera = scene.camera("Eject", scene.orbit_location(target, 0.82, -18.0, 12.0), target, lens=70.0)
    _shoot(RENDERS / "sleeve_eject.png", t0)


def shelf_wall(args) -> None:
    q = args.quick
    sc = _studio_scene(960 if q else 1920, 640 if q else 1280, 64 if q else 512)
    rig.world_gradient(top=(0.018, 0.018, 0.020), bottom=(0.004, 0.004, 0.004))
    bays, rows = 3, 2
    sleeve.build(with_cassette=False)
    src = bpy.data.objects["VHS_Sleeve"]
    src.hide_render = True
    film = sleeve.build_film()
    film.hide_render = True
    rnd = random.Random(5)
    for r in range(rows):
        dz = r * shelf.ROW_PITCH
        for b in range(bays):
            xc = (b - 1) * shelf.BAY_PITCH
            # the plank above a row is the next row's own plank, except at the top
            parts = shelf.build_bay(shelf.materials_dict(seed=1.0 + b + 3 * r), x_center=xc,
                                    with_above=r == rows - 1, dividers=(True, b == bays - 1))
            for o in parts.values():
                o.location.z += dz * MM
            shelf.build_rail(shelf.materials_dict(seed=1.0), x0=xc - shelf.BAY_INNER / 2,
                             x1=xc + shelf.BAY_INNER / 2, z_offset=dz)
            count = shelf.SLOTS if (r, b) != (1, 2) else 7
            for i in range(count):
                pull, yaw, height = rnd.choice(list(_PACKED))
                if rnd.random() < 0.06:
                    pull, yaw = 16.0, 0.15
                shelf.place_tape(src, shelf.slot_x(i, xc), pull=pull, yaw_deg=yaw, height=height, z=dz,
                                 name=f"T{r}{b}{i}", extra=(film,) if rnd.random() < 0.1 else ())
            if count < shelf.SLOTS:
                face = shelf.slot_x(count - 1, xc) + sleeve.HD
                shelf.place_tape(src, shelf.lean_x(face, 9.0), lean_deg=9.0, z=dz, name=f"T{r}{b}L")
    x0 = -1.5 * shelf.BAY_PITCH
    shelf.lights(x0=x0, x1=-x0, rows=rows)
    mats.set_mode(mats.MODE_SHOWCASE, grid=True)
    target = (0.0, 0.05, shelf.ROW_PITCH * MM * 0.92)
    sc.camera = scene.camera("Wall", scene.orbit_location(target, 1.08, -20.0, 5.0), target, lens=50.0)
    sc.camera.data.dof.use_dof = True
    sc.camera.data.dof.focus_distance = 1.08
    sc.camera.data.dof.aperture_fstop = 4.0
    t0 = time.time()
    _shoot(RENDERS / "shelf_wall.png", t0)


_PACKED = [(0.0, 0.0, 1.0), (1.4, -0.25, 0.988), (2.8, 0.2, 1.008), (4.2, -0.1, 0.995)]


def dvd_shots(args) -> None:
    from . import dvd
    q = args.quick
    sc = _studio_scene(960 if q else 1920, 640 if q else 1280, 64 if q else 512)
    mats.load_sample_image(CACHE / "sample_dvd.png")      # the DVD atlas layout
    root = dvd.build()
    root.location = (0, 0, dvd.HH * MM)
    root.rotation_euler = (0, 0, math.radians(-24.0))
    target = (0.0, 0, dvd.HH * MM)
    rig.studio(target=target, radius=0.8)
    for side, strength in ((-1, 1.2), (1, 0.6)):
        rig.light_card(f"Strip{side:+d}", (side * 0.6, -0.35, target[2] + 0.04), target,
                       size=(0.12, 0.7), strength=strength)
    rig.cyclorama(size=2.4)
    mats.set_mode(mats.MODE_SHOWCASE)
    t0 = time.time()
    sc.camera = scene.camera("DVD", scene.orbit_location(target, 0.78, -20.0, 10.0), target, lens=70.0)
    _shoot(RENDERS / "dvd_hero.png", t0)


def turntables(args) -> None:
    q = args.quick
    n = 12 if q else 36
    for name, build, size, target, dist, pitch, lens in (
            ("cassette", lambda: cassette.build(progress=0.4), (720, 480), (0, 0.004, 0.0125), 0.6, 24.0, 60.0),
            ("sleeve", lambda: _standing_sleeve(), (560, 720), (0, 0, sleeve.HH * MM), 0.9, 10.0, 70.0)):
        sc = _studio_scene(*size, 48 if q else 160)
        root = build()
        rig.studio(target=target, radius=0.7)
        rig.cyclorama(size=2.0)
        mats.set_mode(mats.MODE_SHOWCASE)
        sc.camera = scene.camera("TT", scene.orbit_location(target, dist, 0.0, pitch), target, lens=lens)
        t0 = time.time()
        for i in range(n):
            root.rotation_euler = (0, 0, math.radians(360.0 * i / n) + root.get("nc_yaw0", 0.0))
            scene.render_still(RENDERS / "_frames" / f"{name}_tt_{i:02d}.png", color_mode="RGB")
        _log(f"{name} turntable: {n} frames in {time.time() - t0:.0f}s")


def _standing_sleeve():
    root = sleeve.build(with_cassette=True, progress=0.4)
    root.location = (0, 0, sleeve.HH * MM)
    root["nc_yaw0"] = math.radians(-60.0)
    return root


def render_all(args) -> None:
    for fn in (cassette_shots, sleeve_shots, shelf_wall, dvd_shots, turntables):
        fn(args)
