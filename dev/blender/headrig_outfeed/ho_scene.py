"""Render stage for inspecting the headrig outfeed (run inside Blender after ho_build).

Reuses the headrig stage (it keeps the Headrig collection visible for context) and adds
stand-in pieces on the rolls.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_scene as HS  # noqa: E402

import ho_build as D  # noqa: E402

RENDERS = os.path.join(HERE, "renders")


def setup(samples=32):
    cam = HS.setup(samples)
    for name in ("Headrig", D.COLL):
        c = bpy.context.view_layer.layer_collection.children.get(name)
        if c is not None:
            c.exclude = False
    return cam


def board(name, x0, x1, y, z0, z1):
    """Stand-in sawn piece (Godot extents)."""
    obj = bpy.data.objects.get(name)
    if obj is None:
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        obj = bpy.context.active_object
        obj.name = name
        mat = bpy.data.materials.get("HR_PreviewWood")
        if mat is not None:
            obj.data.materials.append(mat)
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        bpy.data.collections[D.COLL].objects.link(obj)
    a, b = D.G(x0, y[0], z0), D.G(x1, y[1], z1)
    obj.location = (a + b) / 2
    obj.scale = (abs(b.x - a.x), abs(b.y - a.y), abs(b.z - a.z))
    return obj


def place_pieces():
    top = D.TOP_Y
    board("HO_PreviewSlab", 30.3, 35.2, (top, top + 0.1), 5.0, 5.4)
    board("HO_PreviewBoard", 38.5, 43.4, (top, top + 0.05), 5.05, 5.25)
    board("HO_PreviewTroughSlab", 37.0, 41.9, (D.TROUGH_FLOOR_Y, D.TROUGH_FLOOR_Y + 0.1), 3.7, 4.05)


def look(cam, eye_g, target_g, lens=35):
    HS.look(cam, eye_g, target_g, lens)


def render(name):
    os.makedirs(RENDERS, exist_ok=True)
    path = os.path.join(RENDERS, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
