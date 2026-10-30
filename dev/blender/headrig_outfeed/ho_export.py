"""Export the headrig outfeed to glTF for the game (run inside Blender after ho_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  headrig_outfeed_frame.glb    HO_Frame: roll case, end stop, skids, slab trough, chipper, chip pipe
  headrig_outfeed_parts.glb    moving parts, each its own node: HO_Roll1..n, HO_SlabKick, HO_CantKick,
                               HO_BoardKick, their Cyl/Rod, HO_TroughHead/Tail, HO_FeedRoll
  headrig_outfeed_flight.glb   HO_Flight: one slab-chain flight, for instancing
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import ho_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "headrig_outfeed")


def export_all():
    os.makedirs(OUT, exist_ok=True)
    HE._set_viewport_colours()
    D.pose()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None and not o.name.startswith("HO_Preview")]
    frame = [o for o in tops if o.name == "HO_Frame"]
    flight = [o for o in tops if o.name == "HO_Flight"]
    parts = [o for o in tops if o not in frame and o not in flight]
    out = {}
    for name, roots in (("frame", frame), ("parts", parts), ("flight", flight)):
        fn = "headrig_outfeed_%s.glb" % name
        out[fn] = HE._export(roots, os.path.join(OUT, fn))
    return out
