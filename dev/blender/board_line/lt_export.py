"""Export the landing table and transfer to glTF (run inside Blender after lt_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  board_landing_frame.glb   LT_Frame
  board_landing_parts.glb   LT_Lift (> LT_Roll1..n), LT_Tail, LT_Head
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import lt_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "board_line")


def export_all():
    HE._set_viewport_colours()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None]
    frame = [o for o in tops if o.name == "LT_Frame"]
    parts = [o for o in tops if o not in frame]
    return {fn: HE._export(roots, os.path.join(OUT, fn))
            for fn, roots in (("board_landing_frame.glb", frame), ("board_landing_parts.glb", parts))}
