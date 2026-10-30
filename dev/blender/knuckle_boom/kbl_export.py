"""Export the knuckleboom loader to glTF for the game (run inside Blender after kbl_build).

One file, knuckle_boom_loader.glb, with the whole KBL_Base hierarchy in the rest pose
(every joint angle 0: boom and stick level, tongs closed). The game drives the joint
empties by name and re-aims the cylinder barrel/rod empties with look_at every frame.
"""
import os

import bpy

import kbl_build as K

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models",
                   "knuckle_boom")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    for name, (rgb, metal, rough) in K.VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough
    K.pose(0.0, 0.0, 0.0, 0.0)
    O = bpy.data.objects
    O["KBL_Dangle"].rotation_euler = (0, 0, 0)
    K.aim_cylinders(K.pairs())
    root = O["KBL_Base"]
    bpy.ops.object.select_all(action='DESELECT')
    objs = [root] + list(root.children_recursive)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = os.path.join(OUT, "knuckle_boom_loader.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='VIEWPORT', export_cameras=False,
                              export_lights=False, export_animations=False)
    return {"path": os.path.abspath(path), "objects": len(objs)}
