"""Render stage for inspecting the band headrig (run inside Blender after hr_build).

Reuses the knuckleboom render setup, hides the other machines and lays stand-in logs on
the deck and on the carriage against the knees.
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "knuckle_boom"))
import kbl_scene as KS  # noqa: E402

import hr_build as D  # noqa: E402

RENDERS = os.path.join(HERE, "renders")
OTHERS = ("KnuckleBoomLoader", "DryKilns", "RingDebarker", "LogDeck", "LogKicker")


def setup(samples=32):
    lc = bpy.context.view_layer.layer_collection.children.get("Collection")
    if lc is not None:
        lc.exclude = False
        for o in lc.collection.all_objects:
            o.hide_render = True
    for name in OTHERS:
        c = bpy.context.view_layer.layer_collection.children.get(name)
        if c is not None:
            c.exclude = True
    cam = KS.setup(samples=samples)
    if lc is not None:
        lc.exclude = True
    bpy.context.scene.view_settings.exposure = -1.6
    return cam


def log(name, at_godot, radius=D.LOG_R):
    obj = bpy.data.objects.get(name)
    if obj is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=4.92, vertices=40)
        obj = bpy.context.active_object
        obj.name = name
        import materials_lib as ML
        mat = bpy.data.materials.get("HR_PreviewWood") or ML.simple("HR_PreviewWood", (0.55, 0.38, 0.2), 0.8, 0.0, 20, 0.3)
        obj.data.materials.append(mat)
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        bpy.data.collections[D.COLL].objects.link(obj)
    obj.rotation_euler = (0, math.radians(90), 0)
    obj.location = D.G(*at_godot)
    return obj


def place_logs():
    log("HR_PreviewLogCar", (D.CAR_HOME_X, D.BASE_TOP_Y + D.LOG_R, D.KNEE_FACE_REST - D.LOG_R))
    log("HR_PreviewLogDeck", (16.9, D.deck_y(4.9) + 0.29, 4.9), 0.29)


def look(cam, eye_g, target_g, lens=35):
    KS.look(cam, D.G(*eye_g), D.G(*target_g), lens)


def render(name):
    os.makedirs(RENDERS, exist_ok=True)
    path = os.path.join(RENDERS, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
