"""Export the green stacker to glTF for the game (run inside Blender after stacker_build).

Every mesh is written in the sorter-local Godot frame (see sorter_build.G); the stacker
shares the sorter's frame, so the game places it with the sorter's own transform.

  stacker_frame.glb       everything that never moves, plus the chain shafts as separate
                          nodes (origin on the shaft axis, spun about Z)
  stacker_<part>.glb      each moving part at its home position (location zeroed), in
                          stacker coordinates: the game moves it by offsets from home
  stacker_link.glb        heavy bar chain link; stacker_uns_lug.glb the unscrambler lug
  stacker_roll.glb        one line-up drum roll, origin on its axis
  stacker_stick.glb       one stick

Materials go out as their viewport colours (sorter_export.VIEWPORT plus the stacker's own).
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "bin_sorter"))
import sorter_export as SE  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "green_stacker")

STATIC = (
    "SurgeFrame", "SurgeWearStrips", "SurgeStopBases", "SurgeHeadShaft", "SurgeTailShaft",
    "UnscramblerFrame", "UnscramblerBed", "UnscramblerWearStrips", "UnscramblerDrive",
    "UnscramblerHeadShaft", "UnscramblerFootShaft",
    "InfeedFrame", "InfeedPlates", "InfeedWearStrips", "InfeedDrive.001", "InfeedHeadShaft", "InfeedTailSprockets",
    "LayerStopsGuides", "CourseDividerFrame", "HoldoverRack", "PocketAdjusterCylinders", "ForkRails", "ForkDrive", "StickFrame", "StickMagazines",
    "PackageGuides", "PackageGuideHangers",
    "HoistBase", "LandingBase", "OutfeedFrame", "OutfeedWearStrips", "OutfeedHeadShaft", "OutfeedTailShaft",
    "CatwalkFrame", "CatwalkGrating.001", "CatwalkRails.001",
)
MOVING = {
    "stacker_surge_stop.glb": ("SurgeStop",),
    "stacker_layer_stops.glb": ("LayerStops",),
    "stacker_course_divider.glb": ("CourseDivider", "CourseDividerRods"),
    "stacker_pocket_adjusters.glb": ("PocketAdjusters", "PocketAdjusterRods"),
    "stacker_forks.glb": ("Forks", "ForkWear"),
    "stacker_fork_trolley.glb": ("ForkTrolley", "ForkTrolleyGear"),
    "stacker_fence.glb": ("PullbackFence",),
    "stacker_stick_gates.glb": ("StickGates", "StickGateRods"),
    "stacker_hoist.glb": ("Hoist", "HoistRods"),
    "stacker_landing_lift.glb": ("LandingLift", "LandingLiftRods"),
    "stacker_ending_lift.glb": ("EndingLift", "EndingLiftBearings", "EndingLiftRods"),
}
# Static parts in their own files, in stacker coordinates.
STATIC_PARTS = {
    "stacker_far_fence.glb": ("FarFence", "FarFencePosts", "FarFenceCylinders", "ShortBoardSkids"),
}
PARTS = {
    "stacker_link.glb": ("BarChainLink",),
    "stacker_uns_lug.glb": ("UnscramblerLug",),
    "stacker_roll.glb": ("LineupRoll",),
    "stacker_ending_roll.glb": ("EndingRoll",),
    "stacker_stick.glb": ("Stick",),
}
VIEWPORT = {
    "Stacker_DrumShell": ((0.06, 0.06, 0.065), 0.6, 0.45),
    "Stacker_Sticks": ((0.06, 0.04, 0.025), 0.0, 0.8),
}


def export_all():
    os.makedirs(OUT, exist_ok=True)
    SE._set_viewport_colours()
    for name, (rgb, metal, rough) in VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough
    out = [SE._export(os.path.join(OUT, "stacker_frame.glb"), STATIC, False)]
    for fname, names in MOVING.items():
        # Zero only the root; parented children (rods) keep their offsets.
        out.append(SE._export(os.path.join(OUT, fname), names[:1], True) if len(names) == 1 else
                   _export_rooted(os.path.join(OUT, fname), names))
    for fname, names in STATIC_PARTS.items():
        out.append(SE._export(os.path.join(OUT, fname), names, False))
    for fname, names in PARTS.items():
        out.append(SE._export(os.path.join(OUT, fname), names, True))
    return [os.path.basename(p) for p in out]


def export_ending():
    """Only the far-end ending parts (stacker_build.build_ending_lift / build_far_fence /
    build_ending_rolls), leaving every other stacker glb as it is."""
    os.makedirs(OUT, exist_ok=True)
    SE._set_viewport_colours()
    for name, (rgb, metal, rough) in VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough
    out = [_export_rooted(os.path.join(OUT, "stacker_ending_lift.glb"), MOVING["stacker_ending_lift.glb"])]
    for fname, names in STATIC_PARTS.items():
        out.append(SE._export(os.path.join(OUT, fname), names, False))
    out.append(SE._export(os.path.join(OUT, "stacker_ending_roll.glb"), PARTS["stacker_ending_roll.glb"], True))
    return [os.path.basename(p) for p in out]


def export_layer_stops():
    """The layer stops (moving) and the static frame, which holds their cylinder guides."""
    SE._set_viewport_colours()
    for name, (rgb, metal, rough) in VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough
    out = [SE._export(os.path.join(OUT, "stacker_frame.glb"), STATIC, False),
           SE._export(os.path.join(OUT, "stacker_layer_stops.glb"), MOVING["stacker_layer_stops.glb"], True)]
    return [os.path.basename(p) for p in out]


def _export_rooted(path, names):
    """Export a moving part whose extra objects are either parented to the first (rods) or
    sit unparented in the same stacker coordinates (wear strips, gear): the root goes to its
    home (location zeroed) and unparented extras keep theirs."""
    root = bpy.data.objects[names[0]]
    saved = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    try:
        return SE._export(path, names, False)
    finally:
        root.location = saved
