"""Procedural M4A3 (75) Sherman, roughly to scale. +X forward, +Y left, +Z up, metres."""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
import mesh_lib as L  # noqa: E402
from mesh_lib import mat  # noqa: E402

COLL = "M4A3_Sherman"

TRACK_Y = 1.10          # track centre line
WHEEL_R = 0.254         # 20 in road wheels
WHEEL_Z = 0.32
T = 0.06                # track thickness (plate + grousers)
PITCH = 0.152           # 6 in link pitch
BOGIES = (1.50, 0.0, -1.50)
WHEEL_DX = 0.31
SPROCKET = (2.62, 0.74, 0.31)   # x, z, pitch radius
IDLER = (-2.72, 0.50, 0.26)
HULL_W = 1.31           # half width of upper hull
LOWER_W = 0.80          # half width of lower hull between the tracks
SPONSON_Z = 1.12
DECK_REAR = (-2.80, 1.84)
DECK_FRONT = (1.95, 1.92)
GLACIS_BOTTOM = (2.82, 1.12)
TX = 0.25               # turret ring centre

GL_DIR = (Vector(GLACIS_BOTTOM) - Vector(DECK_FRONT)).normalized()
GL_N = Vector((-GL_DIR.y, GL_DIR.x))
GL_ANGLE = math.degrees(math.atan2(GL_N.x, GL_N.y))


def deck_z(x):
    (x0, z0), (x1, z1) = DECK_REAR, DECK_FRONT
    return z0 + (x - x0) / (x1 - x0) * (z1 - z0)


TZ = deck_z(TX)
ROOF_Z = TZ + 0.73


def glacis_matrix(t, y, offset=0.0, extra_rot=(0, 0, 0)):
    """Frame on the glacis: local X down the slope, Z out of the plate."""
    p = Vector(DECK_FRONT).lerp(Vector(GLACIS_BOTTOM), t) + GL_N * offset
    return mat((p.x, y, p.y), (0, GL_ANGLE, 0)) @ mat(rot=extra_rot)


def set_parent(obj, parent):
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()


def empty(name, coll, loc=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.5
    coll.objects.link(obj)
    obj.location = loc
    bpy.context.view_layer.update()
    if parent is not None:
        set_parent(obj, parent)
    return obj


# ---------------------------------------------------------------------------
# Hull

def build_hull(coll, M, root):
    bm = bmesh.new()
    upper = [(-2.92, SPONSON_Z), GLACIS_BOTTOM, DECK_FRONT, DECK_REAR, (-2.96, 1.62)]
    L.add_prism(bm, upper, -HULL_W, HULL_W)

    nose = [(-2.88, SPONSON_Z), (-2.95, 0.85), (-2.85, 0.56), (-2.6, 0.42)]
    cx, cz, r = 2.42, 0.80, 0.38
    for k in range(9):
        a = math.radians(-90 + k * 110 / 8)
        nose.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    nose.append((GLACIS_BOTTOM[0] - 0.02, SPONSON_Z))
    L.add_prism(bm, nose, -LOWER_W, LOWER_W)
    hull = L.make_object("Hull", bm, coll, [M["paint"]], bevel=0.02)
    set_parent(hull, root)

    # Final drive housings that carry the sprockets.
    bm = bmesh.new()
    for s in (1, -1):
        L.add_lathe(bm, [(0, 0.76), (0.2, 0.76), (0.2, 0.9), (0.17, 0.95), (0.12, 0.97), (0, 0.97)], 32,
                    mat((SPROCKET[0], 0, SPROCKET[1]), (0, 0, 0 if s > 0 else 180)))
    obj = L.make_object("FinalDrives", bm, coll, [M["cast"]], bevel=0.01)
    set_parent(obj, root)

    # Bolt rows along the transmission cover flanges.
    bm = bmesh.new()
    for i in range(16):
        y = -0.72 + i * 0.096
        L.add_cyl(bm, 0.018, 0.02, mat((GLACIS_BOTTOM[0] + 0.005, y, SPONSON_Z - 0.02), (0, 90, 0)), segs=6)
    for s in (1, -1):
        for k in range(6):
            a = math.radians(-60 + k * 22)
            p = Vector((cx + (r + 0.01) * math.cos(a), cz + (r + 0.01) * math.sin(a)))
            L.add_cyl(bm, 0.017, 0.02, mat((p.x, s * (LOWER_W - 0.04), p.y), (0, 90 - math.degrees(a), 0)), segs=6)
    obj = L.make_object("HullBolts", bm, coll, [M["paint"]])
    set_parent(obj, root)


def build_hull_details(coll, M, root):
    bm = bmesh.new()       # painted steel bits
    bmg = bmesh.new()      # glass
    bml = bmesh.new()      # lamp lenses

    # Driver and assistant driver hatches with periscopes.
    for y in (0.48, -0.48):
        x = 1.62
        z = deck_z(x)
        L.add_cyl(bm, 0.30, 0.03, mat((x, y, z + 0.015)), segs=40)
        L.add_cyl(bm, 0.26, 0.035, mat((x, y, z + 0.045)), segs=40, r2=0.24)
        L.add_beam(bm, (x - 0.32, y + 0.12, z + 0.04), (x - 0.32, y - 0.12, z + 0.04), 0.06, 0.05)  # hinge
        L.add_cyl(bm, 0.06, 0.04, mat((x + 0.12, y - 0.1, z + 0.08)), segs=16)
        L.add_box(bm, (0.16, 0.10, 0.07), mat((x + 0.13, y - 0.1, z + 0.135)))
        L.add_box(bmg, (0.005, 0.08, 0.03), mat((x + 0.212, y - 0.1, z + 0.14)))
    # Ventilator dome between the hatches.
    L.add_sphere(bm, 0.11, mat((1.75, 0, deck_z(1.75)), scale=(1, 1, 0.6)), segs=20, rings=10)

    # Bow machine gun ball mount on the right of the glacis.
    t = 0.34
    m = glacis_matrix(t, -0.46)
    L.add_cyl(bm, 0.17, 0.05, m @ mat((0, 0, 0.02)), segs=32)
    L.add_sphere(bm, 0.12, m @ mat((0, 0, 0.03)), segs=24, rings=12)
    # Lifting eyes and headlight brackets near the lower corners.
    for y in (1.05, -1.05):
        mh = glacis_matrix(0.82, y, 0.0)
        L.add_box(bm, (0.08, 0.05, 0.06), mh @ mat((0, 0, 0.03)))
        L.add_cyl(bm, 0.075, 0.10, mh @ mat((0.0, 0, 0.12), (0, -GL_ANGLE + 90, 0)), segs=20)
        L.add_cyl(bml, 0.06, 0.012, mh @ mat((0.0, 0, 0.12)) @ mat(rot=(0, -GL_ANGLE + 90, 0)) @ mat((0, 0, 0.051)), segs=20)
        # Brush guard loop.
        for a in (-1, 1):
            L.add_rod(bm, (mh @ Vector((0.05, a * 0.11, 0.0))), (mh @ Vector((0.05, a * 0.11, 0.2))), 0.008)
        L.add_rod(bm, (mh @ Vector((0.05, -0.11, 0.2))), (mh @ Vector((0.05, 0.11, 0.2))), 0.008)
        L.add_rod(bm, (mh @ Vector((-0.1, 0.0, 0.0))), (mh @ Vector((0.05, 0.0, 0.2))), 0.008)

    # Front tow shackles.
    for y in (0.45, -0.45):
        L.add_box(bm, (0.08, 0.10, 0.10), mat((2.84, y, 0.66)))
        L.add_torus(bm, 0.06, 0.018, mat((2.92, y, 0.6), (0, 0, 90)), segs=16)

    # Fenders over the sprockets and idlers.
    for s in (1, -1):
        y = s * TRACK_Y
        L.add_beam(bm, (GLACIS_BOTTOM[0] - 0.05, y, SPONSON_Z + 0.01), (3.12, y, SPONSON_Z - 0.06), 0.46, 0.008)
        L.add_beam(bm, (-2.9, y, SPONSON_Z + 0.01), (-3.14, y, SPONSON_Z - 0.04), 0.46, 0.008)
        # Appliqué armour over the ammunition racks.
        xs = (0.55, -0.35) if s < 0 else (0.15,)
        for x in xs:
            L.add_box(bm, (0.62, 0.03, 0.42), mat((x, s * (HULL_W + 0.015), 1.48)))
        # Lifting rings at the deck corners.
        for x in (1.6, -2.6):
            L.add_torus(bm, 0.045, 0.012, mat((x, s * (HULL_W - 0.08), deck_z(x) + 0.03), (90, 0, 0)), segs=12)

    # Engine deck: grille, access doors, fuel fillers.
    for i in range(14):
        x = -2.62 + i * 0.035
        L.add_box(bm, (0.012, 1.7, 0.03), mat((x, 0, deck_z(x) + 0.01), (0, 15, 0)))
    L.add_box(bm, (0.52, 1.78, 0.02), mat((-2.39, 0, deck_z(-2.39) - 0.005)))
    for y in (0.45, -0.45):
        L.add_box(bm, (0.95, 0.86, 0.012), mat((-1.5, y, deck_z(-1.5) + 0.006)))
        L.add_rod(bm, (-1.2, y - 0.1, deck_z(-1.2) + 0.03), (-1.2, y + 0.1, deck_z(-1.2) + 0.03), 0.01)
    for x in (-0.95, -2.0):
        for s in (1, -1):
            L.add_cyl(bm, 0.075, 0.03, mat((x, s * 1.0, deck_z(x) + 0.015)), segs=20)

    # Rear plate: exhaust deflector, tail lights, tow pintle.
    L.add_beam(bm, (-2.95, 0, 1.18), (-3.18, 0, 0.98), 1.9, 0.01, up=(0, 0, 1))
    for s in (1, -1):
        L.add_box(bm, (0.04, 0.12, 0.1), mat((-2.98, s * 1.05, 1.45)))
        # Sand shield mounting rail along the bottom of the sponson.
        L.add_box(bm, (5.55, 0.02, 0.05), mat((-0.06, s * (HULL_W + 0.01), SPONSON_Z + 0.025)))
        L.add_box(bml, (0.005, 0.05, 0.04), mat((-3.0, s * 1.05, 1.46)))
    L.add_box(bm, (0.1, 0.16, 0.16), mat((-2.98, 0, 0.75)))
    L.add_torus(bm, 0.05, 0.02, mat((-3.06, 0, 0.74), (90, 0, 0)), segs=16)

    for name, b, mats in (("HullDetails", bm, [M["paint"]]), ("HullGlass", bmg, [M["glass"]]), ("HullLamps", bml, [M["brass"]])):
        obj = L.make_object(name, b, coll, mats, bevel=0.004 if name == "HullDetails" else None, bevel_segments=1)
        set_parent(obj, root)

    # Bow MG barrel with perforated jacket.
    bm = bmesh.new()
    p0 = glacis_matrix(t, -0.46) @ Vector((0, 0, 0.05))
    d = Vector((1, 0, -0.06)).normalized()
    L.add_rod(bm, p0, p0 + d * 0.42, 0.024, segs=16)
    L.add_rod(bm, p0 + d * 0.4, p0 + d * 0.55, 0.011, segs=10)
    obj = L.make_object("BowMG", bm, coll, [M["gunmetal"]])
    set_parent(obj, root)


def star_points(r_outer, rot=90.0):
    pts = []
    for k in range(10):
        r = r_outer if k % 2 == 0 else r_outer * 0.382
        a = math.radians(rot + k * 36)
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def build_markings(coll, M, root):
    bm = bmesh.new()
    for s in (1, -1):
        pts = [(-0.95 + x, 1.47 + z) for x, z in star_points(0.3)]
        y = s * (HULL_W + 0.001)
        L.add_prism(bm, pts, y, y + s * 0.002)
    # Air recognition star in a ring on the engine deck.
    x0 = -1.55
    z = deck_z(x0) + 0.016
    m = mat((x0, 0, z), (90, 0, 0))
    L.add_prism(bm, star_points(0.36, rot=0.0), 0.0, 0.002, m)
    ring = []
    for k in range(64):
        a = 2 * math.pi * k / 64
        ring.append((math.cos(a), math.sin(a)))
    verts_o = [bm.verts.new(m @ Vector((0.46 * c, 0.002, 0.46 * s))) for c, s in ring]
    verts_i = [bm.verts.new(m @ Vector((0.42 * c, 0.002, 0.42 * s))) for c, s in ring]
    for k in range(64):
        j = (k + 1) % 64
        bm.faces.new((verts_o[k], verts_o[j], verts_i[j], verts_i[k]))
    obj = L.make_object("Markings", bm, coll, [M["star"]], weighted=False)
    set_parent(obj, root)


# ---------------------------------------------------------------------------
# Running gear

WHEEL_PROFILE = [
    (0, -0.075), (0.055, -0.075), (0.065, -0.06), (0.075, -0.05), (0.16, -0.065), (0.19, -0.085),
    (0.198, -0.115), (0.215, -0.122), (0.245, -0.122), (0.254, -0.11), (0.254, -0.045), (0.245, -0.036),
    (0.175, -0.034), (0.175, 0.034), (0.245, 0.036), (0.254, 0.045), (0.254, 0.11), (0.245, 0.122),
    (0.215, 0.122), (0.198, 0.115), (0.19, 0.085), (0.16, 0.065), (0.075, 0.05), (0.065, 0.06),
    (0.055, 0.075), (0, 0.075),
]


def build_wheel_mesh(coll, M):
    bm = bmesh.new()
    mats = [0] * (len(WHEEL_PROFILE) - 1)
    for i in list(range(6, 12)) + list(range(13, 19)):
        mats[i] = 1
    L.add_lathe(bm, WHEEL_PROFILE, 48, mats=mats)
    for a in (-0.078, 0.078):
        for k in range(6):
            ang = 2 * math.pi * k / 6
            L.add_cyl(bm, 0.011, 0.012, mat((0.04 * math.cos(ang), a, 0.04 * math.sin(ang)), (90, 0, 0)), segs=6)
    return L.make_object("RoadWheel", bm, coll, [M["paint"], M["rubber"]], bevel=0.004, bevel_segments=2)


def build_roller_mesh(coll, M, name):
    prof = [(0, -0.08), (0.04, -0.08), (0.05, -0.07), (0.1, -0.075), (0.11, -0.065), (0.11, -0.03),
            (0.08, -0.025), (0.08, 0.025), (0.11, 0.03), (0.11, 0.065), (0.1, 0.075), (0.05, 0.07),
            (0.04, 0.08), (0, 0.08)]
    bm = bmesh.new()
    L.add_lathe(bm, prof, 32)
    return L.make_object(name, bm, coll, [M["paint"]], bevel=0.004, bevel_segments=2)


def build_sprocket_mesh(coll, M):
    bm = bmesh.new()
    hub = [(0, -0.13), (0.1, -0.13), (0.12, -0.11), (0.14, -0.1), (0.25, -0.1), (0.27, -0.09), (0.27, 0.09),
           (0.25, 0.1), (0.14, 0.1), (0.12, 0.11), (0.1, 0.15), (0, 0.16)]
    L.add_lathe(bm, hub, 48)
    teeth = 13
    outline = []
    for i in range(teeth):
        a0 = 2 * math.pi * i / teeth
        half = math.pi / teeth
        for frac, r in ((-0.95, 0.285), (-0.5, 0.29), (-0.3, 0.335), (-0.12, 0.36), (0.12, 0.36), (0.3, 0.335), (0.5, 0.29)):
            outline.append((a0 + frac * half, r))
    for y in (-0.09, 0.09):
        _ring_prism(bm, outline, 0.24, y - 0.02, y + 0.02)
    for k in range(12):
        ang = 2 * math.pi * k / 12
        L.add_cyl(bm, 0.014, 0.02, mat((0.2 * math.cos(ang), 0.105, 0.2 * math.sin(ang)), (90, 0, 0)), segs=6)
    return L.make_object("Sprocket", bm, coll, [M["cast"]], bevel=0.004, bevel_segments=2)


def _ring_prism(bm, outline, inner_r, y0, y1):
    """Annulus with an arbitrary outer outline given as (angle, radius) pairs."""
    n = len(outline)
    ring = []
    for a, r in outline:
        c, s = math.cos(a), math.sin(a)
        ring.append([
            bm.verts.new((r * c, y0, r * s)), bm.verts.new((r * c, y1, r * s)),
            bm.verts.new((inner_r * c, y1, inner_r * s)), bm.verts.new((inner_r * c, y0, inner_r * s)),
        ])
    faces = []
    for k in range(n):
        a, b = ring[k], ring[(k + 1) % n]
        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def build_idler_mesh(coll, M):
    prof = [(0, -0.1), (0.07, -0.1), (0.09, -0.08), (0.2, -0.07), (0.24, -0.12), (0.26, -0.12), (0.26, -0.035),
            (0.2, -0.03), (0.2, 0.03), (0.26, 0.035), (0.26, 0.12), (0.24, 0.12), (0.2, 0.07), (0.09, 0.08),
            (0.07, 0.1), (0, 0.1)]
    bm = bmesh.new()
    L.add_lathe(bm, prof, 48)
    return L.make_object("Idler", bm, coll, [M["paint"]], bevel=0.004, bevel_segments=2)


def track_top_z(x):
    """Track centre line height of the straight upper run."""
    x0, z0 = IDLER[0], IDLER[1] + IDLER[2] + T / 2
    x1, z1 = SPROCKET[0], SPROCKET[1] + SPROCKET[2]
    return z0 + (x - x0) / (x1 - x0) * (z1 - z0)


def build_bogie(coll, M, bx, s, roller_src, root):
    """VVSS bogie in local space (y=0 at the track centre), placed and mirrored per side."""
    rz = track_top_z(bx) - T / 2 - 0.11
    bm = bmesh.new()
    L.add_box(bm, (0.50, 0.18, 0.30), mat((0, -0.21, 0.70)))
    L.add_box(bm, (0.62, 0.03, 0.36), mat((0, -0.31, 0.70)))
    L.add_box(bm, (0.12, 0.10, rz - 0.82), mat((0, -0.21, (rz + 0.82) / 2)))
    L.add_rod(bm, (0, -0.24, rz), (0, -0.06, rz), 0.03)
    for a in (-1, 1):
        L.add_beam(bm, (a * 0.10, -0.17, 0.62), (a * WHEEL_DX, -0.17, WHEEL_Z), 0.06, 0.1)
        L.add_rod(bm, (a * WHEEL_DX, -0.22, WHEEL_Z), (a * WHEEL_DX, -0.10, WHEEL_Z), 0.045)
    spring = [(0, 0)]
    for i in range(9):
        spring.append((0.085 if i % 2 == 0 else 0.07, 0.02 + i * 0.024))
    spring.append((0, 0.22))
    L.add_lathe(bm, spring, 24, mat((0, -0.19, 0.38), (90, 0, 0)))
    rot = 0 if s > 0 else 180
    loc = (bx, s * TRACK_Y, 0)
    obj = L.make_object("Bogie_%s_%d" % ("L" if s > 0 else "R", BOGIES.index(bx)), bm, coll, [M["cast"]],
                        bevel=0.012, loc=loc, rot=(0, 0, rot))
    set_parent(obj, root)
    roller = L.link_copy(roller_src, obj.name + "_Roller", coll, (bx, s * TRACK_Y, rz), (0, 0, rot))
    set_parent(roller, root)
    return obj


def add_track_link(bm, m, mat_index=0):
    """One T54E1-style steel chevron link. Local X along the track, Z outward."""
    L.add_box(bm, (0.13, 0.40, 0.03), m @ mat((0, 0, -0.015)), mat_index)
    for side in (-1, 1):
        L.add_box(bm, (0.035, 0.21, 0.025), m @ mat((0.0, side * 0.1, 0.0125), (0, 0, side * 25)), mat_index)
        for u in (-0.07, 0.07):
            L.add_box(bm, (0.045, 0.035, 0.045), m @ mat((u, side * 0.205, -0.015)), mat_index)
    for u in (-0.07, 0.07):
        L.add_box(bm, (0.045, 0.08, 0.035), m @ mat((u, 0, -0.015)), mat_index)
    L.add_box(bm, (0.06, 0.035, 0.07), m @ mat((0, 0, -0.065)), mat_index)


def track_loop():
    """Closed track centre line in the XZ plane, counter-clockwise seen from +Y."""
    circles = [SPROCKET, IDLER] + [(bx + a * WHEEL_DX, WHEEL_Z, WHEEL_R) for bx in BOGIES for a in (-1, 1)]
    pts = []
    for cx, cz, r in circles:
        rr = r + T / 2 if (cx, cz, r) != SPROCKET else r
        for k in range(240):
            a = 2 * math.pi * k / 240
            pts.append((round(cx + rr * math.cos(a), 6), round(cz + rr * math.sin(a), 6)))
    return L.convex_hull_2d(pts)


def build_track(coll, M, s, root, link_obj):
    """Track as rigid links instanced along a path curve by Geometry Nodes (see tank_rig)."""
    import tank_rig
    side = "L" if s > 0 else "R"
    loop = track_loop()
    length = sum((Vector(loop[i]) - Vector(loop[i - 1])).length for i in range(len(loop)))
    count = round(length / PITCH)
    y = s * TRACK_Y

    cu = bpy.data.curves.new("TrackPath_" + side, 'CURVE')
    cu.dimensions = '3D'
    spline = cu.splines.new('POLY')
    spline.points.add(len(loop) - 1)
    for p, (x, z) in zip(spline.points, loop):
        p.co = (x, y, z, 1.0)
    spline.use_cyclic_u = True
    path = bpy.data.objects.new("TrackPath_" + side, cu)
    coll.objects.link(path)
    path.hide_render = True
    set_parent(path, root)

    me = bpy.data.meshes.new("Track_" + side)
    me.materials.append(M["track"])
    track = bpy.data.objects.new("Track_" + side, me)
    coll.objects.link(track)
    set_parent(track, root)
    tank_rig.add_track_modifier(track, path, link_obj, count)
    return count, length


def build_running_gear(coll, M, root):
    gear = L.collection("RunningGear", coll)
    wheel = build_wheel_mesh(gear, M)
    roller = build_roller_mesh(gear, M, "ReturnRoller")
    sprocket = build_sprocket_mesh(gear, M)
    idler = build_idler_mesh(gear, M)
    bm = bmesh.new()
    add_track_link(bm, Matrix())
    link = L.make_object("TrackLink", bm, gear, [M["track"]], bevel=0.004, bevel_segments=1)
    link.hide_render = True
    link.location = (0, 0, -20)
    info = {}
    for s in (1, -1):
        rot = (0, 0, 0 if s > 0 else 180)
        side = "L" if s > 0 else "R"
        for i, bx in enumerate(BOGIES):
            build_bogie(gear, M, bx, s, roller, root)
            for a in (-1, 1):
                w = L.link_copy(wheel, "RoadWheel_%s_%d%s" % (side, i, "f" if a > 0 else "r"), gear,
                                (bx + a * WHEEL_DX, s * TRACK_Y, WHEEL_Z), rot)
                set_parent(w, root)
        sp = L.link_copy(sprocket, "Sprocket_" + side, gear, (SPROCKET[0], s * TRACK_Y, SPROCKET[1]), rot)
        set_parent(sp, root)
        idl = L.link_copy(idler, "Idler_" + side, gear, (IDLER[0], s * TRACK_Y, IDLER[1]), rot)
        set_parent(idl, root)
        bm = bmesh.new()
        L.add_beam(bm, (-2.42, s * 0.84, 0.66), (IDLER[0], s * 0.84, IDLER[1]), 0.08, 0.12)
        L.add_rod(bm, (IDLER[0], s * 0.78, IDLER[1]), (IDLER[0], s * 1.0, IDLER[1]), 0.05)
        arm = L.make_object("IdlerArm_" + side, bm, gear, [M["cast"]], bevel=0.01)
        set_parent(arm, root)
        info[side] = build_track(gear, M, s, root, link)
    # The source meshes stay hidden at the origin; only their copies are shown.
    for src in (wheel, roller, sprocket, idler):
        src.hide_viewport = True
        src.hide_render = True
    return info


# ---------------------------------------------------------------------------
# Turret

def build_turret(coll, M, root):
    tur = L.collection("Turret", coll)
    pivot = empty("Turret", tur, (TX, 0, TZ), root)
    base = TZ + 0.03
    rings_def = [
        (0.00, 0.96, 1.20, 0.97, 2.3), (0.08, 1.02, 1.26, 1.02, 2.3), (0.30, 1.00, 1.24, 1.00, 2.2),
        (0.50, 0.90, 1.14, 0.92, 2.2), (0.62, 0.80, 1.04, 0.82, 2.3), (0.68, 0.66, 0.92, 0.70, 2.5),
        (0.70, 0.50, 0.78, 0.55, 2.6),
    ]
    rings = [L.superellipse(af, ar, b, n, base + z, 72, TX) for z, af, ar, b, n in rings_def]
    bm = bmesh.new()
    L.add_loft(bm, rings)
    L.add_cyl(bm, 0.93, 0.05, mat((TX, 0, TZ + 0.02)), segs=72)
    body = L.make_object("TurretBody", bm, tur, [M["cast"]], bevel=0.02, smooth_angle=50)
    set_parent(body, pivot)

    gun_z = base + 0.36
    trunnion = empty("Gun", tur, (TX + 0.9, 0, gun_z), pivot)

    # M34A1 mantlet.
    bm = bmesh.new()
    prof = [(TX + 0.78, base + 0.09)]
    for k in range(13):
        a = math.radians(-90 + k * 15)
        prof.append((TX + 0.93 + 0.2 * math.cos(a), gun_z + 0.27 * math.sin(a)))
    prof.append((TX + 0.78, base + 0.63))
    L.add_prism(bm, prof, -0.47, 0.47)
    L.add_cyl(bm, 0.1, 0.12, mat((TX + 1.16, 0, gun_z), (0, 90, 0)), segs=32)
    mantlet = L.make_object("Mantlet", bm, tur, [M["cast"]], bevel=0.05, bevel_segments=5, smooth_angle=35)
    set_parent(mantlet, trunnion)

    # 75 mm M3 gun.
    barrel = [(0, -0.05), (0.075, -0.05), (0.075, 0.12), (0.066, 0.15), (0.06, 0.3), (0.054, 2.42), (0.05, 2.5),
              (0.058, 2.51), (0.058, 2.62), (0.0375, 2.62), (0.0375, 2.35), (0, 2.35)]
    bm = bmesh.new()
    L.add_lathe(bm, barrel, 40, mat((TX + 1.2, 0, gun_z), (0, 0, -90)))
    gun = L.make_object("GunBarrel", bm, tur, [M["paint"]], bevel=0.004, bevel_segments=2, smooth_angle=30)
    set_parent(gun, trunnion)
    bm = bmesh.new()
    L.add_rod(bm, (TX + 1.05, 0.2, gun_z - 0.03), (TX + 1.22, 0.2, gun_z - 0.03), 0.014)
    L.add_cyl(bm, 0.03, 0.02, mat((TX + 1.125, -0.22, gun_z + 0.06), (0, 90, 0)), segs=16)
    coax = L.make_object("Coax", bm, tur, [M["gunmetal"]])
    set_parent(coax, trunnion)

    # Roof: commander's vision cupola, loader's hatch, periscopes, vent, lifting eyes.
    bm = bmesh.new()
    bmg = bmesh.new()
    cx, cy = TX - 0.32, -0.36
    L.add_cyl(bm, 0.36, 0.06, mat((cx, cy, ROOF_Z + 0.03)), segs=48)
    L.add_cyl(bm, 0.31, 0.16, mat((cx, cy, ROOF_Z + 0.13)), segs=48, r2=0.29)
    for k in range(6):
        a = 2 * math.pi * k / 6
        L.add_box(bm, (0.08, 0.16, 0.1), mat((cx + 0.3 * math.cos(a), cy + 0.3 * math.sin(a), ROOF_Z + 0.14), (0, 0, math.degrees(a))))
        L.add_box(bmg, (0.005, 0.12, 0.05), mat((cx + 0.342 * math.cos(a), cy + 0.342 * math.sin(a), ROOF_Z + 0.145), (0, 0, math.degrees(a))))
    L.add_sphere(bm, 0.28, mat((cx, cy, ROOF_Z + 0.21), scale=(1, 1, 0.25)), segs=32, rings=12)
    L.add_beam(bm, (cx - 0.05, cy - 0.3, ROOF_Z + 0.24), (cx - 0.05, cy + 0.3, ROOF_Z + 0.24), 0.04, 0.03)
    L.add_cyl(bm, 0.26, 0.03, mat((TX + 0.02, 0.40, ROOF_Z + 0.015), scale=(1.15, 0.8, 1)), segs=40)
    L.add_beam(bm, (TX - 0.27, 0.3, ROOF_Z + 0.035), (TX - 0.27, 0.5, ROOF_Z + 0.035), 0.05, 0.04)
    for px, py in ((TX + 0.40, -0.28), (TX + 0.30, 0.47)):
        L.add_cyl(bm, 0.08, 0.04, mat((px, py, ROOF_Z + 0.02)), segs=20)
        L.add_box(bm, (0.16, 0.11, 0.08), mat((px + 0.01, py, ROOF_Z + 0.08)))
        L.add_box(bmg, (0.005, 0.09, 0.035), mat((px + 0.092, py, ROOF_Z + 0.085)))
    L.add_sphere(bm, 0.1, mat((TX + 0.25, 0.05, ROOF_Z), scale=(1, 1, 0.55)), segs=20, rings=10)
    for px, py in ((TX + 0.5, 0.25), (TX - 0.75, 0.5), (TX - 0.75, -0.55)):
        L.add_torus(bm, 0.04, 0.012, mat((px, py, ROOF_Z + 0.03), (90, 0, 0)), segs=12)
    # Pistol port on the left wall and antenna mount on the bustle.
    L.add_cyl(bm, 0.09, 0.04, mat((TX - 0.15, 0.995, base + 0.32), (90, 0, 0)), segs=24)
    L.add_cyl(bm, 0.05, 0.12, mat((TX - 1.0, 0.42, ROOF_Z - 0.02)), segs=16)
    roof = L.make_object("TurretRoof", bm, tur, [M["cast"]], bevel=0.006, bevel_segments=2)
    set_parent(roof, pivot)
    glass = L.make_object("TurretGlass", bmg, tur, [M["glass"]])
    set_parent(glass, pivot)

    bm = bmesh.new()
    L.add_rod(bm, (TX - 1.0, 0.42, ROOF_Z + 0.04), (TX - 1.08, 0.45, ROOF_Z + 2.4), 0.005, segs=6)
    ant = L.make_object("Antenna", bm, tur, [M["gunmetal"]], weighted=False)
    set_parent(ant, pivot)

    build_m2(tur, M, pivot)
    return pivot


def build_m2(coll, M, pivot):
    """.50 cal M2 on a roof pintle, pointing forward-left."""
    bm = bmesh.new()
    px, py = TX - 0.6, 0.15
    L.add_cyl(bm, 0.03, 0.38, mat((px, py, ROOF_Z + 0.19)), segs=16)
    L.add_cyl(bm, 0.06, 0.03, mat((px, py, ROOF_Z + 0.015)), segs=16)
    gm = mat((px, py, ROOF_Z + 0.42), (0, -6, 25))
    L.add_box(bm, (0.6, 0.1, 0.14), gm @ mat((-0.05, 0, 0)))
    L.add_box(bm, (0.14, 0.12, 0.05), gm @ mat((0.12, 0, 0.09)))
    for sgn in (-1, 1):
        L.add_rod(bm, gm @ Vector((-0.35, sgn * 0.05, 0)), gm @ Vector((-0.45, sgn * 0.05, 0.02)), 0.013)
    L.add_rod(bm, gm @ Vector((0.25, 0, 0)), gm @ Vector((0.6, 0, 0)), 0.03, segs=16)
    L.add_rod(bm, gm @ Vector((0.6, 0, 0)), gm @ Vector((1.38, 0, 0)), 0.014, segs=12)
    L.add_cyl(bm, 0.022, 0.03, gm @ mat((1.38, 0, 0), (0, 90, 0)), segs=12)
    L.add_box(bm, (0.26, 0.1, 0.16), gm @ mat((0.02, 0.1, -0.02)))
    L.add_box(bm, (0.06, 0.06, 0.04), gm @ mat((0.02, 0.07, 0.07)))
    obj = L.make_object("M2_50cal", bm, coll, [M["gunmetal"]], bevel=0.004, bevel_segments=1)
    set_parent(obj, pivot)


# ---------------------------------------------------------------------------
# Stowage

def build_stowage(coll, M, root):
    st = L.collection("Stowage", coll)
    # Spare track links on the glacis with a retaining bar.
    bm = bmesh.new()
    for i in range(8):
        y = -0.54 + i * PITCH
        # Grousers against the plate, guide horns facing out, as commonly stowed.
        add_track_link(bm, glacis_matrix(0.62, y, 0.026, (180, 0, 90)))
    obj = L.make_object("SpareTrack", bm, st, [M["track"]], bevel=0.004, bevel_segments=1)
    set_parent(obj, root)
    bm = bmesh.new()
    for t in (0.49, 0.75):
        L.add_beam(bm, glacis_matrix(t, -0.66, 0.068) @ Vector((0, 0, 0)), glacis_matrix(t, 0.66, 0.068) @ Vector((0, 0, 0)), 0.03, 0.02)
        for y in (-0.66, 0.66):
            L.add_beam(bm, glacis_matrix(t, y, 0.0) @ Vector((0, 0, 0)), glacis_matrix(t, y, 0.08) @ Vector((0, 0, 0)), 0.03, 0.03)
    obj = L.make_object("SpareTrackBars", bm, st, [M["paint"]], bevel=0.003, bevel_segments=1)
    set_parent(obj, root)

    # Jerry cans on the rear deck.
    bm = bmesh.new()
    bmc = bmesh.new()
    for i, y in enumerate((-0.62, -0.95)):
        x = -2.45
        z = deck_z(x) + 0.09
        L.add_box(bm, (0.47, 0.33, 0.165), mat((x, y, z), (0, 0, 4 * i)))
        for sgn in (-1, 1):
            L.add_box(bm, (0.42, 0.025, 0.01), mat((x, y, z + 0.085), (0, 0, 4 * i + sgn * 33)))
        L.add_box(bm, (0.06, 0.12, 0.03), mat((x - 0.26, y, z + 0.05), (0, 0, 4 * i)))
    L.make_object("JerryCans", bm, st, [M["paint"]], bevel=0.02, bevel_segments=3).parent = root
    # Rolled tarp strapped behind the turret.
    x = -1.0
    L.add_lathe(bmc, [(0, -0.72), (0.12, -0.72), (0.14, -0.69), (0.14, 0.69), (0.12, 0.72), (0, 0.72)], 24,
                mat((x, 0.05, deck_z(x) + 0.14)))
    tarp = L.make_object("Tarp", bmc, st, [M["canvas"]], bevel=0.01, smooth_angle=60)
    tarp.parent = root
    bm = bmesh.new()
    for y in (-0.45, 0.5):
        L.add_torus(bm, 0.145, 0.008, mat((x, y + 0.05, deck_z(x) + 0.14)), segs=24, minor=6)
    L.make_object("TarpStraps", bm, st, [M["gunmetal"]], weighted=False).parent = root

    # Pioneer tools along the left sponson: shovel, pick and crowbar.
    bmw = bmesh.new()
    bmm = bmesh.new()
    yl = HULL_W + 0.03
    zs, zp, zc = 1.66, 1.42, 1.25
    L.add_rod(bmw, (-2.78, yl, zs), (-2.0, yl, zs), 0.018)
    L.add_torus(bmw, 0.04, 0.01, mat((-2.82, yl, zs), (90, 0, 0)), segs=12, minor=6)
    L.add_beam(bmm, (-2.02, yl, zs), (-1.94, yl, zs), 0.025, 0.04)
    L.add_box(bmm, (0.26, 0.012, 0.2), mat((-1.8, yl, zs)))
    L.add_rod(bmw, (-2.8, yl, zp), (-1.5, yl, zp), 0.02)
    L.add_beam(bmm, (-1.45, yl, zp - 0.22), (-1.45, yl, zp + 0.22), 0.035, 0.05)
    L.add_rod(bmm, (-2.8, yl, zc), (-1.65, yl, zc), 0.014)
    for x, z in ((-2.55, zs), (-2.15, zs), (-2.55, zp), (-1.75, zp), (-2.35, zc), (-1.85, zc)):
        L.add_box(bmm, (0.035, 0.05, 0.07), mat((x, yl - 0.008, z)))
    L.make_object("ToolHandles", bmw, st, [M["wood"]], weighted=False).parent = root
    L.make_object("ToolMetal", bmm, st, [M["gunmetal"]], bevel=0.003, bevel_segments=1).parent = root


def build(materials):
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    root = empty("M4A3_Sherman_Root", coll)
    build_hull(coll, materials, root)
    build_hull_details(coll, materials, root)
    build_markings(coll, materials, root)
    gear = build_running_gear(coll, materials, root)
    build_turret(coll, materials, root)
    build_stowage(coll, materials, root)
    return {"objects": len(coll.all_objects), "track_links": gear}
