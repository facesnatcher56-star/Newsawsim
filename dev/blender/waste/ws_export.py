"""Export the waste system to glTF for the game (run inside Blender after ws_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  waste_frame.glb    WS_Frame: slasher frames and guards, pan bases and springs, chipper, pipe, cyclone, bin
  waste_parts.glb    moving parts, each its own node: WS_Pan1..6, WS_SlabArbor, WS_EdgeArborNear/Far,
                     the slasher chain shafts, WS_FeedRoll, WS_Drum

The slasher chains reuse the board line's roller chain link (board_line_roller_link.glb).
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import ws_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "waste")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    HE._set_viewport_colours()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None]
    frame = [o for o in tops if o.name == "WS_Frame"]
    parts = [o for o in tops if o not in frame]
    out = {}
    for name, roots in (("frame", frame), ("parts", parts)):
        fn = "waste_%s.glb" % name
        out[fn] = HE._export(roots, os.path.join(OUT, fn))
    return out
