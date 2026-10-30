"""Export the dry kiln to glTF for the game (run inside Blender after kiln_build.build).

Meshes are in the kiln-local Godot frame (kiln_build docstring): +Z along the tracks (front
wall at z = 0, green yard at z < 0), +X across, origin on the floor at the front-left corner.

  kiln.glb   building, interior, rails, door rails, doors (all shut on their hangers), door
             dollies parked at the ends of their rails, fans, and the empty cart strings as
             the preview placed them. The preview lumber is left out.
"""
import os
import sys
import time

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "bin_sorter"))
import sorter_export as SE  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "dry_kiln")

# glTF cannot carry the procedural node trees, so every material goes out as a flat
# viewport colour (linear), metallic and roughness. Kept well off white and only lightly
# metallic: fully metallic pale grey mirrors the sky and turns the whole kiln one glare.
VIEWPORT = {
    # The mill is lit mostly by a bright blue sky, so anything metallic mirrors it and goes
    # pale: the cladding and roof are kept nearly non-metallic and darker than they would be
    # in a render, so walls, roof and doors stay three distinct tones in game.
    "Kiln_Aluminium": ((0.21, 0.195, 0.17), 0.1, 0.65),
    "Kiln_Roof": ((0.018, 0.018, 0.02), 0.1, 0.8),
    "Kiln_DoorPanel": ((0.46, 0.43, 0.38), 0.05, 0.55),
    "Kiln_Curb": ((0.06, 0.055, 0.05), 0.0, 0.9),
    "Kiln_DoorBlue": ((0.02, 0.05, 0.22), 0.3, 0.5),
    "Kiln_CartBlack": ((0.03, 0.03, 0.032), 0.3, 0.6),
    "Sorter_Rubber": ((0.015, 0.015, 0.015), 0.0, 0.8),
}


def _set_viewport_colours():
    SE._set_viewport_colours()
    for name, (rgb, metal, rough) in VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough


def export_all():
    os.makedirs(OUT, exist_ok=True)
    _set_viewport_colours()
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
    # Export beside the target and swap it in: OneDrive (and Godot's importer) briefly lock
    # the .glb after each write, so writing it in place fails every other time.
    tmp = os.path.join(OUT, "kiln.export.glb")
    try:
        bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_materials='VIEWPORT', export_cameras=False,
                                  export_lights=False, export_animations=False)
    finally:
        for o, loc in saved.items():
            o.location = loc
    for _ in range(20):
        try:
            os.replace(tmp, path)
            break
        except OSError:
            time.sleep(0.5)
    else:
        raise OSError("kiln.glb stayed locked; the new export is at " + tmp)
    return [os.path.basename(path), len(objs)]
