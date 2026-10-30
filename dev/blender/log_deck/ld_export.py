"""Export the log deck to glTF for the game (run inside Blender after ld_build).

Every file shares the deck frame (LiveLogDeck root, floor at z = 0), so the game places each
one at y = -1.288 under the deck root:

  log_deck_frame.glb     LD_Frame: bed (LD_Bed > LD_HeadShaft, LD_TailShaft), legs, fixed steps
  log_deck_moving.glb    LD_MovingSteps: moving steps, lift tubes, cylinder rods (down pose)
  log_deck_drive.glb     LD_Drive: head shaft drive and the feeder's hydraulic power unit
  log_deck_catwalk.glb   LD_Catwalk: service catwalk and stairs
  log_deck_chain.glb     LD_ChainLink, LD_ChainDog: one pitch of chain each, for instancing
"""
import os
import time

import bpy

import ld_build as D

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models",
                   "log_deck")
FILES = {
    "log_deck_frame.glb": ["LD_Frame"],
    "log_deck_moving.glb": ["LD_MovingSteps"],
    "log_deck_drive.glb": ["LD_Drive"],
    "log_deck_catwalk.glb": ["LD_Catwalk"],
    "log_deck_chain.glb": ["LD_ChainLink", "LD_ChainDog"],
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
        objs += [root] + [c for c in root.children_recursive if not c.name.startswith("LD_Preview")]
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
    D.pose(0.0)
    chain = [(n, bpy.data.objects[n].location.copy()) for n in FILES["log_deck_chain.glb"]]
    for n, _ in chain:
        bpy.data.objects[n].location = (0, 0, 0)
    try:
        return {name: _export(roots, os.path.join(OUT, name)) for name, roots in FILES.items()}
    finally:
        for n, loc in chain:
            bpy.data.objects[n].location = loc
