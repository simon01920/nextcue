"""DVD keep case (Amaray-style), 135 x 190 x 14 mm.

Frame: X = width with the spine (living hinge) at -X and the opening at +X,
Y = depth with the front cover facing -Y, Z = height (same convention as the
VHS sleeve, so the shelf code can stand either).

The shell is a quad lattice whose four face corners are rounded by an
elliptical square-to-disc remap of the corner cells, so the rounding stays
all quads. A shallow parting groove runs round the opening edges where the
two covers meet. The printed insert sits under a clear overwrap that wraps
front, spine and back, leaving a 2 mm moulded rim.

Material slots: SHELL, COVER_BACK, LABEL_SPINE, COVER_ART (labels, UV map
UV_LABEL_DVD into the "dvd" atlas), plus the separate OVERWRAP object.
"""

from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Vector

from nc import MM, geo, mats
from nc.atlas import DVD, DVD_D, DVD_H, DVD_W

HW, HD, HH = DVD_W / 2, DVD_D / 2, DVD_H / 2
R = 5.0              # face corner radius
RIM = 2.0            # moulded rim around the insert
SEAM = 0.45          # half-height of the parting groove
SEAM_DEPTH = 0.7
HINGE = 9.0          # the groove stops this far from the spine
UV_NAME = "UV_LABEL_DVD"


def _cuts(lo: float, hi: float, extra=()) -> list[float]:
    n = 4
    pts = {lo, hi, *extra}
    for i in range(n + 1):
        pts.add(lo + R * i / n)
        pts.add(hi - R * i / n)
    return sorted(pts)


def _round_corners(bm) -> None:
    """Map each corner cell onto a quarter disc (elliptical grid mapping)."""
    cx, cz = HW - R, HH - R
    for v in bm.verts:
        x, y, z = v.co
        if abs(x) <= cx + 1e-9 or abs(z) <= cz + 1e-9:
            continue
        a = (abs(x) - cx) / R
        b = (abs(z) - cz) / R
        a2 = a * math.sqrt(max(0.0, 1 - b * b / 2))
        b2 = b * math.sqrt(max(0.0, 1 - a * a / 2))
        v.co.x = math.copysign(cx + a2 * R, x)
        v.co.z = math.copysign(cz + b2 * R, z)


def _groove(bm, faces, depth: float) -> None:
    res = bmesh.ops.extrude_face_region(bm, geom=list(faces))
    normals = {}
    for f in faces:
        for vtx in f.verts:
            normals.setdefault(tuple(round(c, 5) for c in vtx.co), []).append(f.normal.copy())
    bmesh.ops.delete(bm, geom=list(faces), context="FACES")
    for nv in (e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)):
        ns = normals.get(tuple(round(c, 5) for c in nv.co))
        if ns:
            avg = sum(ns, Vector()).normalized()
            nv.co -= avg * depth
    bm.normal_update()


def build_shell() -> bpy.types.Object:
    xs = _cuts(-HW, HW, (-HW + RIM, HW - RIM, -HW + HINGE, 0.0))
    ys = sorted({-HD, -SEAM, SEAM, HD, -HD / 2, HD / 2})
    zs = _cuts(-HH, HH, (-HH + RIM, HH - RIM, 0.0))
    bm = geo.lattice_box(xs, ys, zs)
    bm.normal_update()

    # labels and UVs from the unrounded lattice (the art stays rectangular)
    uv = bm.loops.layers.uv.new(UV_NAME)
    for f in bm.faces:
        n = f.normal
        c = f.calc_center_median()
        inside_xz = abs(c.x) < HW - RIM and abs(c.z) < HH - RIM
        if n.y < -0.9 and inside_xz:
            f.material_index = 3                   # COVER_ART
        elif n.y > 0.9 and inside_xz:
            f.material_index = 1                   # COVER_BACK
        elif n.x < -0.9 and abs(c.z) < HH - RIM:
            f.material_index = 2                   # LABEL_SPINE
        else:
            f.material_index = 0                   # SHELL
        for loop in f.loops:
            x, y, z = loop.vert.co
            v = (z + HH) / DVD_H
            if n.y < -0.9:
                loop[uv].uv = DVD["front"].uv((x + HW) / DVD_W, v)
            elif n.y > 0.9:
                loop[uv].uv = DVD["back"].uv((HW - x) / DVD_W, v)
            elif n.x < -0.9:
                loop[uv].uv = DVD["spine"].uv((HD - y) / DVD_D, v)
            else:
                loop[uv].uv = DVD["spine"].uv(0.5, v)

    _round_corners(bm)
    bm.normal_update()
    seam = [f for f in bm.faces
            if abs(f.normal.y) < 0.2 and abs(f.calc_center_median().y) < SEAM
            and f.calc_center_median().x > -HW + HINGE]
    _groove(bm, seam, SEAM_DEPTH)
    obj = geo.to_object(bm, "DVD_Case")
    obj.scale = (MM, MM, MM)
    geo.add_bevel(obj, 0.4, segments=3, angle_deg=35.0, profile=0.6, name="Edges")
    geo.add_weighted_normals(obj)
    return obj


def build_overwrap(shell: bpy.types.Object) -> bpy.types.Object:
    """Clear sleeve over front, spine and back, 0.12 mm proud of the shell."""
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    keep = {f for f in bm.faces if abs(f.normal.y) > 0.9 or f.normal.x < -0.9}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.12
    obj = geo.to_object(bm, "DVD_Overwrap")
    obj.scale = (MM, MM, MM)
    geo.add_bevel(obj, 0.5, segments=2, angle_deg=35.0, name="Wrap")
    obj.data.materials.append(mats.cached("OVERWRAP", lambda: mats.film("OVERWRAP", crinkle=0.12,
                                                                         transmit=0.96)))
    return obj


def materials_dict() -> dict:
    existing = bpy.data.materials.get("COVER_ART")
    if existing is not None and "nc_dvd_set" in existing:
        return {k: bpy.data.materials[v] for k, v in existing["nc_dvd_set"].items()}
    insert = mats.Print(ink_roughness=0.55, coat=0.0, wear=0.2, uv_hero=UV_NAME, uv_spine=UV_NAME)
    built = {
        "SHELL": mats.plastic("SHELL", mats.Plastic(color=(0.012, 0.012, 0.013, 1.0), roughness=0.42,
                                                    rough_var=0.08, stipple=0.6, scratch=0.25, seed=9.0)),
        "COVER_BACK": mats.label("COVER_BACK", insert),
        "LABEL_SPINE": mats.label("LABEL_SPINE", insert),
        "COVER_ART": mats.label("COVER_ART", insert),
    }
    built["COVER_ART"]["nc_dvd_set"] = {k: m.name for k, m in built.items()}
    return built


def build(collection=None) -> bpy.types.Object:
    m = materials_dict()
    shell = build_shell()
    for name in ("SHELL", "COVER_BACK", "LABEL_SPINE", "COVER_ART"):
        shell.data.materials.append(m[name])
    wrap = build_overwrap(shell)
    root = bpy.data.objects.new("DVD_CaseRoot", None)
    (collection or bpy.context.scene.collection).objects.link(root)
    shell.parent = root
    wrap.parent = root
    root["nc_size_mm"] = (DVD_W, DVD_H, DVD_D)
    return root
