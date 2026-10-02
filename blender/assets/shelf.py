"""Video-store / home-collection shelf, built as tileable bays.

Frame (mm): X along the row, Y depth (plank front edge at Y=0, back panel
behind at +Y), Z up with the plank top at Z=0. Tapes stand with their spine
facing -Y.

One bay = left divider centre to right divider centre, so bays tile with
seams through identical divider halves. Each bay has its own plank and back
panel (separate boards, separate grain), an aluminium label rail runs along
the plank front with a printed section card (runtime text), and a warm LED
strip under the plank above lights the tapes from the front-top.

Variants differ in wood grain, dust and wear, so a wall of 40 bays doesn't
read as one tile repeated.
"""

from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Vector

from nc import MM, geo, mats, rig
from nc.atlas import SLEEVE_D, SLEEVE_H, SLEEVE_W

PITCH_DEG = 10.0         # camera looks down this much
PX_PER_MM = 3.0          # plate resolution; the dimensions below are chosen
                         # so slots, bays and row bands are whole pixels

PLANK_T = 18.0           # board thickness
PLANK_D = 160.0          # depth front edge -> back panel
ROW_BAND = 230.0         # on-screen row height (mm) -> 690 px
ROW_PITCH = ROW_BAND / math.cos(math.radians(PITCH_DEG))   # 233.55 mm
ROW_CLEAR = ROW_PITCH - PLANK_T      # plank top -> underside of the plank above
DIVIDER_T = 18.0
SLOTS = 12               # tapes per bay
SLOT_PITCH = 86.0 / PX_PER_MM        # 28.667 mm: 28 mm sleeve + 0.67 mm play
BAY_MARGIN = 5.0         # free space at each end of a full bay
BAY_INNER = SLOTS * SLOT_PITCH + 2 * BAY_MARGIN     # 354 mm
BAY_PITCH = BAY_INNER + DIVIDER_T                   # 372 mm -> 1116 px
BACK_T = 9.0
TAPE_FRONT_Y = 18.0      # spine plane of a pushed-in tape
RAIL_H, RAIL_D, RAIL_LIP = 30.0, 6.0, 8.0   # rail height, depth, height above plank
CARD_H = 19.0


def slot_x(slot: int, bay_center: float = 0.0) -> float:
    """Centre X (mm) of a slot in the bay centred on bay_center."""
    return bay_center - BAY_INNER / 2 + BAY_MARGIN + SLOT_PITCH * (slot + 0.5)


def slot_left_px(slot: int) -> int:
    """Left edge of a slot column in bay-plate pixels."""
    return int(round((DIVIDER_T / 2 + BAY_MARGIN + SLOT_PITCH * slot) * PX_PER_MM))


def _box(name, x0, x1, y0, y1, z0, z1, *, cuts=(1, 1, 1)):
    nx, ny, nz = cuts
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]
    ys = [y0 + (y1 - y0) * i / ny for i in range(ny + 1)]
    zs = [z0 + (z1 - z0) * i / nz for i in range(nz + 1)]
    bm = geo.lattice_box(xs, ys, zs)
    obj = geo.to_object(bm, name)
    obj.scale = (MM, MM, MM)
    return obj


def materials_dict(seed: float) -> dict:
    walnut = mats.Wood(seed=seed, axis="X", dust=0.5)
    back = mats.Wood(base=(0.10, 0.055, 0.03, 1.0), dark=(0.04, 0.02, 0.012, 1.0), roughness=0.62,
                     grain_scale=18.0, seed=seed + 31.0, axis="Z", dust=0.05)
    divider = mats.Wood(seed=101.0, axis="Z", dust=0.15)
    return {
        "plank": mats.cached(f"Shelf_Plank_{seed:g}", lambda: mats.wood(f"Shelf_Plank_{seed:g}", walnut)),
        "back": mats.cached(f"Shelf_Back_{seed:g}", lambda: mats.wood(f"Shelf_Back_{seed:g}", back)),
        "divider": mats.cached("Shelf_Divider", lambda: mats.wood("Shelf_Divider", divider)),
        "rail": mats.cached("Shelf_Rail", lambda: mats.metal(
            "Shelf_Rail", color=(0.62, 0.62, 0.60, 1.0), roughness=0.34, anisotropic=0.5)),
        "card": mats.cached("LABEL_SHELF_TAG", lambda: mats.label("LABEL_SHELF_TAG", mats.Print(
            ink_roughness=0.7, coat=0.0, wear=0.2, uv_hero="UV_LABEL_TAG", uv_spine="UV_LABEL_TAG"))),
    }


def build_bay(materials, *, x_center: float = 0.0, with_above: bool = True, collection=None,
              dividers=(True, True)) -> dict:
    """One bay centred on x_center. Returns its parts by role."""
    hx = BAY_PITCH / 2
    parts = {}
    # plank: own board per bay, front edge rounded over
    plank = _box("Shelf_Plank", x_center - hx + DIVIDER_T / 2, x_center + hx - DIVIDER_T / 2,
                 0.0, PLANK_D, -PLANK_T, 0.0, cuts=(8, 4, 1))
    geo.add_bevel(plank, 2.5, segments=4, angle_deg=40.0, profile=0.5, name="RoundOver")
    plank.data.materials.append(materials["plank"])
    parts["plank"] = plank
    # back panel
    back = _box("Shelf_Back", x_center - hx, x_center + hx, PLANK_D, PLANK_D + BACK_T,
                -PLANK_T, ROW_CLEAR, cuts=(4, 1, 4))
    back.data.materials.append(materials["back"])
    parts["back"] = back
    # dividers at both ends (the half outside the bay belongs to the neighbour)
    for side, wanted in zip((-1, 1), dividers):
        if not wanted:
            continue
        d = _box("Shelf_Divider", x_center + side * hx - DIVIDER_T / 2, x_center + side * hx + DIVIDER_T / 2,
                 -2.0, PLANK_D, -PLANK_T, ROW_CLEAR, cuts=(1, 4, 6))
        geo.add_bevel(d, 1.5, segments=3, angle_deg=40.0, name="Edge")
        d.data.materials.append(materials["divider"])
        parts[f"divider{side}"] = d
    if with_above:
        above = _box("Shelf_PlankAbove", x_center - hx, x_center + hx, 0.0, PLANK_D, ROW_CLEAR, ROW_CLEAR + PLANK_T)
        above.data.materials.append(materials["plank"])
        parts["above"] = above
    return parts


def build_rail(materials, *, x0: float, x1: float, z_offset: float = 0.0):
    """Aluminium C-channel along the plank front with a section card inside.
    The card face maps to UV_LABEL_TAG (0..1 over the bay's card)."""
    z_top = RAIL_LIP + z_offset
    z_bot = z_top - RAIL_H
    y_front = -RAIL_D
    bm = bmesh.new()
    # extruded profile: back plate, bottom lip, top lip (lips 2 mm deep)
    profile = [(0.0, z_bot), (y_front, z_bot), (y_front, z_bot + 2.2), (-1.4, z_bot + 2.2),
               (-1.4, z_top - 2.2), (y_front, z_top - 2.2), (y_front, z_top), (0.0, z_top)]
    rings = []
    for x in (x0, x1):
        rings.append([bm.verts.new((x, y, z)) for (y, z) in profile])
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    rail = geo.to_object(bm, "Shelf_Rail")
    rail.scale = (MM, MM, MM)
    geo.add_bevel(rail, 0.4, segments=2, angle_deg=40.0, name="Edge")
    rail.data.materials.append(materials["rail"])
    # card: thin paper strip held between the lips
    bm = bmesh.new()
    cz = (z_bot + z_top) / 2
    xs = [x0 + 1.0, x1 - 1.0]
    vs = [bm.verts.new((xs[0], -1.6, cz - CARD_H / 2)), bm.verts.new((xs[1], -1.6, cz - CARD_H / 2)),
          bm.verts.new((xs[1], -1.6, cz + CARD_H / 2)), bm.verts.new((xs[0], -1.6, cz + CARD_H / 2))]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv.new("UV_LABEL_TAG")
    for loop in f.loops:
        loop[uv].uv = ((loop.vert.co.x - xs[0]) / (xs[1] - xs[0]),
                       (loop.vert.co.z - (cz - CARD_H / 2)) / CARD_H)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if f.normal.y > 0:
        bmesh.ops.reverse_faces(bm, faces=[f])
    card = geo.to_object(bm, "Shelf_Card", smooth=False)
    card.scale = (MM, MM, MM)
    card.data.materials.append(materials["card"])
    return rail, card


def lights(*, x0: float, x1: float) -> list:
    """Warm LED strip under the plank above + soft room key + front fill."""
    width = (x1 - x0) * MM
    cx = (x0 + x1) / 2 * MM
    objs = []
    strip = rig.area_light("LED_Strip", (cx, 0.012, (ROW_CLEAR - 1.0) * MM), (cx, 0.09, 0.0),
                           size=(width, 0.008), power=rig.power_for(7.5, 0.2) * width / 0.37,
                           color=(1.0, 0.80, 0.58))
    objs.append(strip)
    key = rig.area_light("Room_Key", (cx - 0.2, -0.9, 0.55), (cx, 0.08, 0.09), size=(1.2, 0.6),
                         power=rig.power_for(1.1, 1.07), color=(1.0, 0.95, 0.9))
    objs.append(key)
    fill = rig.area_light("Room_Fill", (cx + 0.5, -0.8, 0.1), (cx, 0.08, 0.09), size=(1.0, 1.0),
                          power=rig.power_for(0.3, 0.95), color=(0.85, 0.9, 1.0))
    objs.append(fill)
    # The room behind the camera, seen only in reflections: a broad, dim
    # window-like card low in front gives laminated spines a soft sheen
    # that shifts across their rounded folds.
    card = rig.light_card("Room_Reflection", (cx - 0.15, -1.1, 0.30), (cx, 0.0, 0.10),
                          size=(width * 1.6 + 0.6, 0.55), strength=0.55, color=(0.95, 0.96, 1.0, 1.0))
    objs.append(card)
    return objs


def camera_for(x0: float, x1: float, z_lo: float, z_hi: float, *, px_per_mm: float = PX_PER_MM):
    """Orthographic camera looking down PITCH_DEG framing world X in
    [x0, x1] and the screen band whose 'height' coordinate spans
    [z_lo, z_hi], where screen height h = y*sin(p) + z*cos(p) (mm).
    Pixels are exactly 1/px_per_mm mm when the spans are whole pixels."""
    from nc import scene
    p = math.radians(PITCH_DEG)
    rx = int(round((x1 - x0) * px_per_mm))
    ry = int(round((z_hi - z_lo) * px_per_mm))
    bpy.context.scene.render.resolution_x = rx
    bpy.context.scene.render.resolution_y = ry
    bpy.context.scene.render.pixel_aspect_x = 1.0
    bpy.context.scene.render.pixel_aspect_y = 1.0
    cx = (x0 + x1) / 2
    hc = (z_lo + z_hi) / 2
    # point at y=0 with screen height hc: z = hc / cos(p)
    target = Vector((cx, 0.0, hc / math.cos(p))) * MM
    view = Vector((0.0, math.cos(p), -math.sin(p)))
    loc = target - view * 1.5
    cam = scene.camera("ShelfCam", loc, target, ortho_scale=max(rx, ry) / px_per_mm * MM)
    cam.data.sensor_fit = "HORIZONTAL" if rx >= ry else "VERTICAL"
    return cam


def place_tape(source: bpy.types.Object, x: float, *, pull: float = 0.0, yaw_deg: float = 0.0,
               lean_deg: float = 0.0, height: float = 1.0, name: str = "Tape", extra=()) -> list:
    """Instance a sleeve-space mesh (sleeve, shrink film …) standing on the
    plank with its spine to -Y, centred on x (mm).

    pull: toward the camera (mm). yaw_deg: about Z (shows the cover side).
    lean_deg > 0 tips the top to the LEFT (-X) about the bottom-left edge,
    the way a tape falls against its left neighbour; < 0 mirrors it.
    height: scale of the sleeve's height (retail sleeves vary by a few mm).
    extra: more sleeve-space objects (e.g. the film) given the same
    transform. Returns all instances, the sleeve first."""
    from mathutils import Matrix
    from assets import sleeve
    to_shelf = Matrix.Rotation(math.radians(90.0), 4, "Z")
    lift = Matrix.Translation((0, 0, sleeve.HH * height * MM)) @ Matrix.Diagonal((1.0, 1.0, height, 1.0))
    yaw = Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    side = -1.0 if lean_deg >= 0 else 1.0
    pivot = Vector((side * sleeve.HD * MM, 0, 0))
    lean = (Matrix.Translation(pivot) @ Matrix.Rotation(-math.radians(lean_deg), 4, "Y")
            @ Matrix.Translation(-pivot))
    place = Matrix.Translation((x * MM, (TAPE_FRONT_Y + sleeve.HW - pull) * MM, 0))
    mm = Matrix.Diagonal((MM, MM, MM, 1.0))   # meshes are authored in mm
    world = place @ lean @ yaw @ lift @ to_shelf @ mm
    out = []
    for src in (source, *extra):
        inst = src.copy()                 # shares mesh data
        bpy.context.scene.collection.objects.link(inst)
        inst.name = name if not out else f"{name}_{src.name}"
        inst.parent = None
        inst.hide_render = False          # sources are hidden
        inst.matrix_world = world
        out.append(inst)
    return out


def lean_x(neighbour_right_face: float, lean_deg: float, height: float = 1.0) -> float:
    """Centre x for a tape leaning left so its top-left corner rests on the
    right face of the neighbour (a tape or the divider)."""
    return neighbour_right_face + SLEEVE_H * height * math.sin(math.radians(lean_deg)) + SLEEVE_D / 2


def screen_height(y: float, z: float) -> float:
    p = math.radians(PITCH_DEG)
    return y * math.sin(p) + z * math.cos(p)


# Vertical band of one row on screen: from the bottom of its own rail up to
# the bottom of the rail of the row above, so stacked rows meet exactly.
ROW_BAND_LO = screen_height(-RAIL_D, RAIL_LIP - RAIL_H)
ROW_BAND_HI = ROW_BAND_LO + ROW_PITCH * math.cos(math.radians(PITCH_DEG))
