"""Export the 10-bay sorter to glTF for the game (run inside Blender after sorter_build).

Every mesh is already written in the sorter-local Godot frame (see sorter_build.G),
which the +Y-up glTF export converts back, so parts land in Godot unchanged.

  sorter_frame.glb        everything that never moves, plus the four chain shafts as
                          separate nodes (origin on the shaft axis, spun about Z)
  sorter_gate.glb         one gate, origin on its shaft axis
  sorter_carriage.glb     one fork carriage (Carriage + CarriageRollers), origin at the
                          tine tops, upstream end
  sorter_top_link.glb     overhead chain link; sorter_top_lug.glb is the link with its lug
  sorter_haul_link.glb    haul-out drag chain link
  sorter_infeed_stop.glb  pop-up stop rocker, in sorter coordinates
  sorter_lift.glb         pack lift deck (lowered) with its two chain shafts as child nodes,
                          in sorter coordinates; sorter_lift_rams.glb its rams' rods and sheaves

Materials go out as their viewport colours (export_materials='VIEWPORT'); the game's
sorter script swaps in its own StandardMaterial3Ds by material name.
"""
import os

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models", "bin_sorter")

STATIC = (
    "Frame", "DeckFixed", "DeckHinges", "DeckWearStrips", "BayFronts", "InfeedStand", "InfeedDrive",
    "TransferWearStrips", "TransferHeadShaft", "TransferTailSprockets",
    "ChainSupports", "RaceWearStrips", "CatwalkBrackets", "CatwalkGrating", "CatwalkRails",
    "Drives", "ChainGuards", "DriveBrackets", "Hoists", "EndTable", "HaulWearStrips",
    "TopDriveShaft", "TopTailShaft", "HaulDriveShaft", "HaulTailShaft",
    "Pit", "PitSteel", "PitLadder", "LiftFrame",
)
# Moving parts exported where they stand (sorter coordinates): the pack lift's deck lowered,
# with its chain shafts as child nodes, and the rams.
IN_PLACE = {
    "sorter_lift.glb": ("LiftDeck", "LiftWearStrips", "LiftHeadShaft", "LiftTailShaft"),
    "sorter_lift_rams.glb": ("LiftRams",),
}
PARTS = {
    "sorter_gate.glb": ("Gate",),
    "sorter_carriage.glb": ("Carriage", "CarriageRollers"),
    "sorter_top_link.glb": ("TopChainLink",),
    "sorter_top_lug.glb": ("TopChainLug",),
    "sorter_haul_link.glb": ("HaulChainLink",),
    "sorter_transfer_link.glb": ("TransferChainLink",),
}

# Viewport colours (linear) and finish written into the glTF materials.
VIEWPORT = {
    "Sorter_FrameGreen": ((0.03, 0.075, 0.048), 0.3, 0.6),
    "Sorter_SafetyOrange": ((0.55, 0.14, 0.02), 0.2, 0.55),
    "Sorter_SafetyYellow": ((0.6, 0.42, 0.02), 0.2, 0.55),
    "Sorter_MotorGrey": ((0.09, 0.1, 0.12), 0.3, 0.55),
    "Sorter_Galvanized": ((0.28, 0.28, 0.27), 0.7, 0.45),
    "Sorter_DeckSteel": ((0.3, 0.3, 0.3), 0.9, 0.35),
    "Sorter_ChainSteel": ((0.12, 0.12, 0.13), 0.9, 0.4),
    "Sorter_UHMW": ((0.75, 0.74, 0.7), 0.0, 0.35),
    "Sorter_MachinedSteel": ((0.5, 0.5, 0.5), 1.0, 0.3),
    "Sorter_Concrete": ((0.16, 0.155, 0.145), 0.0, 0.9),
}


def _set_viewport_colours():
    for name, (rgb, metal, rough) in VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough


def _export(path, names, at_origin):
    objs = [bpy.data.objects[n] for n in names]
    saved = [(o, o.location.copy(), o.hide_render, o.hide_get()) for o in objs]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        if at_origin:
            o.location = (0.0, 0.0, 0.0)
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='VIEWPORT', export_cameras=False,
                              export_lights=False, export_animations=False)
    for o, loc, hr, hv in saved:
        o.location = loc
        o.hide_render = hr
        o.hide_set(hv)
    return path


def export_all():
    os.makedirs(OUT, exist_ok=True)
    _set_viewport_colours()
    out = [_export(os.path.join(OUT, "sorter_frame.glb"), STATIC, False),
           _export(os.path.join(OUT, "sorter_infeed_stop.glb"), ("InfeedStop",), False)]
    for fname, names in PARTS.items():
        out.append(_export(os.path.join(OUT, fname), names, True))
    for fname, names in IN_PLACE.items():
        out.append(_export(os.path.join(OUT, fname), names, False))
    return [os.path.basename(p) for p in out]
