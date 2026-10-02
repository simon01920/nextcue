"""VHS cardboard slipcase (retail sleeve), 107 x 190.5 x 28 mm.

Frame: X = width with the spine at -X and the open side at +X, Y = depth
with the front cover facing -Y, Z = height. Viewed from the front, the spine
is on the left, like a book.

Five closed faces built as a subdivided lattice, then given board thickness
by a Solidify modifier (inner lining and raw cut edge get their own
materials through the modifier's material offsets). Folds are rounded by a
bevel; the covers bow very slightly like real board, and the corners are
gently crushed.

UV maps
  UV_LABEL_HERO   back | spine | front unfolded into the hero atlas
  UV_LABEL_SPINE  spine + the 20 mm of front cover beside the fold (shelf)
  UV_BAKE         non-overlapping unwrap for texture baking (GLB export)
Material slots: COVER_BACK, LABEL_SPINE, COVER_ART (artwork at runtime),
SLEEVE_PRINT_END (top/bottom ends), SLEEVE_BOARD (inside), SLEEVE_EDGE.
"""

from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Vector

from nc import MM, geo, mats
from nc.atlas import HERO, SPINE, SLEEVE_D, SLEEVE_H, SLEEVE_W, FRONT_STRIP

HW, HH, HD = SLEEVE_W / 2, SLEEVE_H / 2, SLEEVE_D / 2
BOARD = 0.8          # mm
BULGE = 0.35         # mm, cover bow at the centre


def _lattice():
    nx, ny, nz = 12, 6, 24
    xs = [-HW + SLEEVE_W * i / nx for i in range(nx + 1)]
    ys = [-HD + SLEEVE_D * i / ny for i in range(ny + 1)]
    zs = [-HH + SLEEVE_H * i / nz for i in range(nz + 1)]
    return xs, ys, zs


def _uv_hero(face, co: Vector):
    x, y, z = co
    v = (z + HH) / SLEEVE_H
    n = face.normal
    if n.y < -0.9:                    # front: left edge meets the spine fold
        return HERO["front"].uv((x + HW) / SLEEVE_W, v)
    if n.y > 0.9:                     # back: seen from +Y, right edge at the spine
        return HERO["back"].uv((HW - x) / SLEEVE_W, v)
    if n.x < -0.9:                    # spine: seen from -X, right edge at the front
        return HERO["spine"].uv((HD - y) / SLEEVE_D, v)
    # ends: the print wraps over the fold, so each end repeats the spine's
    # outermost row of artwork across its depth
    return HERO["spine"].uv(min(1.0, max(0.0, (HD - y) / SLEEVE_D)), 0.997 if z > 0 else 0.003)


def _uv_spine(face, co: Vector):
    x, y, z = co
    v = (z + HH) / SLEEVE_H
    n = face.normal
    if n.x < -0.9:
        return SPINE["spine"].uv((HD - y) / SLEEVE_D, v)
    if n.y < -0.9:
        u = min(1.0, (x + HW) / FRONT_STRIP)
        return SPINE["front_strip"].uv(u, v)
    if n.y > 0.9:                     # back: not visible on the shelf
        return SPINE["spine"].uv(0.0, v)
    return SPINE["spine"].uv(min(1.0, max(0.0, (HD - y) / SLEEVE_D)), 0.997 if z > 0 else 0.003)


def build_mesh(seed: int = 7) -> bpy.types.Object:
    xs, ys, zs = _lattice()
    bm = geo.lattice_box(xs, ys, zs)
    # open side
    geo.remove_faces(bm, [f for f in bm.faces if f.normal.x > 0.9])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    # Covers bow outward a little, strongest at the centre; ends dish in.
    for v in bm.verts:
        u = (v.co.x + HW) / SLEEVE_W
        w = (v.co.z + HH) / SLEEVE_H
        bow = (1 - (2 * u - 1) ** 2) * (1 - (2 * w - 1) ** 2)
        if abs(abs(v.co.y) - HD) < 1e-6:
            v.co.y += math.copysign(BULGE * bow, v.co.y)
    # Gently crushed corners: each corner is pushed in along its diagonal
    # by a deterministic amount, fading out over 6 mm.
    rnd = random.Random(seed)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                corner = Vector((sx * HW, sy * HD, sz * HH))
                inward = -Vector((sx, sy, sz)).normalized()
                amt = rnd.uniform(0.15, 0.5)
                for v in bm.verts:
                    d = (v.co - corner).length
                    if d < 6.0:
                        v.co += inward * amt * (1 - d / 6.0) ** 2

    bm.normal_update()
    uv_h = bm.loops.layers.uv.new(mats.LABEL_UV_HERO)
    uv_s = bm.loops.layers.uv.new(mats.LABEL_UV_SPINE)
    for f in bm.faces:
        n = f.normal
        if n.y < -0.9:
            f.material_index = 2           # COVER_ART
        elif n.y > 0.9:
            f.material_index = 0           # COVER_BACK
        elif n.x < -0.9:
            f.material_index = 1           # LABEL_SPINE
        else:
            f.material_index = 3           # SLEEVE_PRINT_END
        for loop in f.loops:
            loop[uv_h].uv = _uv_hero(f, loop.vert.co)
            loop[uv_s].uv = _uv_spine(f, loop.vert.co)

    # Board thickness. Every face the op adds is either the inner lining or
    # the raw cut edge at the opening; classify them explicitly rather than
    # relying on the modifier's additive material offsets.
    outer = set(bm.faces)
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=BOARD)
    bm.normal_update()
    for f in bm.faces:
        if f in outer:
            continue
        c = f.calc_center_median()
        f.material_index = 5 if c.x > HW - BOARD * 1.5 and abs(f.normal.x) < 0.5 else 4
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = geo.to_object(bm, "VHS_Sleeve")
    obj.scale = (MM, MM, MM)
    geo.add_bevel(obj, 0.7, segments=4, angle_deg=35.0, profile=0.55, name="Folds")
    geo.add_weighted_normals(obj)
    return obj


FILM_GAP = 0.3       # mm between board and film


def build_film(seed: int = 3) -> bpy.types.Object:
    """Shrink-wrap around the closed sleeve: a slightly oversized box whose
    faces float off the board in shallow air pockets, tightest at the folds,
    with softly rounded corners where the film was heat-shrunk."""
    g = FILM_GAP
    nx, ny, nz = 14, 5, 28
    xs = [-HW - g + (SLEEVE_W + 2 * g) * i / nx for i in range(nx + 1)]
    ys = [-HD - g + (SLEEVE_D + 2 * g) * i / ny for i in range(ny + 1)]
    zs = [-HH - g + (SLEEVE_H + 2 * g) * i / nz for i in range(nz + 1)]
    bm = geo.lattice_box(xs, ys, zs)
    rnd = random.Random(seed)
    phase = [rnd.uniform(0, math.tau) for _ in range(6)]
    for v in bm.verts:
        x, y, z = v.co
        # distance from the nearest fold (edges are where the film is tight)
        ex = 1 - abs(x) / (HW + g)
        ey = 1 - abs(y) / (HD + g)
        ez = 1 - abs(z) / (HH + g)
        if abs(abs(y) - (HD + g)) < 1e-6:          # front/back faces
            free = min(ex, ez) * 4.0
            n = Vector((0, math.copysign(1, y), 0))
        elif abs(abs(x) - (HW + g)) < 1e-6:        # spine / open side
            free = min(ey, ez) * 4.0
            n = Vector((math.copysign(1, x), 0, 0))
        else:                                       # ends
            free = min(ex, ey) * 4.0
            n = Vector((0, 0, math.copysign(1, z)))
        free = min(1.0, free)
        pocket = 0.5 + 0.5 * math.sin(x * 0.11 + phase[0]) * math.sin(z * 0.07 + phase[1])
        pocket += 0.3 * math.sin(x * 0.31 + z * 0.23 + phase[2])
        v.co += n * free * max(0.0, pocket) * 0.45
    bm.normal_update()
    obj = geo.to_object(bm, "VHS_Film")
    obj.scale = (MM, MM, MM)
    geo.add_bevel(obj, 1.1, segments=3, angle_deg=40.0, profile=0.7, name="Shrunk")
    obj.data.materials.append(mats.cached("SHRINK_FILM", lambda: mats.film("SHRINK_FILM")))
    return obj


def bake_uv(obj: bpy.types.Object) -> None:
    """Non-overlapping UVs for baking (applied after modifiers at export)."""
    mesh = obj.data
    if mats.BAKE_UV not in mesh.uv_layers:
        mesh.uv_layers.new(name=mats.BAKE_UV)


def materials_dict() -> dict:
    """Built once per scene; every sleeve instance shares the set."""
    existing = bpy.data.materials.get("COVER_ART")
    if existing is not None and "nc_sleeve_set" in existing:
        return {k: bpy.data.materials[v] for k, v in existing["nc_sleeve_set"].items()}
    built = _build_materials()
    built["COVER_ART"]["nc_sleeve_set"] = {k: m.name for k, m in built.items()}
    return built


def _build_materials() -> dict:
    cover = mats.Print(ink_roughness=0.42, coat=0.55, coat_roughness=0.2, wear=0.6)
    return {
        "COVER_BACK": mats.label("COVER_BACK", cover),
        "LABEL_SPINE": mats.label("LABEL_SPINE", cover),
        "COVER_ART": mats.label("COVER_ART", cover),
        # ends carry the spine's edge colour (see _uv_*), more worn: they
        # are what hands and shelves rub against
        "SLEEVE_PRINT_END": mats.label("SLEEVE_PRINT_END", mats.Print(
            ink_roughness=0.6, coat=0.4, coat_roughness=0.42, wear=1.0, dust=0.6)),
        "SLEEVE_BOARD": mats.matte("SLEEVE_BOARD", (0.60, 0.58, 0.54, 1.0), roughness=0.9, bump=0.15),
        "SLEEVE_EDGE": mats.matte("SLEEVE_EDGE", (0.42, 0.37, 0.30, 1.0), roughness=0.95, bump=0.3,
                                  bump_scale=4000.0),
    }


def build(collection=None, *, seed: int = 7, with_cassette: bool = True,
          progress: float = 0.35) -> bpy.types.Object:
    m = materials_dict()
    obj = build_mesh(seed)
    for name in ("COVER_BACK", "LABEL_SPINE", "COVER_ART", "SLEEVE_PRINT_END", "SLEEVE_BOARD", "SLEEVE_EDGE"):
        obj.data.materials.append(m[name])
    root = bpy.data.objects.new("VHS_SleeveRoot", None)
    (collection or bpy.context.scene.collection).objects.link(root)
    obj.parent = root
    if with_cassette:
        from assets import cassette
        tape = cassette.build(collection, progress=progress)
        # cassette X -> sleeve Z, cassette Y -> sleeve -X (its spine label
        # faces the open side), cassette Z -> sleeve -Y (face label toward
        # the front cover); centred in the sleeve, nudged 0.6 mm toward the
        # opening.
        from mathutils import Matrix
        rot = Matrix(((0, -1, 0), (0, 0, -1), (1, 0, 0))).to_4x4()
        tape.matrix_world = (Matrix.Translation((0.6 * MM, 0, 0)) @ rot
                             @ Matrix.Translation((0, 0, -12.5 * MM)))
        tape.parent = root
        root["nc_cassette"] = tape.name
    root["nc_size_mm"] = (SLEEVE_W, SLEEVE_H, SLEEVE_D)
    return root
