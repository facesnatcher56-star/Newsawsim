"""Render stage for inspecting the log deck (run inside Blender after ld_build).

Reuses the knuckleboom render setup, lines the ring debarker up with the deck the way the
mill has it (ring at Godot x 5.165, infeed line at Godot z 2.118) and lays stand-in logs on
the chains, the feeder steps and the infeed.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "knuckle_boom"))
import kbl_scene as KS  # noqa: E402

import ld_build as D  # noqa: E402

RENDERS = os.path.join(HERE, "renders")
DEBARKER_ROOTS = ("DB_Machine", "IN", "OUT", "BB_BarkBelt", "BIN_Root")


def setup(samples=40):
    cam = KS.setup(samples=samples)
    bpy.context.scene.view_settings.exposure = -1.6
    for name in DEBARKER_ROOTS:
        o = bpy.data.objects.get(name)
        if o is not None:
            o.location = (5.165, -D.LINE_Z, 0.0)
    return cam


def restore_debarker():
    for name in DEBARKER_ROOTS:
        o = bpy.data.objects.get(name)
        if o is not None:
            o.location = (0.0, 0.0, 0.0)


def _log(name):
    log = bpy.data.objects.get(name)
    if log is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=D.LOG_R, depth=D.LOG_LEN, vertices=40)
        log = bpy.context.active_object
        log.name = name
        log.rotation_euler = (0, math.radians(90), 0)
        import materials_lib as ML
        mat = bpy.data.materials.get("LD_PreviewBark") or ML.simple("LD_PreviewBark", (0.12, 0.06, 0.03), 0.95, 0.0, 20, 0.6)
        log.data.materials.append(mat)
    return log


def place_logs(lift=0.0):
    """Logs packed on the chains, one on every feeder step and one in the infeed V."""
    spots = []
    for k in range(8):
        bz = 0.30 + k * 0.62
        spots.append(D.bed_to_godot(0.0, D.LOG_R, bz))
    for k in (1, 2, 3):
        spots.append((D.C, D.CN[k] + D.LOG_R + 0.015 + lift * 0, D.A[k + 1] + 0.30))
    spots.append((D.C + 0.6, D.LINE_Y, D.LINE_Z))
    for i, (x, y, z) in enumerate(spots):
        _log("LD_PreviewLog%d" % i).location = D.G(x, y, z)
    return len(spots)


def chain_loop(s):
    """Bed-local (y, z, tangent_y, tangent_z) at distance s round a chain loop; the top run
    travels towards the feeder (-z). Same path as live_log_deck.gd."""
    r = D.SPROCKET_R
    run = D.TAIL_Z - D.HEAD_Z
    total = 2 * run + 2 * math.pi * r
    s %= total
    if s < run:
        return D.CHAIN_Y, D.TAIL_Z - s, 0.0, -1.0
    s -= run
    if s < math.pi * r:
        a = s / r
        return D.SHAFT_Y + r * math.cos(a), D.HEAD_Z - r * math.sin(a), -math.sin(a), -math.cos(a)
    s -= math.pi * r
    if s < run:
        return D.SHAFT_Y - r, D.HEAD_Z + s, 0.0, 1.0
    a = (s - run) / r
    return D.SHAFT_Y - r * math.cos(a), D.TAIL_Z + r * math.sin(a), math.sin(a), math.cos(a)


def chain_preview(show=True):
    """Linked copies of the chain links round every strand (preview only, not exported)."""
    from mathutils import Matrix
    coll = bpy.data.collections[D.COLL]
    for o in [o for o in bpy.data.objects if o.name.startswith("LD_PreviewChain")]:
        bpy.data.objects.remove(o)
    if not show:
        return 0
    bed = bpy.data.objects["LD_Bed"]
    link = bpy.data.objects["LD_ChainLink"]
    dog = bpy.data.objects["LD_ChainDog"]
    total = 2 * (D.TAIL_Z - D.HEAD_Z) + 2 * math.pi * D.SPROCKET_R
    n = round(total / D.CHAIN_PITCH)
    pitch = total / n
    conv = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    count = 0
    for x in D.STRANDS:
        for i in range(n):
            y, z, ty, tz = chain_loop(i * pitch)
            # Godot link basis: X across, Y out of the loop (dogs up on the top run), Z back
            # along the travel.
            t = Vector((0, ty, tz))
            out = Vector((1, 0, 0)).cross(t)
            gb = Matrix((Vector((1, 0, 0)), out, -t)).transposed()
            src = dog if i % 4 == 0 else link
            o = bpy.data.objects.new("LD_PreviewChain", src.data)
            coll.objects.link(o)
            o.parent = bed
            m = (conv @ gb @ conv.inverted()).to_4x4()
            m.translation = D.B(x, y, z)
            o.matrix_basis = m
            count += 1
    return count


def look(cam, eye_g, target_g, lens=35):
    KS.look(cam, D.G(*eye_g), D.G(*target_g), lens)


def render(name):
    os.makedirs(RENDERS, exist_ok=True)
    path = os.path.join(RENDERS, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
