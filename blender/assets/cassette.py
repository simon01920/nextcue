"""VHS cassette at real-world scale (188 x 104 x 25 mm).

Frame: X = length (188), Y = depth with -Y the spine/label edge and +Y the
dust door, Z = thickness with the face label on top (+Z). Built from a
lattice-box shell with extruded recesses and grooves; round features (window,
hub holes, screw holes) are cut by deleting a block of quads and bridging
its boundary loop to a circle/rounded-rect loop of the same vertex count, so
the whole shell stays quad topology.
"""

from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from nc import MM
from nc import geo, mats
from nc.atlas import HERO

L, D, T = 188.0, 104.0, 25.0          # mm
HX, HY = L / 2, D / 2
REEL_X, REEL_Y = 47.0, 9.0            # reel centres (94 mm spindle pitch)
HUB_R, PACK_MAX_R = 13.0, 37.5        # tape winds from hub to max radius
TAPE_W = 12.65                        # 1/2" tape
SEAM_Z = (9.8, 10.2)
CORNER_R = 2.0                        # plan radius of the vertical corners

FACE_LABEL = (-40.0, 40.0, -48.5, -4.5)       # x0, x1, y0, y1 on the top face
WINDOW = (-52.0, 52.0, -0.5, 27.5)            # x0, x1, y0, y1
SPINE_LABEL = (-74.0, 74.0, 2.5, 22.5)        # x0, x1, z0, z1 on the back face
DOOR = (-78.0, 78.0, 1.6, 23.4)               # x0, x1, z0, z1 on the front face
TAB = (-89.0, -79.5, 7.5, 17.5)               # write-protect tab on the back face
HUB_HOLE_R = 13.6
SCREWS = [(-83.5, -40.5), (83.5, -40.5), (-83.5, 41.0), (83.5, 41.0), (0.0, 44.0)]
SCREW_R = 2.7


def pack_radius(fraction: float) -> float:
    """Outer radius of a pack holding `fraction` of the tape (area-true)."""
    full = PACK_MAX_R ** 2 - HUB_R ** 2
    return math.sqrt(HUB_R ** 2 + max(0.0, min(1.0, fraction)) * full)


# --------------------------------------------------------------------------

def _cuts_around(c: float, half: float, n: int) -> list[float]:
    return [c - half + 2 * half * i / n for i in range(n + 1)]


def _shell_lattice():
    xs = {-HX, HX}
    ys = {-HY, HY}
    zs = {0.0, T}
    # face label recess, window block, door, spine label, tab
    xs |= {FACE_LABEL[0], FACE_LABEL[1]}
    ys |= {FACE_LABEL[2], FACE_LABEL[3]}
    # window: a block of quads whose boundary has as many verts as the loop
    wx = _cuts_around(0.0, 54.0, 24)
    wy = _cuts_around(13.5, 15.0, 6)
    xs |= set(wx)
    ys |= set(wy)
    xs |= {SPINE_LABEL[0], SPINE_LABEL[1], DOOR[0] - 0.5, DOOR[0], DOOR[1], DOOR[1] + 0.5}
    zs |= {SPINE_LABEL[2], SPINE_LABEL[3], DOOR[2] - 0.5, DOOR[2], DOOR[3], DOOR[3] + 0.5}
    xs |= {TAB[0], TAB[1]}
    zs |= {TAB[2], TAB[3], *SEAM_Z}
    # tape-path openings either side of the door
    xs |= {-91.0, -82.5, 82.5, 91.0}
    zs |= {4.5, 18.5}
    # grip ridges on both sides near the spine corners
    ridge_y = [-46.0 + 1.3 * i for i in range(19)]
    ys |= set(ridge_y)
    zs |= {5.0, 20.0}
    # bottom: hub holes and screw holes (square blocks for bridging)
    hub_cuts = []
    for sx in (-1, 1):
        cx = sx * REEL_X
        xs |= set(_cuts_around(cx, 16.0, 8))
        ys |= set(_cuts_around(REEL_Y, 16.0, 8))
    for sx, sy in SCREWS:
        xs |= set(_cuts_around(sx, 4.0, 4))
        ys |= set(_cuts_around(sy, 4.0, 4))
    return sorted(xs), sorted(ys), sorted(zs), ridge_y


def _bridge_hole(bm, faces, project, depth: float):
    """Cut a hole into a planar block of quads.

    The block's boundary loop is kept; every boundary vertex is projected
    radially onto the hole outline by ``project(angle) -> (x, y)``, giving an
    inner loop with the same vertex count, and the two loops are bridged with
    quads. The inner loop is then extruded by ``depth`` along Z (negative =
    down) to form the hole wall. Returns (ring_faces, wall_faces)."""
    z = faces[0].calc_center_median().z
    face_set = set(faces)
    boundary_edges = {e for f in faces for e in f.edges
                      if sum(1 for lf in e.link_faces if lf in face_set) == 1}
    bmesh.ops.delete(bm, geom=list(faces), context="FACES_KEEP_BOUNDARY")
    loop = _order_loop(boundary_edges)                      # CCW in XY
    cx = sum(v.co.x for v in loop) / len(loop)
    cy = sum(v.co.y for v in loop) / len(loop)
    inner = []
    for v in loop:
        x, y = project(math.atan2(v.co.y - cy, v.co.x - cx))
        inner.append(bm.verts.new((x, y, z)))
    n = len(loop)
    ring = [bm.faces.new((loop[i], loop[(i + 1) % n], inner[(i + 1) % n], inner[i])) for i in range(n)]
    inner_set = set(inner)
    res = bmesh.ops.extrude_edge_only(bm, edges=[e for e in bm.edges
                                                 if e.verts[0] in inner_set and e.verts[1] in inner_set])
    for v in (g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)):
        v.co.z += depth
    bm.normal_update()
    return ring, [f for f in res["geom"] if isinstance(f, bmesh.types.BMFace)]


def _order_loop(edges):
    edges = set(edges)
    adj = {}
    for e in edges:
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    start = next(iter(adj))
    loop = [start]
    prev = None
    cur = start
    while True:
        nxt = [v for v in adj[cur] if v is not prev]
        if not nxt:
            break
        nv = nxt[0] if nxt[0] is not start or len(loop) > 2 else (nxt[1] if len(nxt) > 1 else nxt[0])
        if nv is start:
            break
        loop.append(nv)
        prev, cur = cur, nv
    # counter-clockwise in XY
    area = 0.0
    for i in range(len(loop)):
        a, b = loop[i].co, loop[(i + 1) % len(loop)].co
        area += a.x * b.y - b.x * a.y
    if area < 0:
        loop.reverse()
    return loop


def circle_projector(cx: float, cy: float, r: float):
    return lambda a: (cx + r * math.cos(a), cy + r * math.sin(a))


def rounded_rect_projector(x0: float, x1: float, y0: float, y1: float, r: float):
    """Ray from the rect centre at angle a, intersected with the rounded rect
    (signed-distance bisection)."""
    w, h = x1 - x0, y1 - y0
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2

    def sdf(px: float, py: float) -> float:
        qx, qy = abs(px) - (w / 2 - r), abs(py) - (h / 2 - r)
        return (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** 0.5 + min(max(qx, qy), 0) - r

    def project(a: float):
        dx, dy = math.cos(a), math.sin(a)
        lo, hi = 0.0, w + h
        for _ in range(48):
            mid = (lo + hi) / 2
            if sdf(dx * mid, dy * mid) <= 0:
                lo = mid
            else:
                hi = mid
        return cx + dx * lo, cy + dy * lo

    return project


# --------------------------------------------------------------------------

def build_shell(materials) -> bpy.types.Object:
    xs, ys, zs, ridge_y = _shell_lattice()
    bm = geo.lattice_box(xs, ys, zs)

    top = lambda pred: geo.faces_where(bm, (0, 0, 1), pred)
    bottom = lambda pred: geo.faces_where(bm, (0, 0, -1), pred)
    back = lambda pred: geo.faces_where(bm, (0, -1, 0), pred)
    front = lambda pred: geo.faces_where(bm, (0, 1, 0), pred)

    # Face label recess (0.45 mm)
    x0, x1, y0, y1 = FACE_LABEL
    geo.extrude_along_normals(bm, top(lambda c: x0 < c.x < x1 and y0 < c.y < y1), -0.45)

    # Spine label recess on the back edge
    x0, x1, z0, z1 = SPINE_LABEL
    geo.extrude_along_normals(bm, back(lambda c: x0 < c.x < x1 and z0 < c.z < z1), -0.45)

    # Write-protect tab: recessed outline reads as a breakable tab
    x0, x1, z0, z1 = TAB
    geo.extrude_along_normals(bm, back(lambda c: x0 < c.x < x1 and z0 < c.z < z1), -0.3)

    # Door: a 0.5 mm groove around a slightly recessed panel
    x0, x1, z0, z1 = DOOR
    groove = front(lambda c: (x0 - 0.5 < c.x < x1 + 0.5 and z0 - 0.5 < c.z < z1 + 0.5)
                   and not (x0 < c.x < x1 and z0 < c.z < z1))
    geo.extrude_along_normals(bm, groove, -1.2)
    geo.extrude_along_normals(bm, front(lambda c: x0 < c.x < x1 and z0 < c.z < z1 and c.y > HY - 0.01), -0.15)

    # Tape-path openings either side of the door
    for a, b in ((-91.0, -82.5), (82.5, 91.0)):
        geo.extrude_along_normals(bm, front(lambda c, a=a, b=b: a < c.x < b and 4.5 < c.z < 18.5), -2.5)

    # Seam between the shell halves on the long sides. It stops short of the
    # rounded vertical corners: a groove wrapped around a beveled corner
    # gives the bevel modifier degenerate short edges and spikes.
    def seam_pred(c):
        if not (SEAM_Z[0] < c.z < SEAM_Z[1]):
            return False
        return abs(c.x) > HX - 0.01 and abs(c.y) < HY - CORNER_R - 2.0
    seam = [f for f in bm.faces if abs(f.normal.z) < 0.1 and seam_pred(f.calc_center_median())]
    geo.extrude_along_normals(bm, seam, -0.35)

    # Grip ridges near the spine corners (alternate strips raised 0.3 mm).
    # The seam groove already runs through this zone, so skip its band.
    strips = []
    for i in range(0, len(ridge_y) - 1, 2):
        a, b = ridge_y[i], ridge_y[i + 1]
        for f in bm.faces:
            c = f.calc_center_median()
            if (abs(abs(f.normal.x) - 1) < 0.05 and abs(c.x) > HX - 0.01 and a < c.y < b
                    and 5.0 < c.z < 20.0 and not (SEAM_Z[0] < c.z < SEAM_Z[1])):
                strips.append(f)
    geo.extrude_along_normals(bm, strips, 0.3)

    # Window: rounded opening bridged from the block of top quads under it.
    wfaces = top(lambda c: -54.0 < c.x < 54.0 and -1.5 < c.y < 28.5)
    _bridge_hole(bm, wfaces, rounded_rect_projector(*WINDOW, 6.0), -2.0)

    # Bottom: hub holes and screw holes, walls going up into the shell.
    for sx in (-1, 1):
        cx = sx * REEL_X
        hf = bottom(lambda c, cx=cx: abs(c.x - cx) < 16.0 and abs(c.y - REEL_Y) < 16.0)
        _bridge_hole(bm, hf, circle_projector(cx, REEL_Y, HUB_HOLE_R), 1.8)
    for sx, sy in SCREWS:
        sf = bottom(lambda c, sx=sx, sy=sy: abs(c.x - sx) < 4.0 and abs(c.y - sy) < 4.0)
        _bridge_hole(bm, sf, circle_projector(sx, sy, SCREW_R), 2.2)

    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Finish zones: stippled matte on the big faces, smooth gloss on the
    # sides, the door and a band around the window (like real shells).
    for f in bm.faces:
        c = f.calc_center_median()
        on_top_or_bottom = abs(f.normal.z) > 0.9 and (c.z > T - 0.6 or c.z < 0.6)
        near_window = (WINDOW[0] - 3.0 < c.x < WINDOW[1] + 3.0 and WINDOW[2] - 3.0 < c.y < WINDOW[3] + 3.0)
        f.material_index = 0 if on_top_or_bottom and not near_window else 1
    obj = geo.to_object(bm, "VHS_Shell")
    obj.scale = (MM, MM, MM)

    # Vertical outer corners get a plan radius; everything else a fine edge.
    def corner(a, b):
        on = lambda p: abs(p.x) > HX - 0.01 and abs(p.y) > HY - 0.01
        return on(a) and on(b) and abs(a.z - b.z) > 0.01
    geo.set_bevel_weights(obj, corner)
    geo.add_bevel(obj, CORNER_R, segments=6, limit="WEIGHT", profile=0.5, harden=False, name="CornerRadius")
    geo.add_bevel(obj, 0.45, segments=3, angle_deg=40.0, profile=0.6, name="EdgeBevel")
    geo.add_weighted_normals(obj)
    obj.data.materials.append(materials["shell"])
    obj.data.materials.append(materials["shell_gloss"])
    return obj


def build_lettering(materials) -> list[bpy.types.Object]:
    """Moulded lettering: brand on the door, format marks on the top face."""
    from nc.paths import ROOT
    anton = str(ROOT / "assets" / "fonts" / "Anton-Regular.ttf")
    figtree = str(ROOT / "assets" / "fonts" / "Figtree-Bold.ttf")
    out = []
    specs = [
        # text, font, size, (x, y, z), frame, spacing
        # Seen from +Y the viewer's right is -X, so the brand sits at +X.
        ("NEXTCUE", anton, 6.0, (12.0, HY + 0.02, 12.5), "front", 1.25),
        ("HG", anton, 6.0, (-9.0, HY + 0.02, 12.5), "front", 1.1),
        ("T-120", figtree, 3.4, (60.0, 41.0, T + 0.02), "top", 1.15),
        ("VHS", anton, 5.0, (-62.0, 41.0, T + 0.02), "top", 1.3),
    ]
    for i, (txt, font, size, loc, frame, spacing) in enumerate(specs):
        o = geo.text_mesh(txt, font_path=font, size=size, extrude=0.06, bevel=0.03,
                          name=f"VHS_Letter{i}", letter_spacing=spacing)
        if frame == "front":
            # text plane XY -> world XZ, reading along +X... seen from +Y.
            o.rotation_euler = (math.pi / 2, 0, math.pi)
        o.location = (loc[0] * MM, loc[1] * MM, loc[2] * MM)
        o.scale = (MM, MM, MM)
        o.data.materials.append(materials["shell_gloss"] if frame == "front" else materials["shell"])
        out.append(o)
    return out


def build_window(materials) -> bpy.types.Object:
    bm = bmesh.new()
    w, h = WINDOW[1] - WINDOW[0] + 0.6, WINDOW[3] - WINDOW[2] + 0.6
    geo.rounded_slab(bm, w, h, 1.0, 6.3, segments=8, z=T - 0.8)
    bmesh.ops.translate(bm, vec=(0, (WINDOW[2] + WINDOW[3]) / 2, 0), verts=bm.verts[:])
    obj = geo.to_object(bm, "VHS_Window")
    obj.scale = (MM, MM, MM)
    geo.add_bevel(obj, 0.25, segments=2, angle_deg=40.0, name="EdgeBevel")
    obj.data.materials.append(materials["window"])
    return obj


def build_reel(name: str, cx: float, cy: float, fraction: float, materials) -> list[bpy.types.Object]:
    objs = []
    z0 = 2.0
    # lower flange (opaque white) and upper flange (clear)
    bm = bmesh.new()
    geo.cylinder(bm, 39.0, 0.8, segments=96, center=(0, 0, z0 + 0.4), inner_radius=HUB_R - 2.0)
    o = geo.to_object(bm, name + "_FlangeLow")
    o.data.materials.append(materials["hub"])
    objs.append(o)
    bm = bmesh.new()
    geo.cylinder(bm, 39.0, 0.6, segments=96, center=(0, 0, z0 + 0.8 + TAPE_W + 0.6), inner_radius=HUB_R - 2.0)
    o = geo.to_object(bm, name + "_FlangeHigh")
    o.data.materials.append(materials["flange"])
    objs.append(o)
    # tape pack
    r = pack_radius(fraction)
    bm = bmesh.new()
    geo.cylinder(bm, r, TAPE_W, segments=128, center=(0, 0, z0 + 0.8 + TAPE_W / 2 + 0.05),
                 inner_radius=HUB_R - 0.01)
    o = geo.to_object(bm, name + "_Tape")
    o.data.materials.append(materials["tape"])
    objs.append(o)
    # hub: tube with drive splines and a slotted cap
    bm = bmesh.new()
    geo.cylinder(bm, HUB_R, TAPE_W + 3.5, segments=64, center=(0, 0, z0 + (TAPE_W + 3.5) / 2 - 0.4),
                 inner_radius=9.4)
    for k in range(6):
        a = 2 * math.pi * k / 6
        tooth = bmesh.new()
        tf = geo.cylinder(tooth, 0.9, TAPE_W + 2.0, segments=8,
                          center=(math.cos(a) * 9.0, math.sin(a) * 9.0, z0 + (TAPE_W + 2.0) / 2))
        tmesh = bpy.data.meshes.new("t")
        tooth.to_mesh(tmesh)
        tooth.free()
        bm.from_mesh(tmesh)
        bpy.data.meshes.remove(tmesh)
    o = geo.to_object(bm, name + "_Hub")
    o.data.materials.append(materials["hub"])
    objs.append(o)
    # cap with six windows (spokes) seen through the clear flange
    bm = bmesh.new()
    geo.cylinder(bm, 9.4, 0.8, segments=48, center=(0, 0, z0 + TAPE_W + 2.6), inner_radius=3.2)
    o = geo.to_object(bm, name + "_Cap")
    o.data.materials.append(materials["hub"])
    objs.append(o)
    for o in objs:
        o.location = (cx * MM, cy * MM, 0)
        o.scale = (MM, MM, MM)
        geo.add_bevel(o, 0.15, segments=2, angle_deg=40.0, harden=False)
    return objs


def build_screws(materials) -> list[bpy.types.Object]:
    """Pan-head screws seated at the top of each bottom recess, head facing
    down; the Phillips cross is a pair of dark bars just under the head."""
    out = []
    for i, (sx, sy) in enumerate(SCREWS):
        bm = bmesh.new()
        geo.cylinder(bm, SCREW_R - 0.35, 0.8, segments=24, center=(0, 0, 1.8))
        head = geo.to_object(bm, f"VHS_Screw{i}")
        head.data.materials.append(materials["screw"])
        cross = bmesh.new()
        for ang in (0.0, math.pi / 2):
            bar = bmesh.ops.create_cube(cross, size=1.0)
            vs = bar["verts"]
            bmesh.ops.scale(cross, vec=(3.0, 0.5, 0.12), verts=vs)
            bmesh.ops.rotate(cross, matrix=Matrix.Rotation(ang, 3, "Z"), verts=vs, cent=(0, 0, 0))
            bmesh.ops.translate(cross, vec=(0, 0, 1.36), verts=vs)
        slot = geo.to_object(cross, f"VHS_ScrewSlot{i}", smooth=False)
        slot.data.materials.append(materials["screw_slot"])
        for o in (head, slot):
            o.location = (sx * MM, sy * MM, 0)
            o.scale = (MM, MM, MM)
        geo.add_bevel(head, 0.15, segments=2, angle_deg=40.0, harden=False)
        out += [head, slot]
    return out


def _sticker(name: str, w: float, h: float, region, materials, *, frame: Matrix) -> bpy.types.Object:
    """Paper sticker w x h mm whose outward face maps into atlas region."""
    bm = bmesh.new()
    faces = geo.rounded_slab(bm, w, h, 0.14, 0.9, segments=4, z=0.07)
    top = faces[0]
    uv_hero = bm.loops.layers.uv.new(mats.LABEL_UV_HERO)
    uv_bake = bm.loops.layers.uv.new(mats.BAKE_UV)
    for f in bm.faces:
        for loop in f.loops:
            u = (loop.vert.co.x + w / 2) / w
            v = (loop.vert.co.y + h / 2) / h
            loop[uv_hero].uv = region.uv(u, v)
            loop[uv_bake].uv = (u, v)
    for f in bm.faces:
        f.material_index = 0 if f is top else 1
    obj = geo.to_object(bm, name)
    obj.data.materials.append(materials[name])
    obj.data.materials.append(materials["paper_edge"])
    obj.matrix_world = frame
    return obj


def build_labels(materials) -> list[bpy.types.Object]:
    x0, x1, y0, y1 = FACE_LABEL
    face_frame = (Matrix.Translation(((x0 + x1) / 2 * MM, (y0 + y1) / 2 * MM, (T - 0.45) * MM))
                  @ Matrix.Diagonal((MM, MM, MM, 1)))
    face = _sticker("LABEL_FRONT", x1 - x0 - 1.0, y1 - y0 - 1.0, HERO["cassette_face"], materials,
                    frame=face_frame)
    x0, x1, z0, z1 = SPINE_LABEL
    # spine sticker lies on the back face: local +Z -> world -Y, local +Y -> world +Z
    rot = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    spine_frame = (Matrix.Translation((0, (-HY + 0.45) * MM, (z0 + z1) / 2 * MM)) @ rot
                   @ Matrix.Diagonal((MM, MM, MM, 1)))
    spine = _sticker("LABEL_TAPE_SPINE", x1 - x0 - 1.0, z1 - z0 - 1.0, HERO["cassette_spine"], materials,
                     frame=spine_frame)
    return [face, spine]


def materials_dict() -> dict:
    return {
        "shell": mats.plastic("VHS_Shell", mats.Plastic(roughness=0.48, rough_var=0.08, stipple=0.9,
                                                        scratch=0.3, seed=1.0)),
        "shell_gloss": mats.plastic("VHS_ShellGloss", mats.Plastic(roughness=0.2, rough_var=0.06,
                                                                   stipple=0.0, scratch=0.45, seed=2.0)),
        "window": mats.clear_plastic("VHS_Window", tint=(0.86, 0.88, 0.9, 1.0), roughness=0.02),
        "flange": mats.clear_plastic("VHS_Flange", tint=(0.95, 0.96, 0.97, 1.0), roughness=0.06, dust=0.1),
        "hub": mats.hub_plastic("VHS_Hub", color=(0.84, 0.84, 0.82, 1.0), roughness=0.35),
        "tape": mats.tape_pack("VHS_Tape"),
        "screw": mats.metal("VHS_Screw", color=(0.70, 0.71, 0.70, 1.0), roughness=0.32),
        "screw_slot": mats.matte("VHS_ScrewSlot", (0.02, 0.02, 0.02, 1.0), roughness=0.6),
        "LABEL_FRONT": mats.label("LABEL_FRONT", mats.Print(ink_roughness=0.82, coat=0.0, wear=0.3)),
        "LABEL_TAPE_SPINE": mats.label("LABEL_TAPE_SPINE", mats.Print(ink_roughness=0.82, coat=0.0, wear=0.3)),
        "paper_edge": mats.matte("VHS_PaperEdge", (0.78, 0.76, 0.72, 1.0), roughness=0.85),
    }


def build(collection=None, *, progress: float = 0.35) -> bpy.types.Object:
    """Build the cassette and parent everything to an empty 'VHS_Cassette'.
    progress = fraction of tape already on the take-up (right) reel."""
    materials = materials_dict()
    root = bpy.data.objects.new("VHS_Cassette", None)
    (collection or bpy.context.scene.collection).objects.link(root)
    parts = [build_shell(materials), build_window(materials)]
    parts += build_reel("VHS_ReelL", -REEL_X, REEL_Y, 1.0 - progress, materials)
    parts += build_reel("VHS_ReelR", REEL_X, REEL_Y, progress, materials)
    parts += build_screws(materials)
    parts += build_labels(materials)
    parts += build_lettering(materials)
    for p in parts:
        if collection is not None and p.name in bpy.context.scene.collection.objects:
            bpy.context.scene.collection.objects.unlink(p)
            collection.objects.link(p)
        p.parent = root
    root["nc_size_mm"] = (L, D, T)
    return root
