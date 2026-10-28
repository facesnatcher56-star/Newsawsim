"""Export the dry kiln to glTF for the game (run inside Blender after kiln_build.build).

Meshes are in the kiln-local Godot frame (kiln_build docstring): +Z along the tracks (front
wall at z = 0, green yard at z < 0), +X across, origin on the floor at the front-left corner.

  kiln.glb   building, interior, rails, door rails, doors (all shut on their hangers), door
             dollies parked at the ends of their rails, fans, and the empty cart strings as
             the preview placed them. The preview lumber is left out.
"""
import os

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models", "dry_kiln")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    coll = bpy.data.collections["DryKilns"]
    parts = bpy.data.collections.get("KilnParts")
    skip = set(parts.all_objects) if parts else set()
    objs = [o for o in coll.all_objects if o.type == 'MESH' and o not in skip and o.name != "KilnPreviewLumber"]
    saved = {}
    for name in ("KilnDoor_F0", "KilnDoor_F1", "KilnDoor_R0", "KilnDoor_R1"):
        o = bpy.data.objects.get(name)
        if o is not None:
            saved[o] = o.location.copy()
            o.location = (0.0, 0.0, 0.0)
    for sc in bpy.data.scenes:
        for vl in sc.view_layers:
            for o in vl.objects:
                o.select_set(False, view_layer=vl)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, "kiln.glb")
    try:
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_materials='EXPORT', export_cameras=False,
                                  export_lights=False, export_animations=False)
    finally:
        for o, loc in saved.items():
            o.location = loc
    return [os.path.basename(path), len(objs)]
