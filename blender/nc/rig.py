"""Lighting rigs: product studio for hero/turntable work, warm store light
for the shelf. Light cards are invisible to the camera and only show up in
reflections, which is what gives glossy plastic its long soft gradients."""

from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Vector

from . import MM
from .mats import emission_card, matte
from .scene import look_at


def world_gradient(top=(0.030, 0.031, 0.034), bottom=(0.004, 0.004, 0.005),
                   strength: float = 1.0) -> None:
    world = bpy.data.worlds.get("NC_World") or bpy.data.worlds.new("NC_World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs[2], ramp.inputs[0])
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (*top, 1)
    nt.links.new(ramp.outputs[0], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs["Surface"])


def area_light(name: str, location, target, *, size=(0.3, 0.2), power: float = 40.0,
               color=(1.0, 0.97, 0.92), spread_deg: float = 180.0,
               visible_glossy: bool = True) -> bpy.types.Object:
    data = bpy.data.lights.new(name, "AREA")
    data.shape = "RECTANGLE"
    data.size, data.size_y = size
    data.energy = power
    data.color = color
    data.spread = math.radians(spread_deg)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = Vector(location)
    look_at(obj, target)
    obj.visible_glossy = visible_glossy
    return obj


def light_card(name: str, location, target, size=(0.6, 0.15), strength: float = 3.0,
               color=(1, 1, 1, 1)) -> bpy.types.Object:
    """Emissive plane seen only by glossy rays (reflections)."""
    bm = bmesh.new()
    w, h = size
    vs = [bm.verts.new(p) for p in ((-w / 2, -h / 2, 0), (w / 2, -h / 2, 0),
                                    (w / 2, h / 2, 0), (-w / 2, h / 2, 0))]
    bm.faces.new(vs)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = Vector(location)
    look_at(obj, target)
    obj.data.materials.append(emission_card(name + "_mat", strength, color))
    obj.visible_camera = False
    obj.visible_diffuse = False
    obj.visible_shadow = False
    obj.visible_transmission = False
    obj.visible_volume_scatter = False
    return obj


def power_for(irradiance: float, distance: float) -> float:
    """Area-light power (W) giving roughly `irradiance` (W/m²) at `distance`
    on-axis. A Lambertian emitter of power P has radiant intensity ≈ P/π, so
    E ≈ P / (π d²). Sizing lights this way keeps exposure stable at any scale."""
    return irradiance * math.pi * distance * distance


def studio(target=(0, 0, 0), radius: float = 0.55, key: float = 3.0, fill: float = 0.7,
           rim: float = 2.2, cards: bool = True, card_strength: float = 1.6) -> list[bpy.types.Object]:
    """Three-point product rig. key/fill/rim are target irradiances (W/m²);
    ~3 W/m² renders white paper near 0.75 and black ABS near black."""
    t = Vector(target)
    specs = [
        ("Key", Vector((-0.55, -0.75, 0.75)), (0.32, 0.22), key, (1.0, 0.965, 0.92)),
        ("Fill", Vector((0.85, -0.55, 0.15)), (0.5, 0.5), fill, (0.88, 0.94, 1.0)),
        ("Rim", Vector((0.25, 0.95, 0.55)), (0.6, 0.05), rim, (1.0, 0.98, 0.95)),
    ]
    objs = []
    for name, direction, size, e, color in specs:
        loc = t + direction * radius
        d = (loc - t).length
        objs.append(area_light(name, loc, t, size=(size[0] * radius, size[1] * radius),
                               power=power_for(e, d), color=color))
    if cards:
        objs.append(light_card("CardTop", t + Vector((0.0, -0.35, 0.95)) * radius, t,
                               size=(0.9 * radius, 0.12 * radius), strength=card_strength))
        objs.append(light_card("CardSide", t + Vector((-0.95, 0.1, 0.25)) * radius, t,
                               size=(0.08 * radius, 0.8 * radius), strength=card_strength * 0.6))
    return objs


def cyclorama(size: float = 1.6, curve: float = 0.25, color=(0.018, 0.018, 0.02, 1.0),
              z: float = 0.0) -> bpy.types.Object:
    """Seamless photo backdrop: a floor that curves up into a back wall."""
    bm = bmesh.new()
    segs = 16
    half = size / 2
    rows = []
    # floor from front (-y) to curve start, arc, then wall up
    profile = [(-half, 0.0)]
    profile.append((half - curve, 0.0))
    for s in range(1, segs + 1):
        a = (math.pi / 2) * s / segs
        profile.append((half - curve + math.sin(a) * curve, curve - math.cos(a) * curve))
    profile.append((half, size * 0.8))
    for x in (-half, half):
        rows.append([bm.verts.new((x, y, z + h)) for (y, h) in profile])
    for i in range(len(profile) - 1):
        bm.faces.new((rows[0][i], rows[1][i], rows[1][i + 1], rows[0][i + 1]))
    mesh = bpy.data.meshes.new("Cyclorama")
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new("Cyclorama", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(matte("Backdrop", color, roughness=0.55))
    return obj
