"""Export the cant transfer and gang resaw to glTF for the game (run inside Blender after gr_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  gang_resaw_frame.glb   GR_Frame: transfer frame, stop, sharp chain bed, gang housing and drives,
                         outfeed base and end stop, chip duct
  gang_resaw_parts.glb   moving parts, each its own node: GR_TransferHead/Tail, GR_Turner,
                         GR_Press1..2 (> GR_PressRoll1..2), GR_TopArbor, GR_BottomArbor,
                         GR_ChipHeadNear/Far, GR_Lift (> GR_ORoll1..n)

The transfer and sharp chains reuse the log deck's chain links (log_deck_chain.glb).
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import gr_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "gang_resaw")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    HE._set_viewport_colours()
    D.pose()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None]
    frame = [o for o in tops if o.name == "GR_Frame"]
    parts = [o for o in tops if o not in frame]
    out = {}
    for name, roots in (("frame", frame), ("parts", parts)):
        fn = "gang_resaw_%s.glb" % name
        out[fn] = HE._export(roots, os.path.join(OUT, fn))
    return out
