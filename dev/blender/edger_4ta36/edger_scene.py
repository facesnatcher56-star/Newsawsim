"""Review scene for the edger: concrete floor, soft mill lighting, cameras round the machine."""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
import mesh_lib as L  # noqa: E402
from materials_lib import Graph  # noqa: E402

COLL = "EdgerReview"
IN = 0.0254


def concrete():
    g = Graph("Edger_Floor")
    pos = g.geo.outputs['Position']
    n = g.noise(pos, 1.5, 8, 0.6)
    g.link(g.ramp(n.outputs['Fac'], [(0.3, (0.22, 0.21, 0.2)), (0.7, (0.34, 0.33, 0.31))]), g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = 0.8
    g.link(g.bump(g.noise(pos, 60, 4).outputs['Fac'], 0.1, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def camera(coll, name, loc_in, target_in, lens=30):
    t = bpy.data.objects.new(name + "_Target", None)
    coll.objects.link(t)
    t.location = [v * IN for v in target_in]
    data = bpy.data.cameras.new(name)
    data.lens = lens
    cam = bpy.data.objects.new(name, data)
    coll.objects.link(cam)
    cam.location = [v * IN for v in loc_in]
    c = cam.constraints.new('TRACK_TO')
    c.target = t
    return cam


def build():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    me = bpy.data.meshes.new("EdgerFloor")
    s = 20.0
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    me.materials.append(concrete())
    coll.objects.link(bpy.data.objects.new("EdgerFloor", me))

    scene = bpy.context.scene
    world = bpy.data.worlds.get("Edger_World") or bpy.data.worlds.new("Edger_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs['Color'].default_value = (0.55, 0.58, 0.62, 1.0)
    bg.inputs['Strength'].default_value = 0.35
    for name, loc, rot, energy, size in (("KeyLight", (-1.5, -4.0, 5.0), (50, 0, -20), 900, 3.0),
                                         ("FillLight", (6.0, 3.0, 4.0), (55, 0, 130), 500, 4.0),
                                         ("TopLight", (1.4, 0.0, 6.0), (0, 0, 0), 600, 2.5)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.size = size
        lo = bpy.data.objects.new(name, data)
        coll.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = [math.radians(a) for a in rot]
    cams = {
        "Operator": camera(coll, "Cam_Operator", (175, -190, 130), (52, 15, 52), 28),
        "Drive": camera(coll, "Cam_Drive", (185, 230, 135), (52, 45, 50), 28),
        "Infeed": camera(coll, "Cam_Infeed", (-120, -60, 75), (40, 0, 38), 30),
        "Inside": camera(coll, "Cam_Inside", (0, -60, 110), (32, 0, 38), 26),
        "Gates": camera(coll, "Cam_OpGates", (35, -175, 75), (50, -20, 42), 30),
        "Tower": camera(coll, "Cam_Tower", (40, 170, 95), (68, 20, 72), 32),
        "Chain": camera(coll, "Cam_Chain", (35, -120, 72), (60, -24, 55), 50),
    }
    scene.camera = cams["Operator"]
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'GPU'
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    vs = scene.view_settings
    vs.view_transform = 'AgX'
    try:
        vs.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass
    return {k: v.name for k, v in cams.items()}
