"""Export the board line to glTF for the game (run inside Blender after bl_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  board_line_frame.glb     BL_Frame: all fixed steel
  board_line_parts.glb     shafts, each its own node (BL_FeedTail/Head, BL_UnsFoot/Head, BL_TakeTail/Head)
  board_line_carrier.glb   BL_Carrier: one unscrambler carrier bar with its lugs, for instancing

The chain links reuse the log deck's chain links (log_deck_chain.glb).
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import bl_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "board_line")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    HE._set_viewport_colours()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None]
    frame = [o for o in tops if o.name == "BL_Frame"]
    carrier = [o for o in tops if o.name == "BL_Carrier"]
    parts = [o for o in tops if o not in frame and o not in carrier]
    out = {}
    for name, roots in (("frame", frame), ("parts", parts), ("carrier", carrier)):
        fn = "board_line_%s.glb" % name
        out[fn] = HE._export(roots, os.path.join(OUT, fn))
    return out
