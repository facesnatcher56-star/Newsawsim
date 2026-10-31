"""Inspection renders of the forklift in its own scene (ForkliftStudio), so the mill scene and
its camera are left alone. Run inside Blender after forklift_build.build().

    shot("side_left", eye=(-1.5, 1.6, 8.0), look=(-1.4, 1.3, 0.0), lens=35)

Positions are Godot forklift-local (+X forward, +Y up, +Z left). Renders land in renders/.
"""
import math
import os

import bpy
from mathutils import Vector

import forklift_build as FB

OUT = os.path.join(FB.HERE, "renders")


def setup(samples=48, res=(1280, 800)):
    sc = bpy.data.scenes.get(FB.STUDIO) or bpy.data.scenes.new(FB.STUDIO)
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.device = 'GPU'
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    w = bpy.data.worlds.get("ForkliftWorld") or bpy.data.worlds.new("ForkliftWorld")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.62, 0.72, 1.0)
    bg.inputs["Strength"].default_value = 0.9
    sc.world = w
    if "ForkliftGround" not in bpy.data.objects:
        me = bpy.data.meshes.new("ForkliftGround")
        s = 40.0
        me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
        g = bpy.data.objects.new("ForkliftGround", me)
        m = bpy.data.materials.get("ForkliftGroundMat") or bpy.data.materials.new("ForkliftGroundMat")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.31, 0.29, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
        me.materials.append(m)
        sc.collection.objects.link(g)
    if "ForkliftSun" not in bpy.data.objects:
        ld = bpy.data.lights.new("ForkliftSun", 'SUN')
        ld.energy = 3.5
        ld.angle = math.radians(3)
        sun = bpy.data.objects.new("ForkliftSun", ld)
        sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
        sc.collection.objects.link(sun)
    if "ForkliftCam" not in bpy.data.objects:
        cam = bpy.data.objects.new("ForkliftCam", bpy.data.cameras.new("ForkliftCam"))
        sc.collection.objects.link(cam)
    sc.camera = bpy.data.objects["ForkliftCam"]
    return sc


def shot(name, eye, look, lens=35.0, lift=None):
    """Render one view. lift sets the carriage height (fork bottoms above the ground) first."""
    sc = setup()
    if lift is not None:
        set_lift(lift)
    cam = bpy.data.objects["ForkliftCam"]
    cam.data.lens = lens
    cam.data.clip_start = 0.05
    e, t = FB.G(*eye), FB.G(*look)
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat('-Z', 'Y').to_euler()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=sc.name)
    return path


def set_lift(lift, free_lift=1.2):
    """Same split as forklift.gd: carriage rises alone for the free lift, then the inner mast."""
    car = bpy.data.objects["ForkliftCarriage"]
    inner = bpy.data.objects["ForkliftMastInner"]
    car.location = FB.G(0.0, lift, 0.0)
    inner.location = FB.G(0.0, max(lift - free_lift, 0.0), 0.0)


VIEWS = {
    "fk_front34_left": ((5.0, 2.2, 4.6), (-0.6, 1.3, 0.0), 35),
    "fk_side_left": ((-1.3, 1.5, 8.5), (-1.3, 1.4, 0.0), 35),
    "fk_side_right": ((-1.3, 1.5, -8.5), (-1.3, 1.4, 0.0), 35),
    "fk_rear": ((-9.0, 1.6, 0.0), (-1.0, 1.2, 0.0), 35),
    "fk_rear34_right": ((-6.5, 2.4, -4.8), (-1.2, 1.3, 0.0), 35),
    "fk_front": ((8.0, 1.5, 0.0), (0.0, 1.5, 0.0), 35),
}


def views(names=None):
    return [shot(n, *VIEWS[n]) for n in (names or VIEWS)]
