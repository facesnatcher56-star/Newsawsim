"""Export the log kicker to glTF for the game (run inside Blender after lk_build).

Every file is in mill coordinates (floor at z = 0), so the game places each one at
y = -1.288 under a node at the origin:

  log_kicker_frame.glb     LK_Frame: trough, stands, skids, drive, end stop frame, HPU;
                           LK_HeadShaft / LK_TailShaft sprockets
  log_kicker_paddles.glb   LK_Kicker: kicker shaft, paddles and crank (rest pose)
  log_kicker_bumper.glb    LK_Bumper: bumper plate, rubber face, absorber rods
  log_kicker_cylinder.glb  LK_CylBarrel, LK_CylRod: the kicker cylinder halves

The trough chain reuses the log deck's chain links (log_deck_chain.glb).
"""
import os
import time

import bpy

import lk_build as D

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models",
                   "log_kicker")
FILES = {
    "log_kicker_frame.glb": ["LK_Frame"],
    "log_kicker_paddles.glb": ["LK_Kicker"],
    "log_kicker_bumper.glb": ["LK_Bumper"],
    "log_kicker_cylinder.glb": ["LK_CylBarrel", "LK_CylRod"],
}


def _set_viewport_colours():
    for name, (rgb, metal, rough) in D.VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough


def _export(root_names, path):
    bpy.ops.object.select_all(action='DESELECT')
    objs = []
    for name in root_names:
        root = bpy.data.objects[name]
        objs += [root] + list(root.children_recursive)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # Export beside the target and swap it in: OneDrive and Godot's importer briefly lock
    # a .glb right after it is written.
    tmp = path[:-4] + ".export.glb"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='VIEWPORT', export_cameras=False,
                              export_lights=False, export_animations=False)
    for _ in range(20):
        try:
            os.replace(tmp, path)
            return len(objs)
        except OSError:
            time.sleep(0.5)
    raise OSError(os.path.basename(path) + " stayed locked; the export is at " + tmp)


def export_all():
    os.makedirs(OUT, exist_ok=True)
    _set_viewport_colours()
    D.pose(0.0, 0.0)
    return {name: _export(roots, os.path.join(OUT, name)) for name, roots in FILES.items()}
