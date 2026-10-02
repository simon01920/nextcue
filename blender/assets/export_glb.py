"""GLB export: every asset as one glTF 2.0 binary with baked PBR textures.

glTF has no procedural shading, so each asset is realised (modifiers
applied, joined into one mesh in metres) and its procedural materials are
baked into three shared textures over a fresh non-overlapping UV_BAKE
layout:

  <asset>_base.jpg     base colour (sRGB)
  <asset>_orm.jpg      R ambient occlusion, G roughness, B metallic
  <asset>_normal.png   tangent-space normal (stipple, grain, scratches)

Label slots (COVER_ART, LABEL_SPINE, LABEL_FRONT …) are not baked: they keep
their names and their atlas UV map, with a neutral print colour, so a
viewer can bind per-title artwork to them. Clear plastics export as
KHR_materials_transmission.
"""

from __future__ import annotations

import time
from pathlib import Path

import bmesh
import bpy
import numpy as np

from nc import mats, scene
from nc.paths import CACHE, GLB_DIR


def _log(msg: str) -> None:
    print(f"[nc glb {time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------------------
# Realise and join
# ---------------------------------------------------------------------------

def _descendants(root) -> list[bpy.types.Object]:
    out = []
    stack = [root]
    while stack:
        o = stack.pop()
        if o.type == "MESH" and not o.hide_render:
            out.append(o)
        stack.extend(o.children)
    return out


def prepare(objects) -> list[bpy.types.Object]:
    """Apply modifiers and unparent, keeping each part in its own object
    space: the procedural patterns are defined in object coordinates (mm),
    so they must be baked before the parts are joined."""
    from nc import geo
    # matrix_world is only recomputed by a depsgraph update; objects whose
    # scale/parent were just set by script still report identity
    bpy.context.view_layer.update()
    # world matrices first: clearing a parent moves its children
    worlds = [o.matrix_world.copy() for o in objects]
    for o in objects:
        o.parent = None
    for o, mw in zip(objects, worlds):
        o.matrix_world = mw
    for o in objects:
        if o.data.users > 1:
            o.data = o.data.copy()
        geo.apply_modifiers(o)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o, do_unlink=True)
    return objects


def join_world(objects, name: str) -> bpy.types.Object:
    """Join into one object `name` whose mesh is in metres at the origin."""
    from mathutils import Matrix
    from nc import geo
    for o in objects:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    return geo.join(objects, name)


def bake_uv(objects, *, margin: float = 0.004) -> None:
    """Smart-project the faces to bake of all parts into one shared
    UV_BAKE layout (multi-object edit mode packs them together); label and
    clear faces are left out."""
    for o in objects:
        me = o.data
        if mats.BAKE_UV not in me.uv_layers:
            me.uv_layers.new(name=mats.BAKE_UV)
        me.uv_layers.active = me.uv_layers[mats.BAKE_UV]
    for o in bpy.context.scene.objects:
        o.select_set(o in objects)
    active = objects[0]
    bpy.context.view_layer.objects.active = active
    with bpy.context.temp_override(active_object=active, object=active, selected_objects=objects,
                                   selected_editable_objects=objects):
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        for o in objects:
            me = o.data
            slots = {i for i, m in enumerate(me.materials) if m is not None and _kind(m) == "bake"}
            bm = bmesh.from_edit_mesh(me)
            for f in bm.faces:
                f.select_set(f.material_index in slots)
            bmesh.update_edit_mesh(me)
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=margin, area_weight=0.0,
                                 correct_aspect=True, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------------------
# Baking
# ---------------------------------------------------------------------------

def _kind(mat) -> str:
    if mat.get("nc_label") is not None:
        return "label"
    if mat.get("nc_clear") is not None:
        return "clear"
    return "bake"


def _principled(mat):
    """The beauty BSDF of a library material (the first Principled whose
    output reaches the mode switch)."""
    for n in mat.node_tree.nodes:
        if n.bl_idname == "ShaderNodeBsdfPrincipled":
            return n
    return None


def _source(node, socket_name: str):
    s = node.inputs[socket_name]
    return s.links[0].from_socket if s.is_linked else s.default_value


def _image(name: str, size: int, *, color: bool) -> bpy.types.Image:
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if color else "Non-Color"
    img.generated_color = (0, 0, 0, 1)
    return img


class _Target:
    """Puts an active image node (and optionally an emission override) in
    every material of the object for one bake, then undoes it."""

    def __init__(self, materials, images: dict, emit=None):
        self.undo = []
        for mat in materials:
            nt = mat.node_tree
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = images.get(mat.name) or images["*"]
            nt.nodes.active = tex
            added = [tex]
            relink = None
            if emit is not None and _kind(mat) == "bake":
                out = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial")
                old = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].is_linked else None
                em = nt.nodes.new("ShaderNodeEmission")
                val = emit(mat)
                if isinstance(val, bpy.types.NodeSocket):
                    if val.type == "VALUE":
                        comb = nt.nodes.new("ShaderNodeCombineColor")
                        for i in range(3):
                            nt.links.new(val, comb.inputs[i])
                        nt.links.new(comb.outputs[0], em.inputs["Color"])
                        added.append(comb)
                    else:
                        nt.links.new(val, em.inputs["Color"])
                else:
                    v = val if isinstance(val, (tuple, list)) or hasattr(val, "__len__") else (val, val, val, 1.0)
                    v = tuple(v)
                    em.inputs["Color"].default_value = v if len(v) == 4 else (*v[:3], 1.0)
                nt.links.new(em.outputs[0], out.inputs["Surface"])
                added.append(em)
                relink = (out, old)
            self.undo.append((nt, added, relink))

    def restore(self):
        for nt, added, relink in self.undo:
            if relink is not None:
                out, old = relink
                if old is not None:
                    nt.links.new(old, out.inputs["Surface"])
            for n in added:
                nt.nodes.remove(n)


def _bake(objects, kind: str, *, samples: int = 1, margin: int = 6) -> None:
    sc = bpy.context.scene
    sc.cycles.samples = samples
    sc.render.bake.margin = margin
    sc.render.bake.use_clear = True
    common = dict(margin=margin, use_clear=True, uv_layer=mats.BAKE_UV)
    for o in sc.objects:
        o.select_set(o in objects)
    bpy.context.view_layer.objects.active = objects[0]
    with bpy.context.temp_override(active_object=objects[0], object=objects[0],
                                   selected_objects=objects, selected_editable_objects=objects):
        if kind == "NORMAL":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", **common)
        elif kind == "AO":
            bpy.ops.object.bake(type="AO", **common)
        else:
            bpy.ops.object.bake(type="EMIT", **common)


def _pixels(img) -> np.ndarray:
    buf = np.empty(img.size[0] * img.size[1] * 4, np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(img.size[1], img.size[0], 4)


def bake_textures(objects, name: str, size: int, normal_size: int, *, ao_distance: float = 0.03,
                  ao_samples: int = 96) -> dict:
    materials = list({m.name: m for o in objects for m in o.data.materials if m is not None}.values())
    baked = [m for m in materials if _kind(m) == "bake"]
    scratch = _image(f"{name}_scratch", 16, color=False)
    out = {}
    mats.set_mode(mats.MODE_BEAUTY)

    def run(kind, img, emit=None, **kw):
        t = _Target(materials, {"*": scratch, **{m.name: img for m in baked}}, emit)
        try:
            _bake(objects, kind, **kw)
        finally:
            t.restore()

    base = _image(f"{name}_base", size, color=True)
    run("EMIT", base, lambda m: _source(_principled(m), "Base Color"))
    rough = _image(f"{name}_rough", size, color=False)
    run("EMIT", rough, lambda m: _source(_principled(m), "Roughness"))
    metal = _image(f"{name}_metal", size, color=False)
    run("EMIT", metal, lambda m: _source(_principled(m), "Metallic"))
    bpy.context.scene.world.light_settings.distance = ao_distance
    ao = _image(f"{name}_ao", size, color=False)
    run("AO", ao, samples=ao_samples)
    normal = _image(f"{name}_normal", normal_size, color=False)
    run("NORMAL", normal)

    orm = _image(f"{name}_orm", size, color=False)
    px = np.stack([_pixels(ao)[..., 0], _pixels(rough)[..., 0], _pixels(metal)[..., 0],
                   np.ones(ao.size[::-1], np.float32)], axis=-1)
    orm.pixels.foreach_set(px.ravel())
    for img in (rough, metal, ao, scratch):
        bpy.data.images.remove(img)

    tex_dir = CACHE / "glb"
    tex_dir.mkdir(parents=True, exist_ok=True)
    for key, img, fmt in (("base", base, "JPEG"), ("orm", orm, "JPEG"), ("normal", normal, "PNG")):
        ext = "jpg" if fmt == "JPEG" else "png"
        path = tex_dir / f"{name}_{key}.{ext}"
        img.filepath_raw = str(path)
        img.file_format = fmt
        if fmt == "JPEG":
            bpy.context.scene.render.image_settings.quality = 90
        img.save()
        out[key] = img
    return out


# ---------------------------------------------------------------------------
# glTF-friendly materials
# ---------------------------------------------------------------------------

def _gltf_output_group() -> bpy.types.ShaderNodeTree:
    grp = bpy.data.node_groups.get("glTF Material Output")
    if grp is None:
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return grp


def _placeholder() -> bpy.types.Image:
    img = bpy.data.images.get("NC_PrintPlaceholder")
    if img is None:
        img = bpy.data.images.new("NC_PrintPlaceholder", 4, 4, alpha=False)
        img.generated_color = (0.80, 0.78, 0.73, 1.0)
        img.filepath_raw = str(CACHE / "glb" / "print_placeholder.png")
        img.file_format = "PNG"
        img.save()
    return img


def rebuild_materials(obj, tex: dict) -> None:
    for mat in [m for m in obj.data.materials if m is not None]:
        kind = _kind(mat)
        info = dict(mat.get("nc_label") or mat.get("nc_clear") or {})
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
        if kind == "bake":
            uv = nt.nodes.new("ShaderNodeUVMap")
            uv.uv_map = mats.BAKE_UV
            base = nt.nodes.new("ShaderNodeTexImage")
            base.image = tex["base"]
            orm = nt.nodes.new("ShaderNodeTexImage")
            orm.image = tex["orm"]
            nrm = nt.nodes.new("ShaderNodeTexImage")
            nrm.image = tex["normal"]
            for t in (base, orm, nrm):
                nt.links.new(uv.outputs[0], t.inputs["Vector"])
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(orm.outputs["Color"], sep.inputs[0])
            nt.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
            nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
            nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nmap.uv_map = mats.BAKE_UV
            nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs[0], bsdf.inputs["Normal"])
            occ = nt.nodes.new("ShaderNodeGroup")
            occ.node_tree = _gltf_output_group()
            nt.links.new(sep.outputs[0], occ.inputs["Occlusion"])
        elif kind == "label":
            uv = nt.nodes.new("ShaderNodeUVMap")
            uv.uv_map = info.get("uv", mats.LABEL_UV_HERO)
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = _placeholder()
            nt.links.new(uv.outputs[0], t.inputs["Vector"])
            nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = info.get("roughness", 0.5)
            bsdf.inputs["Coat Weight"].default_value = info.get("coat", 0.0)
            bsdf.inputs["Coat Roughness"].default_value = info.get("coat_roughness", 0.2)
        elif info.get("film"):
            # thin film over print: an alpha-blended, faintly hazy gloss layer
            bsdf.inputs["Base Color"].default_value = (0.95, 0.96, 0.97, 1.0)
            bsdf.inputs["Roughness"].default_value = info.get("roughness", 0.04)
            bsdf.inputs["Alpha"].default_value = 0.08
            try:
                mat.surface_render_method = "BLENDED"
            except AttributeError:
                mat.blend_method = "BLEND"
        else:   # clear pane: glTF transmission
            tint = list(info.get("tint", [0.92, 0.94, 0.95, 1.0]))
            bsdf.inputs["Base Color"].default_value = (*tint[:3], 1.0)
            bsdf.inputs["Transmission Weight"].default_value = 1.0
            bsdf.inputs["Roughness"].default_value = info.get("roughness", 0.03)
            bsdf.inputs["IOR"].default_value = 1.5


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export(obj, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, export_apply=True,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_materials="EXPORT", export_image_format="AUTO", export_yup=True,
        export_cameras=False, export_lights=False)
    return path


def build_asset(name: str, build, *, size: int, normal_size: int, quick: bool) -> dict:
    t0 = time.time()
    sc = scene.reset()
    scene.setup_cycles(sc, width=64, height=64, samples=1, transparent=True, denoise=False)
    bpy.context.scene.world = bpy.data.worlds.new("Bake")
    root = build()
    objs = _descendants(root) if isinstance(root, bpy.types.Object) else list(root)
    objs = prepare(objs)
    bake_uv(objs)
    if quick:
        size, normal_size = size // 4, normal_size // 4
    tex = bake_textures(objs, name, size, normal_size, ao_samples=16 if quick else 96)
    obj = join_world(objs, name)
    rebuild_materials(obj, tex)
    path = export(obj, GLB_DIR / f"{name}.glb")
    me = obj.data
    info = {"faces": len(me.polygons), "verts": len(me.vertices),
            "quads": sum(1 for p in me.polygons if p.loop_total == 4),
            "materials": [m.name for m in me.materials if m], "bytes": path.stat().st_size,
            "texture": size}
    _log(f"{path.name}: {info['faces']} faces ({100 * info['quads'] / max(1, info['faces']):.0f}% quads), "
         f"{info['bytes'] / 1e6:.1f} MB in {time.time() - t0:.0f}s")
    return info


def _cassette():
    from assets import cassette
    return cassette.build(progress=0.35)


def _sleeve():
    from assets import sleeve
    return sleeve.build(with_cassette=True, progress=0.35)


def _bay():
    from assets import shelf
    m = shelf.materials_dict(seed=1.0)
    parts = shelf.build_bay(m, x_center=0.0)
    rail, card = shelf.build_rail(m, x0=-shelf.BAY_INNER / 2, x1=shelf.BAY_INNER / 2)
    return [*parts.values(), rail, card]


def _dvd():
    from assets import dvd
    return dvd.build()


ASSETS = {
    "vhs_cassette": (_cassette, 2048, 1024),
    "vhs_sleeve": (_sleeve, 2048, 1024),
    "shelf_bay": (_bay, 2048, 1024),
    "dvd_case": (_dvd, 1024, 1024),
}


def export_all(args) -> dict:
    report = {}
    for name, (fn, size, nsize) in ASSETS.items():
        report[name] = build_asset(name, fn, size=size, normal_size=nsize, quick=args.quick)
    import json
    (GLB_DIR / "assets.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    return report
