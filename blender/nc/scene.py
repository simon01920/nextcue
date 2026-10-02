"""Scene, render-engine and camera setup."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

from . import MM


def reset() -> bpy.types.Scene:
    """Empty factory scene in metric units (we author in metres)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "MILLIMETERS"
    return scene


def use_gpu() -> str:
    """Prefer OptiX, then CUDA; fall back to CPU. Returns the device type."""
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for device_type in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = device_type
        except TypeError:
            continue
        prefs.get_devices()
        devices = [d for d in prefs.devices if d.type == device_type]
        if devices:
            for d in prefs.devices:
                d.use = d.type == device_type
            bpy.context.scene.cycles.device = "GPU"
            return device_type
    bpy.context.scene.cycles.device = "CPU"
    return "CPU"


def setup_cycles(
    scene: bpy.types.Scene,
    *,
    width: int,
    height: int,
    samples: int = 256,
    transparent: bool = True,
    denoise: bool = True,
    view: str = "AgX",
    look: str | None = "AgX - Medium High Contrast",
    exposure: float = 0.0,
    filter_width: float = 1.5,
    bounces: int = 8,
) -> None:
    scene.render.engine = "CYCLES"
    use_gpu()
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.01
    c.use_denoising = denoise
    if denoise:
        try:
            c.denoiser = "OPENIMAGEDENOISE"
            c.denoising_use_gpu = True
        except (TypeError, AttributeError):
            pass
    c.max_bounces = bounces
    c.diffuse_bounces = min(bounces, 4)
    c.glossy_bounces = min(bounces, 4)
    c.transmission_bounces = bounces
    c.transparent_max_bounces = bounces
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.filter_width = filter_width
    c.sample_clamp_indirect = 8.0
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.render.use_persistent_data = True
    set_view(scene, view, look, exposure)


def set_view(scene, view: str, look: str | None, exposure: float = 0.0) -> None:
    vs = scene.view_settings
    vs.view_transform = view
    try:
        vs.look = look or "None"
    except TypeError:
        vs.look = "None"
    vs.exposure = exposure
    vs.gamma = 1.0
    scene.display_settings.display_device = "sRGB"
    scene.sequencer_colorspace_settings.name = "sRGB"


def look_at(obj: bpy.types.Object, target, roll: float = 0.0) -> None:
    """Point -Z of obj (camera/light) at target."""
    direction = Vector(target) - obj.location
    quat = direction.to_track_quat("-Z", "Y")
    obj.rotation_euler = quat.to_euler()
    if roll:
        obj.rotation_euler.rotate_axis("Z", roll)


def camera(
    name: str,
    location,
    target,
    *,
    lens: float | None = 85.0,
    ortho_scale: float | None = None,
    sensor: float = 36.0,
    clip_start: float = 1 * MM,
    clip_end: float = 50.0,
    shift=(0.0, 0.0),
) -> bpy.types.Object:
    data = bpy.data.cameras.new(name)
    if ortho_scale is not None:
        data.type = "ORTHO"
        data.ortho_scale = ortho_scale
    else:
        data.lens = lens
    data.sensor_width = sensor
    data.sensor_fit = "AUTO"
    data.clip_start = clip_start
    data.clip_end = clip_end
    data.shift_x, data.shift_y = shift
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = Vector(location)
    look_at(obj, target)
    return obj


def orbit_location(target, distance: float, yaw_deg: float, pitch_deg: float) -> Vector:
    """Point on a sphere around target. yaw 0 looks along +Y (camera at -Y)."""
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    x = math.sin(yaw) * math.cos(pitch) * distance
    y = -math.cos(yaw) * math.cos(pitch) * distance
    z = math.sin(pitch) * distance
    return Vector(target) + Vector((x, y, z))


def render_still(path: Path, *, file_format: str = "PNG", color_depth: str = "8",
                 color_mode: str = "RGBA", quality: int = 92) -> Path:
    scene = bpy.context.scene
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    s = scene.render.image_settings
    s.file_format = file_format
    s.color_mode = color_mode
    if file_format in ("PNG", "OPEN_EXR", "TIFF"):
        s.color_depth = color_depth
    if file_format == "OPEN_EXR":
        s.exr_codec = "ZIP"
    if file_format in ("WEBP", "JPEG"):
        s.quality = quality
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def collection(name: str, parent=None) -> bpy.types.Collection:
    col = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(col)
    return col
