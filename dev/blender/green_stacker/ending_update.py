"""Add (or rebuild) only the far-end ending rolls and fence in the sorter .blend, render review
stills and export their glbs, leaving the rest of the stacker as it is. Run in background:

  blender -b dev/blender/bin_sorter/bin_sorter_10bay.blend --python dev/blender/green_stacker/ending_update.py -- [--save] [--no-export]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stacker_build as B  # noqa: E402
import stacker_export as X  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NAMES = ("EndingGate", "EndingGateRods", "FarFence", "FarFencePosts", "FarFenceCylinders", "ShortBoardSkids", "EndingLift", "EndingLiftBearings", "EndingLiftRods",
         "EndingRoll", "LayerStops", "LayerStopsGuides") + tuple("EndingRoll_%d" % i for i in range(len(B.END_Z)))
MAT = {"green": "Sorter_FrameGreen", "orange": "Sorter_SafetyOrange", "grey": "Sorter_MotorGrey",
       "deck": "Sorter_DeckSteel", "uhmw": "Sorter_UHMW", "chain": "Sorter_ChainSteel", "shaft": "Sorter_MachinedSteel", "drum": "Stacker_DrumShell"}


def rebuild():
    for n in NAMES:
        o = bpy.data.objects.get(n)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
    M = {k: bpy.data.materials[v] for k, v in MAT.items()}
    coll = bpy.data.collections[B.COLL]
    parts = bpy.data.collections["StackerParts"]
    B.build_far_fence(coll, M)
    B.build_ending_lift(coll, M)
    B.build_ending_gate(coll, M)
    B.build_ending_preview(coll, B.build_ending_rolls(parts, M))
    B.build_pop_stops(coll, M, "LayerStops", B.LAYER_STOP_X, B.LAYER_STOP_Z)
    # The unscrambler (its side guards): every object build_unscrambler makes, shafts included.
    for n in ("UnscramblerFrame", "UnscramblerBed", "UnscramblerWearStrips", "UnscramblerDrive",
              "UnscramblerHeadShaft", "UnscramblerFootShaft"):
        o = bpy.data.objects.get(n)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
    B.build_unscrambler(coll, M)
    # The infeed (its fence flare). The sorter owns "InfeedDrive", so the stacker's comes out as
    # "InfeedDrive.001" again, the name stacker_export expects.
    for n in ("InfeedFrame", "InfeedPlates", "InfeedWearStrips", "InfeedDrive.001", "InfeedHeadShaft", "InfeedTailSprockets"):
        o = bpy.data.objects.get(n)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
    B.build_infeed(coll, M)
    assert bpy.data.objects.get("InfeedDrive.001") is not None


def render(path, eye, target, lens=24):
    scene = bpy.data.scenes["Scene"]
    cam_data = bpy.data.cameras.new("EndingReviewCam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("EndingReviewCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = B.G(*eye)
    d = B.G(*target) - B.G(*eye)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=scene.name)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_data)


rebuild()
renders = os.path.join(HERE, "renders")
os.makedirs(renders, exist_ok=True)
scene = bpy.data.scenes["Scene"]
# Review stills with what's over and beside the forming section hidden (catwalks, stick
# frame, divider gantry, preview lumber): from above the +Z side, and low from the -Z side.
HIDE = [o for o in bpy.data.collections[B.COLL].all_objects if o.name.startswith(
    ("Catwalk", "StickFrame", "StickMagazines", "PackageGuide", "CourseDivider", "Preview", "HoldoverRack", "Hoist",
     "PullbackFence", "StickGate"))]
for o in HIDE:
    o.hide_render = True
if "--no-render" not in ARGS:
    render(os.path.join(renders, "ending_overview.png"), (28.1, 5.2, 4.6), (28.1, 2.5, 0.4), 20)
if "--no-render" not in ARGS:
    render(os.path.join(renders, "ending_far_close.png"), (29.6, 3.3, 3.6), (28.0, 2.5, 2.1), 24)
if "--no-render" not in ARGS:
    render(os.path.join(renders, "ending_under.png"), (28.0, 3.2, -4.2), (28.1, 2.35, 0.8), 22)
for o in HIDE:
    o.hide_render = False
result = {}
if "--no-export" not in ARGS:
    result["exported"] = X.export_ending() + X.export_layer_stops()
if "--save" in ARGS:
    bpy.ops.wm.save_mainfile()
    result["saved"] = bpy.data.filepath
print("ENDING_UPDATE", result)
