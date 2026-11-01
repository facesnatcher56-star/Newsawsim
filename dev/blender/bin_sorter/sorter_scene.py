"""Review scene for the bin sorter: gates and carriages placed per bay, lumber, floor, light, cameras."""
import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
import mesh_lib as L  # noqa: E402
import sorter_build as S  # noqa: E402

COLL = "SorterPreview"
INCH = 0.0254
# Nominal size -> (thickness, width) in metres; bay index = list index.
SIZES = [(0.75, 3.5), (0.75, 5.5), (0.75, 7.25), (0.75, 9.25), (0.75, 11.25),
         (1.5, 3.5), (1.5, 5.5), (1.5, 7.25), (1.5, 9.25), (1.5, 11.25)]
BOARD_LEN = 4.877


def board(bm, x_centre, y_bottom, t, w):
    # Each board is drawn 2 mm thinner than its slot so stacked boards show their seams.
    S.gbox(bm, (x_centre, y_bottom + t / 2, 0.0), (w, t - 0.002, BOARD_LEN))


EMPTY = (0,) * S.NB
DEMO_STACKS = (4, 9, 2, 6, 10, 0, 7, 3, 5, 1)   # review renders only: build(M, 3, DEMO_STACKS, True)


def build(M, open_gate=None, stacks=EMPTY, demo_lumber=False):
    """Machine as it ships: every bay empty, carriages at the catch height, gates shut.

    Lumber, part-filled bays and an open gate are opt-in for review renders only;
    the sorter itself never carries boards.
    """
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    gate = bpy.data.objects["Gate"]
    carriage = bpy.data.objects["Carriage"]
    rollers = bpy.data.objects["CarriageRollers"]
    lumber = bmesh.new()
    cables = bmesh.new()
    cylinders = bmesh.new()
    rods = bmesh.new()
    for i in range(S.NB):
        bx = S.bay_x(i)
        angle = 42.0 if i == open_gate else 0.0
        L.link_copy(gate, "Gate_%02d" % i, coll, S.G(bx + S.GATE_X0, S.DECK_Y + S.GATE_AXIS_DY, 0.0), (0, angle, 0))
        # Gate cylinders: barrel on the deck-beam clevis, rod to the lever pin.
        (px, py), (ax, ay) = S.gate_pin_world(i, angle), S.gate_anchor_world(i)
        for z in (-S.GATE_CYL_Z, S.GATE_CYL_Z):
            mid = (ax + (px - ax) * 0.55, ay + (py - ay) * 0.55)
            S.grod(cylinders, (ax, ay, z), (*mid, z), 0.035, segs=14)
            S.grod(rods, (*mid, z), (px, py, z), 0.014, segs=8)
        t, w = SIZES[i][0] * INCH, SIZES[i][1] * INCH
        n = stacks[i]
        full = n >= 10
        y = S.HAUL_TOP - 0.1 if full else S.CATCH_Y - n * t
        for src, name in ((carriage, "Carriage_%02d"), (rollers, "CarriageRollers_%02d")):
            L.link_copy(src, name % i, coll, S.G(bx + S.CARRIAGE_X, y, 0.0))
        # Hoist cables from the drums straight down to the carriage shackles.
        for z in (-S.END_BLOCK_Z, S.END_BLOCK_Z):
            S.grod(cables, (S.cable_x(i), S.HOIST_Y, z), (S.cable_x(i), y + S.HANG_H + 0.30, z), 0.008, segs=6)
        if demo_lumber:
            base = S.HAUL_TOP if full else y
            for k in range(n):
                jitter = 0.012 * math.sin(i * 7.1 + k * 3.3)
                board(lumber, bx + 0.55 + jitter, base + k * t, t, w)
    if demo_lumber:
        # A board being pushed toward its bay, one waiting at the stop, one on the rolls,
        # and a finished stack out on the end table against the stops.
        board(lumber, S.bay_x(2) + 0.62, S.DECK_Y, 1.5 * INCH, 7.25 * INCH)
        board(lumber, S.STOP_X - 0.05 - 5.5 * INCH / 2, S.DECK_Y, 1.5 * INCH, 5.5 * INCH)
        board(lumber, -0.3, S.DECK_Y, 1.5 * INCH, 9.25 * INCH)
        for k in range(10):
            board(lumber, S.STACK_STOP_X - 0.003 - 9.25 * INCH / 2, S.HAUL_TOP + k * 1.5 * INCH, 1.5 * INCH, 9.25 * INCH)
    L.make_object("HoistCables", cables, coll, [M["chain"]], weighted=False)
    L.make_object("GateCylinders", cylinders, coll, [M["grey"]], weighted=False)
    L.make_object("GateRods", rods, coll, [M["shaft"]], weighted=False)
    if lumber.verts:
        o = L.make_object("PreviewLumber", lumber, coll, [M["lumber"]], bevel=0.002, bevel_segments=1, weighted=False)
        o.data.polygons.foreach_set("use_smooth", [False] * len(o.data.polygons))
    else:
        lumber.free()

    # Floor slab, open over the haul-out pit (Blender axes: x, -z, y).
    me = bpy.data.meshes.new("Floor")
    s = 60.0
    x0, x1 = S.PIT_X0 - S.PIT_WALL, S.PIT_X1 + S.PIT_WALL
    z0 = S.PIT_Z + S.PIT_WALL
    verts, faces = [], []
    for (a0, b0, a1, b1) in ((-s, -s, x0, s), (x1, -s, s, s), (x0, -s, x1, -z0), (x0, z0, x1, s)):
        k = len(verts)
        verts += [(a0, b0, 0), (a1, b0, 0), (a1, b1, 0), (a0, b1, 0)]
        faces.append((k, k + 1, k + 2, k + 3))
    me.from_pydata(verts, [], faces)
    me.materials.append(M["concrete"])
    floor = bpy.data.objects.new("Floor", me)
    coll.objects.link(floor)
    return coll


def lighting(coll):
    scene = bpy.context.scene
    world = bpy.data.worlds.get("Sorter_World") or bpy.data.worlds.new("Sorter_World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new('ShaderNodeTexSky')
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_disc = False
    sky.sun_elevation = math.radians(35)
    sky.sun_rotation = math.radians(-60)
    bg = nt.nodes.new('ShaderNodeBackground')
    bg.inputs['Strength'].default_value = 0.15
    out = nt.nodes.new('ShaderNodeOutputWorld')
    nt.links.new(sky.outputs['Color'], bg.inputs['Color'])
    nt.links.new(bg.outputs['Background'], out.inputs['Surface'])
    sun = bpy.data.lights.new("SorterSun", 'SUN')
    sun.energy = 3.0
    sun.angle = math.radians(2)
    sun.color = (1.0, 0.95, 0.88)
    so = bpy.data.objects.new("SorterSun", sun)
    coll.objects.link(so)
    so.rotation_euler = (math.radians(55), 0, math.radians(30))


def camera(coll, name, loc, target, lens=35):
    t = bpy.data.objects.new(name + "_Target", None)
    coll.objects.link(t)
    t.location = target
    data = bpy.data.cameras.new(name)
    data.lens = lens
    cam = bpy.data.objects.new(name, data)
    coll.objects.link(cam)
    cam.location = loc
    c = cam.constraints.new('TRACK_TO')
    c.target = t
    return cam


def setup_render(samples=96, res=(1600, 900)):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    scene.cycles.device = 'GPU' if prefs.compute_device_type != 'NONE' else 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    vs = scene.view_settings
    vs.view_transform = 'AgX'
    try:
        vs.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass
    vs.exposure = -0.2


def build_all(M):
    coll = build(M)
    lighting(coll)
    # Blender coordinates: X along the sorter, -Y is the catwalk side (game +Z), Z up.
    cams = {
        "Overview": camera(coll, "Cam_Overview", (-6.5, -13.0, 6.5), (6.2, 0.0, 2.6), 28),
        "Bays": camera(coll, "Cam_Bays", (3.6, -7.8, 5.6), (6.0, 0.0, 2.2), 26),
        "Drive": camera(coll, "Cam_Drive", (15.5, -6.0, 6.8), (12.0, 0.0, 4.9), 30),
        "Infeed": camera(coll, "Cam_Infeed", (-3.4, -4.2, 5.6), (0.6, 0.0, 4.3), 26),
        "Stacks": camera(coll, "Cam_Stacks", (-1.6, 1.6, 2.6), (7.0, -0.4, 1.9), 22),
        "HaulEnd": camera(coll, "Cam_HaulEnd", (17.8, -4.6, 2.2), (13.6, 0.0, 0.4), 30),
        "Pit": camera(coll, "Cam_Pit", (8.0, -8.5, 3.4), (10.5, 0.0, -1.0), 24),
        "Lift": camera(coll, "Cam_Lift", (16.6, -6.5, 1.6), (13.9, 0.0, -0.9), 26),
    }
    setup_render()
    bpy.context.scene.camera = cams["Overview"]
    return {name: c.name for name, c in cams.items()}
