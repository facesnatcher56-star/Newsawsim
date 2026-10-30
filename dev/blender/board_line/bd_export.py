"""Export the raised deck, lug loader and scanner chains to glTF (run inside Blender after bd_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  board_deck_frame.glb     BD_Frame: deck, chain frames, fence, scanner, stop cylinders, actuators
  board_deck_parts.glb     moving parts, each its own node: BD_LugTail/Head, BD_ScanTail/Head,
                           BD_StopsHalf/End, BD_Flipper, BD_ZeroRoll1..n
  board_deck_lug.glb       BD_ScanLug: one scanner chain lug, for instancing
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import bd_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "board_line")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    HE._set_viewport_colours()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None]
    frame = [o for o in tops if o.name == "BD_Frame"]
    lug = [o for o in tops if o.name == "BD_ScanLug"]
    parts = [o for o in tops if o not in frame and o not in lug]
    out = {}
    for name, roots in (("frame", frame), ("parts", parts), ("lug", lug)):
        fn = "board_deck_%s.glb" % name
        out[fn] = HE._export(roots, os.path.join(OUT, fn))
    return out
