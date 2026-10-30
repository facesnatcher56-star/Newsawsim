"""Export the ring debarker line to glTF for the game (run inside Blender after db_build).

All files share the build frame (ring plane at x = 0, floor at z = 0), so the game places
every one with the same transform:

  debarker_machine.glb   DB_Machine: frame, housing, rotor + tools, feed rolls, top arms
  debarker_infeed.glb    IN: V-roll infeed conveyor with its dump skids
  debarker_outfeed.glb   OUT: V-roll outfeed conveyor with the metal detector arch
  bark_belt.glb          BB_BarkBelt: cleated bark belt from under the chute to the bin
  bark_bin.glb           BIN_Root: roll-off bark bin with the BIN_Heap mound inside

Exported in the rest pose: tools closed, top roll arms on the log line.
"""
import os
import time

import bpy

import db_build as D

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models",
                   "debarker")
FILES = {
    "debarker_machine.glb": "DB_Machine",
    "debarker_infeed.glb": "IN",
    "debarker_outfeed.glb": "OUT",
    "bark_belt.glb": "BB_BarkBelt",
    "bark_bin.glb": "BIN_Root",
}


def _set_viewport_colours():
    for name, (rgb, metal, rough) in D.VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough


def _export(root_name, path):
    root = bpy.data.objects[root_name]
    bpy.ops.object.select_all(action='DESELECT')
    objs = [root] + list(root.children_recursive)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
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
    D.pose(tool_r=0.08, top_in_open=0.0, top_out_open=0.0, rotor_deg=0.0)
    log = bpy.data.objects.get("DB_PreviewLog")
    if log is not None:
        log.select_set(False)
    return {name: _export(root, os.path.join(OUT, name)) for name, root in FILES.items()}
