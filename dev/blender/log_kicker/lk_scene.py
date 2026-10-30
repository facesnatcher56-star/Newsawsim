"""Render stage for inspecting the log kicker (run inside Blender after lk_build).

Reuses the knuckleboom render setup and puts a stand-in log in the trough against the
end stop; the debarker and log deck collections are hidden so only the kicker shows.
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "knuckle_boom"))
import kbl_scene as KS  # noqa: E402

import lk_build as D  # noqa: E402

RENDERS = os.path.join(HERE, "renders")


def setup(samples=32):
    for name in ("Collection", "KnuckleBoomLoader", "DryKilns", "RingDebarker", "LogDeck"):
        lc = bpy.context.view_layer.layer_collection.children.get(name)
        if lc is not None:
            lc.exclude = name not in ("Collection",)
    lc = bpy.context.view_layer.layer_collection.children.get("Collection")
    if lc is not None:
        for o in lc.collection.all_objects:
            o.hide_render = True
    cam = KS.setup(samples=samples)
    if lc is not None:
        lc.exclude = True
    bpy.context.scene.view_settings.exposure = -1.6
    return cam


def log(at_godot, spin=0.0):
    obj = bpy.data.objects.get("LK_PreviewLog")
    if obj is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=D.LOG_R, depth=4.92, vertices=40)
        obj = bpy.context.active_object
        obj.name = "LK_PreviewLog"
        import materials_lib as ML
        mat = bpy.data.materials.get("LD_PreviewBark") or ML.simple("LD_PreviewBark", (0.12, 0.06, 0.03), 0.95, 0.0, 20, 0.6)
        obj.data.materials.append(mat)
    obj.rotation_euler = (spin, math.radians(90), 0)
    obj.location = D.G(*at_godot)
    return obj


def look(cam, eye_g, target_g, lens=35):
    KS.look(cam, D.G(*eye_g), D.G(*target_g), lens)


def render(name):
    os.makedirs(RENDERS, exist_ok=True)
    path = os.path.join(RENDERS, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
