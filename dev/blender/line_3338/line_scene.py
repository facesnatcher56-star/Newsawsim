"""Lighting and cameras for reviewing the whole 3338 line."""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "edger_4ta36"))
import mesh_lib as L  # noqa: E402
import edger_scene as ES  # noqa: E402

COLL = "LineReview"


def build():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    scene = bpy.context.scene
    world = bpy.data.worlds.get("Edger_World") or bpy.data.worlds.new("Edger_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs['Color'].default_value = (0.55, 0.58, 0.62, 1.0)
    bg.inputs['Strength'].default_value = 0.45
    for name, loc, rot, energy, size in (("Line_Key", (-4.0, -14.0, 9.0), (50, 0, -15), 4000, 8.0),
                                         ("Line_Fill", (6.0, 6.0, 8.0), (50, 0, 140), 2200, 8.0),
                                         ("Line_Top", (-2.0, -6.0, 12.0), (0, 0, 0), 2500, 10.0)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.size = energy, size
        lo = bpy.data.objects.new(name, data)
        coll.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = [math.radians(a) for a in rot]
    cams = {
        "Overview": ES.camera(coll, "Cam_LineOverview", (420, -760, 420), (-60, -230, 20), 24),
        "Operator": ES.camera(coll, "Cam_LineOperator", (-120, -420, 150), (-80, -120, 40), 22),
        "Unscrambler": ES.camera(coll, "Cam_LineUnscrambler", (150, -560, 120), (-110, -360, 0), 24),
        "Infeed": ES.camera(coll, "Cam_LineInfeed", (-330, 80, 120), (-100, -20, 40), 24),
    }
    scene.camera = cams["Overview"]
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'GPU'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.exposure = -0.5
    return {k: v.name for k, v in cams.items()}
