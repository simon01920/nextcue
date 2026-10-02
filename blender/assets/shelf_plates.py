"""Shelf plates: what the app composites to draw any number of tapes.

Every plate is rendered in the same frame, one bay wide (divider centre to
divider centre, 1116 px) and one row band tall (690 px), so a plate's crop
rectangle is directly its position inside a bay. The app draws, per row:

  1. bay_<n>           opaque background: back panel, plank floor, dividers
  2. tape_end_shadow   only after the last tape of a part-filled bay
  3. tape_<variant>    one per tape, in its slot column (86 px). Variants
                       a..d are packed poses; sealed adds shrink-wrap
  4. tape_pulled_shadow, tape_pulled   a tape pulled forward (watching)
  5. tape_lean         last tape of a part-filled bay, leaning left
  6. rail              aluminium rail and section card, over the tape feet

Tape plates are rendered at slot 5 with neighbours present as holdouts:
they light and shadow the tape (dark gaps, occlusion on the spine edges)
but are cut out of the plate, so each tape's plate covers only its own
column and columns tile seamlessly. Shelf surfaces are shadow catchers, so
the gaps between tapes carry the shadow over whatever the background is.
"""

from __future__ import annotations

import time

import bpy

from nc import MM, mats, plates, rig, scene
from nc.paths import PLATE_DIR

from . import shelf, sleeve

GROUP = "shelf"
HERO = 5                     # slot the measured tape stands in
LEAN_DEG = 9.0
PULL_MM = 16.0
BAY_SEEDS = (1.0, 2.0, 3.0)

# packed poses: (pull mm, yaw deg, height scale). A 0.67 mm gap allows
# ~0.35 deg of yaw; retail sleeves vary a few mm in height.
PACKED = {
    "a": (0.0, 0.0, 1.0),
    "b": (1.4, -0.25, 0.988),
    "c": (2.8, 0.2, 1.008),
    "d": (4.2, -0.1, 0.995),
}


def _log(msg: str) -> None:
    print(f"[nc shelf {time.strftime('%H:%M:%S')}] {msg}", flush=True)


class Stage:
    """One bay with everything around it that affects its light."""

    def __init__(self, *, bay_seed: float, samples: int):
        sc = scene.reset()
        scene.setup_cycles(sc, width=100, height=100, samples=samples, transparent=True)
        rig.world_gradient(top=(0.018, 0.018, 0.020), bottom=(0.004, 0.004, 0.004))
        m = shelf.materials_dict(seed=bay_seed)
        self.bay = shelf.build_bay(m, x_center=0.0)
        x0, x1 = -shelf.BAY_INNER / 2, shelf.BAY_INNER / 2
        self.rail = shelf.build_rail(m, x0=x0, x1=x1)
        self.next_rail = shelf.build_rail(m, x0=x0, x1=x1, z_offset=shelf.ROW_PITCH)
        shelf.lights(x0=-1.5 * shelf.BAY_PITCH, x1=1.5 * shelf.BAY_PITCH)
        sleeve.build(with_cassette=False)
        self.src = bpy.data.objects["VHS_Sleeve"]
        self.src.hide_render = True
        self.film = sleeve.build_film()
        self.film.hide_render = True
        self.cam = shelf.camera_for(-shelf.BAY_PITCH / 2, shelf.BAY_PITCH / 2,
                                    shelf.ROW_BAND_LO, shelf.ROW_BAND_HI)
        sc.camera = self.cam
        self.tapes: list[bpy.types.Object] = []
        self.frame = (sc.render.resolution_x, sc.render.resolution_y)

    # -- scene roles -------------------------------------------------------
    def shelf_objects(self):
        return [*self.bay.values(), *self.rail, *self.next_rail]

    def clear_tapes(self):
        self.drop(list(self.tapes))

    def drop(self, objs):
        for o in objs:
            self.tapes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)

    def tape(self, x, *, film=False, **kw):
        objs = shelf.place_tape(self.src, x, extra=(self.film,) if film else (), **kw)
        self.tapes.extend(objs)
        return objs

    @staticmethod
    def role(objs, *, camera=True, catcher=False, holdout=False, shadow=True):
        for o in objs:
            o.visible_camera = camera
            o.is_shadow_catcher = catcher
            o.is_holdout = holdout
            o.visible_shadow = shadow

    def roles_for_sprites(self):
        """Shelf surfaces catch shadows; surfaces hidden behind other plates
        (this row's rail, the row above) stay in for light but not camera."""
        self.role(self.shelf_objects(), catcher=True)
        self.role([*self.rail, self.bay["above"]], camera=False, catcher=True)
        self.role(self.next_rail, holdout=True)

    def neighbours(self, slots, **role):
        out = []
        for s in slots:
            out += self.tape(shelf.slot_x(s), name=f"N{s}")
        self.role(out, **role)
        return out


def _column(slot: int, n: int = 1) -> tuple:
    return (shelf.slot_left_px(slot), 0, int(round(n * shelf.SLOT_PITCH * shelf.PX_PER_MM)),
            int(round(shelf.ROW_BAND * shelf.PX_PER_MM)))


def render_all(args) -> list[dict]:
    out_dir = PLATE_DIR / GROUP
    out_dir.mkdir(parents=True, exist_ok=True)
    samples = 64 if args.quick else 384
    entries: list[dict] = []
    t_all = time.time()

    # 1. bay backgrounds (opaque; no tapes)
    for i, seed in enumerate(BAY_SEEDS):
        st = Stage(bay_seed=seed, samples=samples)
        st.role([*st.rail, *st.next_rail], camera=False)
        entries.append(plates.render_plate(plates.PlateSpec(
            name=f"bay_{i}", labels=False, transparent=False, crop=False, samples=samples,
            quality=88), out_dir))
        if i == 0:
            # rail plate from the same stage: only the rail (and its card) visible
            st.role(st.shelf_objects(), camera=False)
            st.role(st.rail, camera=True)
            st.neighbours(range(shelf.SLOTS), camera=False)
            entries.append(plates.render_plate(plates.PlateSpec(
                name="rail", uvset=0, samples=samples, margin_px=2, meta={"atlas": "tag"}), out_dir))

    st = Stage(bay_seed=BAY_SEEDS[0], samples=samples)
    st.roles_for_sprites()
    col = _column(HERO)
    left, right = (HERO - 3, HERO - 2, HERO - 1), (HERO + 1, HERO + 2, HERO + 3)

    # Every sprite's meta "slot" is the slot it was rendered for: the app
    # shifts the plate by (target_slot - slot) * slot_px.

    # 2. packed variants + sealed
    st.neighbours((*left, *right), holdout=True)
    for key, (pull, yaw, height) in PACKED.items():
        hero = st.tape(shelf.slot_x(HERO), pull=pull, yaw_deg=yaw, height=height, name=f"Hero_{key}")
        entries.append(plates.render_plate(plates.PlateSpec(
            name=f"tape_{key}", uvset=1, samples=samples, crop_px=col,
            meta={"slot": HERO, "pull_mm": pull, "height": height}), out_dir))
        st.drop(hero)
    hero = st.tape(shelf.slot_x(HERO), pull=0.6, yaw_deg=0.1, film=True, name="Hero_sealed")
    entries.append(plates.render_plate(plates.PlateSpec(
        name="tape_sealed", uvset=1, samples=samples, crop_px=col,
        meta={"slot": HERO, "pull_mm": 0.6}), out_dir))
    st.drop(hero)

    # 3. pulled forward (watching): the tape, then its shadow on neighbours
    st.tape(shelf.slot_x(HERO), pull=PULL_MM, yaw_deg=0.15, name="Hero_pulled")
    entries.append(plates.render_plate(plates.PlateSpec(
        name="tape_pulled", uvset=1, samples=samples, crop_px=col,
        meta={"slot": HERO, "pull_mm": PULL_MM}), out_dir))
    st.clear_tapes()
    hero = st.tape(shelf.slot_x(HERO), pull=PULL_MM, yaw_deg=0.15, name="Hero_pulled")
    st.role(hero, camera=False)
    # Only the pulled tape may count as a caster: the neighbours are
    # catchers (the near ones visible, the far ones only for light).
    st.neighbours((HERO - 1, HERO + 1), catcher=True)
    st.neighbours((HERO - 3, HERO - 2, HERO + 2, HERO + 3), camera=False, catcher=True)
    entries.append(plates.render_plate(plates.PlateSpec(
        name="tape_pulled_shadow", labels=False, samples=samples, crop_px=_column(HERO - 1, 3),
        meta={"slot": HERO}), out_dir))
    st.clear_tapes()

    # 4. end of a part-filled bay: shadow of the last upright onto the empty floor
    hero = st.tape(shelf.slot_x(HERO), name="Hero_end")
    st.role(hero, camera=False)
    st.neighbours(left, camera=False)
    entries.append(plates.render_plate(plates.PlateSpec(
        name="tape_end_shadow", labels=False, samples=samples, crop_px=_column(HERO + 1, 3),
        meta={"slot": HERO}), out_dir))
    st.clear_tapes()

    # 5. leaning on the last upright: the lean tape takes slots HERO, HERO+1
    st.neighbours((HERO - 3, HERO - 2, HERO - 1), holdout=True)
    face = shelf.slot_x(HERO - 1) + sleeve.HD
    st.tape(shelf.lean_x(face, LEAN_DEG), lean_deg=LEAN_DEG, name="Hero_lean")
    x_lo = shelf.slot_left_px(HERO - 1) + 43
    entries.append(plates.render_plate(plates.PlateSpec(
        name="tape_lean", uvset=1, samples=samples, margin_px=3, scout_threshold=0.03,
        clamp_px=(x_lo, 0, st.frame[0], st.frame[1]),
        meta={"slot": HERO, "lean_deg": LEAN_DEG, "slots_used": 2}), out_dir))
    st.clear_tapes()

    layout = {
        "px_per_mm": shelf.PX_PER_MM,
        "bay_px": [st.frame[0], st.frame[1]],
        "slots": shelf.SLOTS,
        "slot_px": int(round(shelf.SLOT_PITCH * shelf.PX_PER_MM)),
        "slot0_left_px": shelf.slot_left_px(0),
        "inner_px": [int(round(shelf.DIVIDER_T / 2 * shelf.PX_PER_MM)),
                     int(round((shelf.DIVIDER_T / 2 + shelf.BAY_INNER) * shelf.PX_PER_MM))],
        "plate_slot": HERO,
        "bays": [f"bay_{i}" for i in range(len(BAY_SEEDS))],
        "packed": [f"tape_{k}" for k in PACKED],
        "lean_max_tapes": shelf.SLOTS - 1,
        "atlas": "spine",
    }
    plates.update_manifest(GROUP, entries, layout)
    _log(f"{len(entries)} shelf plates in {time.time() - t_all:.0f}s")
    return entries
