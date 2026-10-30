"""Render stage for inspecting the knuckleboom loader (run inside Blender after kbl_build)."""
import math
import os

import bpy
from mathutils import Vector

RENDERS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")


def setup(samples=48, res=(1280, 800)):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    try:
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.render.resolution_x, sc.render.resolution_y = res
    for name in ("Cube", "Light", "Camera"):
        o = bpy.data.objects.get(name)
        if o is not None:
            o.hide_render = True
            o.hide_set(True)

    world = sc.world or bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new('ShaderNodeTexSky')
    for attr, val in (("sky_type", 'NISHITA'), ("sun_elevation", math.radians(38)), ("sun_rotation", math.radians(135))):
        try:
            setattr(sky, attr, val)
        except Exception:
            pass
    bg = nt.nodes.new('ShaderNodeBackground')
    bg.inputs['Strength'].default_value = 0.35
    out = nt.nodes.new('ShaderNodeOutputWorld')
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])

    sun = bpy.data.objects.get("KBL_Sun")
    if sun is None:
        sun = bpy.data.objects.new("KBL_Sun", bpy.data.lights.new("KBL_Sun", 'SUN'))
        sc.collection.objects.link(sun)
    sun.data.energy = 3.5
    sun.data.angle = math.radians(2)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(140))

    ground = bpy.data.objects.get("KBL_Ground")
    if ground is None:
        me = bpy.data.meshes.new("KBL_Ground")
        s = 30
        me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
        ground = bpy.data.objects.new("KBL_Ground", me)
        sc.collection.objects.link(ground)
        import materials_lib as ML
        ground.data.materials.append(ML.simple("KBL_Floor", (0.18, 0.17, 0.15), 0.9, 0.0, 3, 0.3))

    cam = bpy.data.objects.get("KBL_Cam")
    if cam is None:
        cam = bpy.data.objects.new("KBL_Cam", bpy.data.cameras.new("KBL_Cam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def look(cam, eye, target, lens=35):
    cam.location = eye
    d = Vector(target) - Vector(eye)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = lens


def render(name):
    os.makedirs(RENDERS, exist_ok=True)
    path = os.path.join(RENDERS, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
