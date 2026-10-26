"""Structural support check: every separate piece must trace a contact path to the floor.

Each mesh is split into its loose parts (islands). Islands that touch or overlap
(within ``gap`` metres) are linked; a breadth-first walk starts from every
island resting on the floor. Anything not reached is floating.
"""
from collections import defaultdict, deque

import bmesh
import bpy
from mathutils.bvhtree import BVHTree


def _islands(obj, depsgraph):
    eval_obj = obj.evaluated_get(depsgraph)
    me = eval_obj.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(obj.matrix_world)
    eval_obj.to_mesh_clear()
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, faces = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            faces.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        verts = {v.index: v.co.copy() for face in faces for v in face.verts}
        remap = {old: new for new, old in enumerate(verts)}
        polys = [tuple(remap[v.index] for v in face.verts) for face in faces]
        # Contact samples: corners alone miss flush faces whose corners overhang
        # each other, so add face centres and edge midpoints.
        samples = list(verts.values())
        samples += [face.calc_center_median() for face in faces]
        samples += [(e.verts[0].co + e.verts[1].co) / 2 for e in {e for face in faces for e in face.edges}]
        out.append((list(verts.values()), polys, samples))
    bm.free()
    return out


def _touching(a, b, gap):
    """Intersecting, or any vertex of one within ``gap`` of the other's surface.

    The overlap test alone misses parts that sit flush (a deck plate on a beam).
    """
    if a[1].overlap(b[1]):
        return True
    for src, dst in ((a, b), (b, a)):
        for v in src[4]:
            if dst[1].find_nearest(v, gap)[0] is not None:
                return True
    return False


def check(floor_z=0.0, gap=0.003, ignore=("Floor",), cell=1.0):
    dg = bpy.context.evaluated_depsgraph_get()
    pieces = []   # (object name, bvh, bbox min, bbox max)
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or obj.hide_render or obj.name in ignore:
            continue
        for verts, polys, samples in _islands(obj, dg):
            xs = [v.x for v in verts]
            ys = [v.y for v in verts]
            zs = [v.z for v in verts]
            lo = (min(xs) - gap, min(ys) - gap, min(zs) - gap)
            hi = (max(xs) + gap, max(ys) + gap, max(zs) + gap)
            pieces.append((obj.name, BVHTree.FromPolygons(verts, polys, epsilon=gap), lo, hi, samples))

    # Broad phase: hash bounding boxes into a coarse grid.
    grid = defaultdict(list)
    for i, (_, _, lo, hi, _) in enumerate(pieces):
        for gx in range(int(lo[0] // cell), int(hi[0] // cell) + 1):
            for gy in range(int(lo[1] // cell), int(hi[1] // cell) + 1):
                for gz in range(int(lo[2] // cell), int(hi[2] // cell) + 1):
                    grid[(gx, gy, gz)].append(i)
    links = defaultdict(set)
    tested = set()
    for members in grid.values():
        for a_i in range(len(members)):
            a = members[a_i]
            for b in members[a_i + 1:]:
                key = (a, b) if a < b else (b, a)
                if key in tested:
                    continue
                tested.add(key)
                la, ha = pieces[a][2], pieces[a][3]
                lb, hb = pieces[b][2], pieces[b][3]
                if any(ha[k] < lb[k] or hb[k] < la[k] for k in range(3)):
                    continue
                if _touching(pieces[a], pieces[b], gap):
                    links[a].add(b)
                    links[b].add(a)

    grounded = [i for i, p in enumerate(pieces) if p[2][2] <= floor_z + gap * 2]
    reached = set(grounded)
    queue = deque(grounded)
    while queue:
        cur = queue.popleft()
        for nxt in links[cur]:
            if nxt not in reached:
                reached.add(nxt)
                queue.append(nxt)

    floating = defaultdict(list)
    for i, (name, _, lo, hi, _) in enumerate(pieces):
        if i not in reached:
            centre = tuple(round((lo[k] + hi[k]) / 2, 2) for k in range(3))
            floating[name].append(centre)
    return {
        "pieces": len(pieces),
        "grounded_start": len(grounded),
        "floating_pieces": sum(len(v) for v in floating.values()),
        "floating_by_object": {k: {"count": len(v), "examples": v[:4]} for k, v in sorted(floating.items(), key=lambda kv: -len(kv[1]))},
    }
