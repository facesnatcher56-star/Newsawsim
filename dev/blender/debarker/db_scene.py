"""Render stage for inspecting the ring debarker (run inside Blender after db_build).

Reuses the knuckleboom render setup (sky, sun, floor, camera, AgX) and adds a stand-in
16 ft log on the line so the rolls, tools and skids can be judged against it.
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "knuckle_boom"))
import kbl_scene as KS  # noqa: E402

import db_build as D  # noqa: E402

RENDERS = os.path.join(HERE, "renders")


def setup():
    cam = KS.setup(samples=40)
    bpy.context.scene.view_settings.exposure = -1.6
    log = bpy.data.objects.get("DB_PreviewLog")
    if log is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=D.LOG_R, depth=4.92, vertices=40)
        log = bpy.context.active_object
        log.name = "DB_PreviewLog"
        log.rotation_euler = (0, math.radians(90), 0)
        import materials_lib as ML
        log.data.materials.append(ML.simple("DB_PreviewBark", (0.12, 0.06, 0.03), 0.95, 0.0, 20, 0.6))
    return cam


def place_log(x_centre):
    bpy.data.objects["DB_PreviewLog"].location = (x_centre, 0.0, D.LINE_Z)


def render(name):
    os.makedirs(RENDERS, exist_ok=True)
    path = os.path.join(RENDERS, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
