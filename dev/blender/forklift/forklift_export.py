"""Export the forklift to glTF for the game (run inside Blender after forklift_build.build).

Every mesh is in the forklift-local Godot frame (+X forward, origin on the ground under the
middle of the drive axle), which the +Y-up glTF export keeps.

  forklift_body.glb         everything fixed to the frame: body, cab, outer mast, fittings
  forklift_wheel.glb        one wheel (tyre, lugs, rim) at the origin, axle along Z, outer
                            face toward +Z
  forklift_mast_inner.glb   inner mast channels, at home (fully lowered)
  forklift_carriage.glb     carriage, positioner, wear strip and both forks, at home (fork
                            bottoms on the ground)

Modifiers (bevels, wheel-arch booleans) are applied; lettering is converted to meshes first.
"""
import os

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models", "forklift")
COLL = "Forklift"

MOVING = {"ForkliftMastInner"}
CARRIAGE = {"ForkliftCarriage", "ForkliftPositioner", "ForkliftCarriageWear", "ForkliftForkL", "ForkliftForkR"}
WHEEL_PREFIXES = ("ForkliftDriveWheel", "ForkliftSteerWheel", "ForkliftDriveLugs", "ForkliftSteerLugs",
                  "ForkliftDriveRim", "ForkliftSteerRim")


def _texts_to_meshes():
    for o in list(bpy.data.collections[COLL].all_objects):
        if o.type == 'FONT':
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target='MESH')


def _export(path, objs):
    # select_all skips hidden objects, which then stay selected and get exported: clear all.
    # The exporter also sees selections in other scenes' view layers.
    for sc in bpy.data.scenes:
        for vl in sc.view_layers:
            for o in vl.objects:
                o.select_set(False, view_layer=vl)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='EXPORT', export_cameras=False,
                              export_lights=False, export_animations=False)
    return os.path.basename(path)


def export_all():
    os.makedirs(OUT, exist_ok=True)
    _texts_to_meshes()
    objs = [o for o in bpy.data.collections[COLL].all_objects if o.type == 'MESH' and not o.hide_render]
    body = [o for o in objs if o.name not in MOVING | CARRIAGE and not o.name.startswith(WHEEL_PREFIXES)]
    out = [_export(os.path.join(OUT, "forklift_body.glb"), body),
           _export(os.path.join(OUT, "forklift_mast_inner.glb"), [bpy.data.objects[n] for n in MOVING]),
           _export(os.path.join(OUT, "forklift_carriage.glb"), [bpy.data.objects[n] for n in CARRIAGE])]
    # One wheel, moved to the origin with no rotation: its outer face is toward +Z.
    w = bpy.data.objects["ForkliftDriveWheelL"]
    loc, rot = w.location.copy(), w.rotation_euler.copy()
    w.location = (0.0, 0.0, 0.0)
    w.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    try:
        out.append(_export(os.path.join(OUT, "forklift_wheel.glb"), [w] + list(w.children)))
    finally:
        w.location, w.rotation_euler = loc, rot
    return out
