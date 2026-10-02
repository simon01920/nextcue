"""Mesh construction helpers.

Hard-surface parts are built as *lattice boxes*: the surface of a box cut
into quads at every feature boundary. Recesses, grooves and raised panels
are extrusions of rectangular quad regions, and edges are rounded by bevel
modifiers. The result is quad-only topology with no booleans.
"""

from __future__ import annotations

import math
from typing import Callable, Iterable, Sequence

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import MM

AXES = {"x": 0, "y": 1, "z": 2}


# --------------------------------------------------------------------------
# Lattice box
# --------------------------------------------------------------------------

def lattice_box(xs: Sequence[float], ys: Sequence[float], zs: Sequence[float]) -> bmesh.types.BMesh:
    """Closed box surface with quad faces at the given sorted cut coordinates.

    The first and last entry of each list are the box bounds; inner entries
    are extra cuts. Units are whatever the caller uses (metres here).
    """
    xs, ys, zs = sorted(set(xs)), sorted(set(ys)), sorted(set(zs))
    bm = bmesh.new()
    verts: dict[tuple[int, int, int], bmesh.types.BMVert] = {}
    nx, ny, nz = len(xs), len(ys), len(zs)

    def v(i, j, k):
        key = (i, j, k)
        if key not in verts:
            verts[key] = bm.verts.new((xs[i], ys[j], zs[k]))
        return verts[key]

    def quad(a, b, c, d):
        bm.faces.new((a, b, c, d))

    # x faces
    for i in (0, nx - 1):
        for j in range(ny - 1):
            for k in range(nz - 1):
                quad(v(i, j, k), v(i, j + 1, k), v(i, j + 1, k + 1), v(i, j, k + 1))
    # y faces
    for j in (0, ny - 1):
        for i in range(nx - 1):
            for k in range(nz - 1):
                quad(v(i, j, k), v(i + 1, j, k), v(i + 1, j, k + 1), v(i, j, k + 1))
    # z faces
    for k in (0, nz - 1):
        for i in range(nx - 1):
            for j in range(ny - 1):
                quad(v(i, j, k), v(i + 1, j, k), v(i + 1, j + 1, k), v(i, j + 1, k))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    return bm


def faces_where(bm, normal, predicate: Callable[[Vector], bool], tol: float = 0.95):
    """Faces whose normal points along `normal` and whose centre passes predicate."""
    n = Vector(normal).normalized()
    out = []
    for f in bm.faces:
        if f.normal.dot(n) >= tol and predicate(f.calc_center_median()):
            out.append(f)
    return out


def in_rect(axis_a: str, lo_a: float, hi_a: float, axis_b: str, lo_b: float, hi_b: float):
    ia, ib = AXES[axis_a], AXES[axis_b]

    def pred(c: Vector) -> bool:
        return lo_a <= c[ia] <= hi_a and lo_b <= c[ib] <= hi_b

    return pred


def extrude_along_normals(bm, faces, distance: float):
    """Extrude a face region and move each new vertex along the summed normals
    of the extruded faces it belongs to. Negative distance pushes inward
    (recess/groove), positive pulls outward (raised panel). Corners where two
    sides meet move along both normals, so wrapped grooves keep square walls.
    """
    if not faces:
        return []
    # Distinct face normals touching each region vertex, keyed by position:
    # extrude_face_region duplicates the region, so new verts start exactly
    # where their originals were.
    by_pos: dict[tuple, dict[tuple, Vector]] = {}
    for f in faces:
        nkey = tuple(round(c, 3) for c in f.normal)
        for vtx in f.verts:
            by_pos.setdefault(_pkey(vtx.co), {})[nkey] = f.normal.copy()
    res = bmesh.ops.extrude_face_region(bm, geom=list(faces))
    # Unlike the interactive extrude, the op keeps the original faces in
    # place; remove them (and their now-unused interior verts/edges) or the
    # region is left behind as a flipped duplicate layer.
    bmesh.ops.delete(bm, geom=list(faces), context="FACES")
    for nv in (e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)):
        normals = by_pos.get(_pkey(nv.co))
        if normals:
            nv.co += sum(normals.values(), Vector()) * distance
    bm.normal_update()
    return [e for e in res["geom"] if isinstance(e, bmesh.types.BMFace) and e.is_valid]


def _pkey(co) -> tuple:
    return (round(co[0], 7), round(co[1], 7), round(co[2], 7))


def remove_faces(bm, faces) -> None:
    bmesh.ops.delete(bm, geom=list(faces), context="FACES_ONLY")


# --------------------------------------------------------------------------
# Primitive solids (quad topology)
# --------------------------------------------------------------------------

def cylinder(bm, radius: float, height: float, *, segments: int = 48,
             center=(0, 0, 0), cap_top: bool = True, cap_bottom: bool = True,
             inner_radius: float | None = None, axis: str = "z"):
    """Cylinder or tube (inner_radius) along an axis, centred at center.
    Caps are quad rings when inner_radius is given, else triangle-free
    n-gon caps (flat, so shading is exact)."""
    cx, cy, cz = center
    h = height / 2
    ring_out_b, ring_out_t, ring_in_b, ring_in_t = [], [], [], []
    for s in range(segments):
        a = 2 * math.pi * s / segments
        ca, sa = math.cos(a), math.sin(a)
        ring_out_b.append(bm.verts.new((radius * ca, radius * sa, -h)))
        ring_out_t.append(bm.verts.new((radius * ca, radius * sa, h)))
        if inner_radius:
            ring_in_b.append(bm.verts.new((inner_radius * ca, inner_radius * sa, -h)))
            ring_in_t.append(bm.verts.new((inner_radius * ca, inner_radius * sa, h)))
    faces = []
    for s in range(segments):
        n = (s + 1) % segments
        faces.append(bm.faces.new((ring_out_b[s], ring_out_b[n], ring_out_t[n], ring_out_t[s])))
        if inner_radius:
            faces.append(bm.faces.new((ring_in_b[n], ring_in_b[s], ring_in_t[s], ring_in_t[n])))
            if cap_top:
                faces.append(bm.faces.new((ring_out_t[s], ring_out_t[n], ring_in_t[n], ring_in_t[s])))
            if cap_bottom:
                faces.append(bm.faces.new((ring_out_b[n], ring_out_b[s], ring_in_b[s], ring_in_b[n])))
    if not inner_radius:
        if cap_top:
            faces.append(bm.faces.new(ring_out_t))
        if cap_bottom:
            faces.append(bm.faces.new(list(reversed(ring_out_b))))
    verts = ring_out_b + ring_out_t + ring_in_b + ring_in_t
    rot = {"z": Matrix.Identity(4), "x": Matrix.Rotation(math.pi / 2, 4, "Y"),
           "y": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((cx, cy, cz)) @ rot, verts=verts)
    return faces


def rounded_rect_outline(w: float, h: float, r: float, segments: int = 6):
    """Points of a rounded rectangle centred at the origin (counter-clockwise)."""
    r = min(r, w / 2, h / 2)
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
               (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    for cx, cy, start in corners:
        for s in range(segments + 1):
            a = math.radians(start + 90 * s / segments)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def rounded_slab(bm, w: float, h: float, thickness: float, r: float, *,
                 segments: int = 6, z: float = 0.0):
    """Flat rounded-rectangle slab (window panes, labels, door panels)."""
    pts = rounded_rect_outline(w, h, r, segments)
    bottom = [bm.verts.new((x, y, z - thickness / 2)) for x, y in pts]
    top = [bm.verts.new((x, y, z + thickness / 2)) for x, y in pts]
    n = len(pts)
    faces = [bm.faces.new(top), bm.faces.new(list(reversed(bottom)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((bottom[i], bottom[j], top[j], top[i])))
    return faces


# --------------------------------------------------------------------------
# Objects and modifiers
# --------------------------------------------------------------------------

def to_object(bm, name: str, collection=None, smooth: bool = True) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def mark_sharp_by_angle(obj: bpy.types.Object, angle_deg: float = 30.0) -> None:
    """Mark edges sharper than the angle so smooth shading keeps them crisp
    (Blender 4.1+ uses the sharp_edge attribute instead of auto-smooth)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    limit = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle() < limit
        else:
            e.smooth = False
    bm.to_mesh(obj.data)
    bm.free()


def set_bevel_weights(obj, edge_predicate, weight: float = 1.0) -> None:
    mesh = obj.data
    attr = mesh.attributes.get("bevel_weight_edge") or mesh.attributes.new(
        "bevel_weight_edge", "FLOAT", "EDGE")
    verts = mesh.vertices
    for e in mesh.edges:
        a, b = verts[e.vertices[0]].co, verts[e.vertices[1]].co
        if edge_predicate(a, b):
            attr.data[e.index].value = weight


def add_bevel(obj, width: float, *, segments: int = 3, limit: str = "ANGLE",
              angle_deg: float = 30.0, profile: float = 0.6, harden: bool = True,
              name: str = "Bevel", clamp: bool = True):
    m = obj.modifiers.new(name, "BEVEL")
    m.width = width
    m.segments = segments
    m.profile = profile
    m.limit_method = limit
    if limit == "ANGLE":
        m.angle_limit = math.radians(angle_deg)
    m.use_clamp_overlap = clamp
    m.harden_normals = harden
    m.miter_outer = "MITER_ARC"
    return m


def add_weighted_normals(obj):
    m = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    m.keep_sharp = True
    m.weight = 50
    return m


def apply_modifiers(obj) -> None:
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=m.name)


def assign_material(obj, mat, faces_predicate=None) -> int:
    """Append a material slot; assign to all faces or those passing predicate
    (predicate gets the polygon). Returns the slot index."""
    mesh = obj.data
    if mat.name not in [m.name for m in mesh.materials if m]:
        mesh.materials.append(mat)
    idx = [m.name if m else None for m in mesh.materials].index(mat.name)
    for p in mesh.polygons:
        if faces_predicate is None or faces_predicate(p):
            p.material_index = idx
    return idx


def text_mesh(text: str, *, font_path: str | None = None, size: float = 5.0, extrude: float = 0.1,
              bevel: float = 0.02, align: str = "CENTER", name: str = "Text",
              letter_spacing: float = 1.0) -> bpy.types.Object:
    """Embossed lettering as a real mesh (sizes in the caller's units)."""
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = text
    if font_path:
        curve.font = bpy.data.fonts.load(font_path, check_existing=True)
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = bevel
    curve.bevel_resolution = 1
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.space_character = letter_spacing
    tmp = bpy.data.objects.new(name + "_curve", curve)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(curve)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = False
    return obj


def join(objects: Iterable[bpy.types.Object], name: str) -> bpy.types.Object:
    objects = list(objects)
    ctx = {"active_object": objects[0], "selected_editable_objects": objects,
           "object": objects[0]}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.join()
    objects[0].name = name
    objects[0].data.name = name
    return objects[0]
