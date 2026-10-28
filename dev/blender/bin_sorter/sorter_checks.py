"""Board-path clearance checks for the bin sorter.

Sweeps the space a board (or a finished stack) occupies along each leg of its
journey and reports every part that intrudes. Coordinates are game-local
(see sorter_build.G).
"""
import bmesh
import bpy
from mathutils.bvhtree import BVHTree

import sorter_build as S

BOARD_HALF_LEN = 2.5        # 16 ft board plus end jitter
BOARD_MAX_T = 0.04          # 2x lumber plus a little
STACK_H = 0.40              # 10 boards of 2x


def _box_tree(p0, p1):
    bm = bmesh.new()
    S.gbox_span(bm, p0, p1)
    bm.verts.ensure_lookup_table()
    verts = [v.co.copy() for v in bm.verts]
    polys = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return BVHTree.FromPolygons(verts, polys)


def _object_trees(exclude):
    dg = bpy.context.evaluated_depsgraph_get()
    out = {}
    for o in bpy.data.objects:
        if o.type != 'MESH' or o.hide_render or o.name == "Floor":
            continue
        if any(o.name == e or (e.endswith("*") and o.name.startswith(e[:-1])) for e in exclude):
            continue
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        mw = o.matrix_world
        out[o.name] = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        e.to_mesh_clear()
    return out


def sweep(name, p0, p1, exclude):
    """Return the parts intersecting the box swept between Godot corners p0 and p1."""
    env = _box_tree(p0, p1)
    trees = _object_trees(list(exclude) + ["PreviewLumber"])
    hits = {n: len(env.overlap(t)) for n, t in trees.items()}
    return {"leg": name, "blocked_by": {n: c for n, c in hits.items() if c}}


def run(lowered_bay=4):
    y0 = S.DECK_Y + 0.002
    legs = [
        sweep("infeed transfer to stop", (S.CREST_X, y0, -BOARD_HALF_LEN), (S.STOP_X - 0.051, y0 + BOARD_MAX_T, BOARD_HALF_LEN),
              ["PreviewTopLugs"]),
        sweep("deck: stop to last bay", (S.STOP_X - 0.05, y0, -BOARD_HALF_LEN), (S.bay_x(S.NB - 1) + S.GATE_X0 + S.GATE_W, y0 + BOARD_MAX_T, BOARD_HALF_LEN),
              ["PreviewTopLugs", "InfeedStop"]),
    ]
    for i in range(S.NB):
        bx = S.bay_x(i)
        legs.append(sweep("drop into bay %d" % i, (bx + 0.3, S.CATCH_Y + 0.005, -BOARD_HALF_LEN), (bx + 0.9, S.DECK_Y - S.DECK_T - 0.005, BOARD_HALF_LEN),
                          ["Gate_%02d" % i]))
    for i, others_lowered in ((lowered_bay, True), (0, False)):
        bx = S.bay_x(i)
        exclude = [] if others_lowered else ["Carriage_%02d" % lowered_bay, "CarriageRollers_%02d" % lowered_bay]
        # From the stack's trailing edge on the tines to the end stops.
        legs.append(sweep("haul-out stack from bay %d" % i, (bx + 0.40, S.HAUL_TOP + 0.003, -BOARD_HALF_LEN),
                          (S.STACK_STOP_X - 0.002, S.HAUL_TOP + STACK_H, BOARD_HALF_LEN), exclude))
    return {"clear": all(not leg["blocked_by"] for leg in legs), "legs": [leg for leg in legs if leg["blocked_by"]] or "all clear"}
