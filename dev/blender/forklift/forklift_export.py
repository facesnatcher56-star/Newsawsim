"""Export the forklift to glTF for the game (run inside Blender after forklift_build.build).

Every mesh is in the forklift-local Godot frame (+X forward, origin on the ground under the
middle of the drive axle), which the +Y-up glTF export keeps.

  forklift_body.glb         everything fixed to the frame: body, cab, outer mast, fittings
  forklift_wheel.glb        one drive wheel (tyre, lugs, rim) at the origin, axle along Z, outer
                            face toward +Z; forklift.gd scales it down for the steer wheels
  forklift_mast_inner.glb   inner mast channels, crosshead, lift cylinder rods, sheaves and
                            chains, at home (fully lowered)
  forklift_carriage.glb     carriage, positioner, wear strip and both forks, at home (fork
                            bottoms on the ground)

Materials go out as their viewport colours (export_materials='VIEWPORT'): node materials
would arrive in Godot white and metallic. Modifiers (bevels, booleans) are applied; lettering
is converted to meshes first.
"""
import os

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models", "forklift")
COLL = "Forklift"

# Viewport colours (linear), metallic, roughness written into the glTF materials. Glass keeps
# its alpha (forklift.gd makes it see-through).
VIEWPORT = {
    "Forklift_Yellow": ((0.78, 0.58, 0.035), 0.0, 0.45),
    "Forklift_Charcoal": ((0.030, 0.032, 0.035), 0.0, 0.6),
    "Forklift_MastGrey": ((0.045, 0.045, 0.047), 0.1, 0.6),
    "Forklift_ForkSteel": ((0.07, 0.07, 0.07), 0.2, 0.55),
    "Forklift_Tyre": ((0.012, 0.012, 0.012), 0.0, 0.9),
    "Forklift_Rim": ((0.36, 0.36, 0.34), 0.1, 0.55),
    "Forklift_Tread": ((0.38, 0.38, 0.38), 0.3, 0.45),
    "Forklift_Glass": ((0.10, 0.13, 0.14), 0.0, 0.08),
    "Forklift_Lamp": ((0.95, 0.95, 0.92), 0.0, 0.2),
    "Forklift_Amber": ((1.0, 0.45, 0.02), 0.0, 0.2),
    "Forklift_RedLamp": ((0.7, 0.02, 0.01), 0.0, 0.2),
    "Forklift_Chain": ((0.10, 0.09, 0.08), 0.3, 0.55),
    "Forklift_Rod": ((0.55, 0.55, 0.55), 0.4, 0.25),
    "Forklift_Black": ((0.006, 0.006, 0.006), 0.0, 0.7),
    "Forklift_Navy": ((0.010, 0.014, 0.035), 0.0, 0.5),
    "Forklift_DecalRed": ((0.45, 0.015, 0.02), 0.0, 0.5),
}


def _set_viewport_colours():
    for name, (rgb, metal, rough) in VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, m.diffuse_color[3])
            m.metallic = metal
            m.roughness = rough


def _texts_to_meshes():
    for o in list(bpy.data.collections[COLL].all_objects):
        if o.type == 'FONT':
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target='MESH')


def _tree(name):
    o = bpy.data.objects[name]
    return [o] + [c for c in o.children_recursive if c.type == 'MESH']


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
                              export_apply=True, export_materials='VIEWPORT', export_cameras=False,
                              export_lights=False, export_animations=False)
    return os.path.basename(path)


def export_all():
    """Run with the ForkliftStudio scene active in the window (the exporter works on the
    window's view layer); see export_in_studio()."""
    os.makedirs(OUT, exist_ok=True)
    _set_viewport_colours()
    _texts_to_meshes()
    inner, carriage = _tree("ForkliftMastInner"), _tree("ForkliftCarriage")
    moving = {o.name for o in inner + carriage}
    objs = [o for o in bpy.data.collections[COLL].all_objects if o.type == 'MESH' and not o.hide_render]
    body = [o for o in objs if o.name not in moving and not o.name.startswith(("ForkliftDrive", "ForkliftSteer"))]
    out = [_export(os.path.join(OUT, "forklift_body.glb"), body),
           _export(os.path.join(OUT, "forklift_mast_inner.glb"), inner),
           _export(os.path.join(OUT, "forklift_carriage.glb"), carriage)]
    # One wheel, moved to the origin with no rotation: its outer face is toward +Z.
    w = bpy.data.objects["ForkliftDriveWheelL"]
    loc, rot, par = w.location.copy(), w.rotation_euler.copy(), w.parent
    w.parent = None
    w.location = (0.0, 0.0, 0.0)
    w.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    try:
        out.append(_export(os.path.join(OUT, "forklift_wheel.glb"), [w] + list(w.children)))
    finally:
        w.parent = par
        w.location, w.rotation_euler = loc, rot
    return out


def export_in_studio(studio="ForkliftStudio"):
    """Switch the window to the forklift's scene for the export, then back."""
    win = bpy.context.window
    prev = win.scene
    win.scene = bpy.data.scenes[studio]
    try:
        with bpy.context.temp_override(window=win, scene=win.scene, view_layer=win.scene.view_layers[0]):
            return export_all()
    finally:
        win.scene = prev
