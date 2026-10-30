"""Debarker outfeed log trough, flip kicker and cushioned end stop (run inside Blender).

Takes debarked logs from the ring debarker's V-roll outfeed and kicks them sideways onto
the incline to the headrig, in the style of a Morbark/Nicholson outfeed trough:
  - 90 deg steel log trough, 6.3 m long, with a dogged drag chain running in a channel
    down the bottom of the V; head drive at the end stop, idler at the debarker end
  - flip kicker: four heavy paddles lie in slots under the far flank, keyed to a shaft
    along the channel edge. A hydraulic cylinder on a crank rolls them up through the V,
    they push the log up the near flank and over the rim, and it rolls down skid ribs
    (set between the incline's lug tracks) onto the incline foot
  - cushioned end stop: bumper plate with a rubber face on two shock absorbers, in a
    heavy portal frame

Built in mill coordinates (the game places every file at y = -1.288 under a node at the
origin): Godot (x, y, z) = Blender (x, -z, y + 1.288), see G(). The log line runs along X
at z 2.118 with the log centre 0.872 up, like the debarker.

  LK_Frame     trough, chain channel, stands, skid ribs, sprocket shafts, drive, end stop
               frame, absorber barrels, HPU; LK_HeadShaft / LK_TailShaft spin about Z
  LK_Kicker    shaft, paddles and crank; pivots about X at the kicker shaft (KICK_PIVOT)
  LK_Bumper    bumper plate, rubber face and absorber rods; slides along X
  LK_CylBarrel / LK_CylRod   kicker cylinder halves (+Y towards the partner, +Z along the pin)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
import materials_lib as ML  # noqa: E402
import mesh_lib as L  # noqa: E402

COLL = "LogKicker"

FLOOR = -1.288
LOG_R = 0.292
LINE_Z = 2.118
LINE_Y = 0.872
# 90 deg V: apex where the flanks would meet, rim height, chain channel half width.
APEX_Y = LINE_Y - LOG_R / math.cos(math.radians(45.0))
RIM_Y = 0.86
CHANNEL_HALF = 0.06
CHANNEL_BOTTOM = 0.355
TROUGH_X = (13.25, 19.55)
# Drag chain in the channel: top-run link centre, sprocket radius, shaft x positions.
CHAIN_Y = 0.39
SPROCKET_R = 0.15
HEAD_X = 19.30
TAIL_X = 13.40
# Flip kicker: paddles keyed to a shaft along the far channel edge.
KICK_PIVOT = (1.98, 0.52)          # Godot (z, y)
PADDLE_X = (15.0, 16.2, 17.4, 18.6)
PADDLE_T = 0.06
KICK_ANGLE = 95.0
CRANK_X = 13.65
CRANK_PIN = (-0.30, -0.40)         # from the pivot, (z, y), at rest
CYL_ANCHOR = (0.90, -1.10)         # Godot (z, y), on a floor bracket
# Skid ribs down to the incline foot, between the incline's lug tracks.
RIB_X = (14.42, 15.62, 16.82, 18.02, 19.22)
SKID_TOP = (2.52, RIM_Y)
SKID_FOOT = (3.10, 0.08)
STAND_X = (13.9, 15.6, 16.8, 18.0, 19.2)
# Cushioned end stop: rubber face where the log end stops.
STOP_FACE_X = 19.40


def G(x, y, z):
    return Vector((x, -z, y - FLOOR))


def flank_y(z):
    return APEX_Y + abs(z - LINE_Z)


def empty(name, coll, parent=None, loc=(0, 0, 0), size=0.15):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = size
    coll.objects.link(obj)
    obj.parent = parent
    obj.location = loc
    return obj


def box(bm, centre, size, mat_index=0):
    L.add_box(bm, size, Matrix.Translation(centre), mat_index)


def gbox(bm, x0, x1, y0, y1, z0, z1, mat_index=0, origin=Vector()):
    a, b = G(x0, y0, z0) - origin, G(x1, y1, z1) - origin
    lo = Vector((min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)))
    hi = Vector((max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
    box(bm, (lo + hi) / 2, hi - lo, mat_index)


def plate(bm, x, thick, zy, mat_index=0, origin=Vector()):
    """Vertical plate at Godot x, outline as Godot (z, y) points."""
    m = Matrix(((0, 1, 0, x - origin.x), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
    pts = [(-z - origin.y, y - FLOOR - origin.z) for z, y in zy]
    L.add_prism(bm, pts, -thick / 2, thick / 2, m, mat_index)


def beam(bm, p0, p1, w, h, mat_index=0, origin=Vector()):
    L.add_beam(bm, G(*p0) - origin, G(*p1) - origin, w, h, mat_index=mat_index)


def cyl_x(bm, centre, r, length, segs=20, mat_index=0):
    L.add_cyl(bm, r, length, Matrix.Translation(centre) @ L.mat(rot=(0, 90, 0)), segs=segs, mat_index=mat_index)


def cyl_y(bm, centre, r, length, segs=20, mat_index=0):
    """Along Blender Y = Godot Z."""
    L.add_cyl(bm, r, length, Matrix.Translation(centre) @ L.mat(rot=(90, 0, 0)), segs=segs, mat_index=mat_index)


def build_materials():
    frame = ((0.05, 0.11, 0.16), (0.09, 0.18, 0.25), (0.15, 0.26, 0.33))
    yellow = ((0.42, 0.26, 0.012), (0.62, 0.40, 0.02), (0.78, 0.55, 0.08))
    return {
        "frame": ML.painted_steel("LK_Frame", *frame, chip_amount=0.55, dirt_height=1.2),
        "moving": ML.painted_steel("LK_Moving", *yellow, chip_amount=0.7, dirt_height=1.0),
        "wear": ML.simple("LK_Wear", (0.24, 0.235, 0.225), 0.38, 0.9, 50, 0.05),
        "dark": ML.painted_steel("LK_Dark", (0.02, 0.02, 0.02), (0.04, 0.04, 0.04), (0.07, 0.07, 0.065),
                                 chip_amount=0.8, dirt_height=1.5),
        "chrome": ML.simple("LK_Chrome", (0.75, 0.75, 0.74), 0.08, 1.0),
        "rubber": ML.rubber("LK_Rubber"),
        "motor": ML.painted_steel("LK_Motor", (0.03, 0.06, 0.12), (0.05, 0.10, 0.20), (0.09, 0.15, 0.27),
                                  chip_amount=0.4, dirt_height=0.5),
        "red": ML.simple("LK_Red", (0.5, 0.03, 0.02), 0.5, 0.0),
    }


VIEWPORT = {
    "LK_Frame": ((0.09, 0.18, 0.25), 0.3, 0.55),
    "LK_Moving": ((0.62, 0.40, 0.02), 0.2, 0.55),
    "LK_Wear": ((0.30, 0.295, 0.285), 0.45, 0.42),
    "LK_Dark": ((0.04, 0.04, 0.04), 0.5, 0.5),
    "LK_Chrome": ((0.78, 0.78, 0.77), 1.0, 0.08),
    "LK_Rubber": ((0.02, 0.02, 0.02), 0.0, 0.85),
    "LK_Motor": ((0.05, 0.10, 0.20), 0.4, 0.5),
    "LK_Red": ((0.5, 0.03, 0.02), 0.0, 0.5),
}


# --- Trough ----------------------------------------------------------------------------

def _gaps(x0, x1, cuts, half):
    """Spans of [x0, x1] with slots of +-half around each cut."""
    spans, start = [], x0
    for c in sorted(cuts):
        spans.append((start, c - half))
        start = c + half
    spans.append((start, x1))
    return [s for s in spans if s[1] - s[0] > 0.01]


def flank(bm, side, x0, x1, mat_index):
    """One 45 deg flank plate (side -1 far, +1 near) from the channel lip to the rim."""
    z_in = LINE_Z + side * CHANNEL_HALF
    z_out = LINE_Z + side * (RIM_Y - APEX_Y)
    inner, outer = G(x0, flank_y(z_in), z_in), G(x0, RIM_Y, z_out)
    length = (outer - inner).length
    d = (outer - inner).normalized()
    # Plate normal out of the V surface (upwards); the plate sits under the surface.
    up = Vector((1, 0, 0)).cross(d)
    if up.z < 0:
        up = -up
    thick = 0.016
    centre = (inner + outer) / 2 + Vector(((x1 - x0) / 2, 0, 0)) - up * thick / 2
    rot = Matrix((Vector((1, 0, 0)), d, up)).transposed()
    if rot.determinant() < 0:
        rot = Matrix((Vector((1, 0, 0)), -d, up)).transposed()
    L.add_box(bm, (x1 - x0, length, thick), Matrix.Translation(centre) @ rot.to_4x4(), mat_index)


def build_trough(bm, F, W, D):
    x0, x1 = TROUGH_X
    for side in (-1, 1):
        # Flanks, slotted where the paddles come through.
        for a, b in _gaps(x0, x1, PADDLE_X, PADDLE_T / 2 + 0.025):
            flank(bm, side, a, b, W)
        # Rim angle along the top edge and a stiffener under the flank.
        z_out = LINE_Z + side * (RIM_Y - APEX_Y)
        gbox(bm, x0, x1, RIM_Y - 0.10, RIM_Y + 0.012, z_out + side * 0.0 - 0.006, z_out + side * 0.0 + 0.006, F)
        gbox(bm, x0, x1, RIM_Y - 0.012, RIM_Y + 0.0, z_out - side * 0.0, z_out + side * 0.075, F)
        # Channel walls.
        zc = LINE_Z + side * (CHANNEL_HALF + 0.006)
        for a, b in _gaps(x0, x1, PADDLE_X, PADDLE_T / 2 + 0.02) if side < 0 else [(x0, x1)]:
            gbox(bm, a, b, CHANNEL_BOTTOM, flank_y(LINE_Z + side * CHANNEL_HALF), zc - 0.006, zc + 0.006, F)
    # Channel bottom wear strip the chain rides on.
    gbox(bm, x0, x1, CHANNEL_BOTTOM - 0.016, CHANNEL_BOTTOM, LINE_Z - CHANNEL_HALF - 0.012,
         LINE_Z + CHANNEL_HALF + 0.012, W)
    # End plates.
    for x in (x0, x1):
        gbox(bm, x - 0.008, x + 0.008, CHANNEL_BOTTOM - 0.016, CHANNEL_BOTTOM + 0.05, LINE_Z - 0.4, LINE_Z + 0.4, F)


def build_stands(bm, F, D):
    for x in STAND_X:
        # Cradle under both flanks, cross beam, two legs, base plates.
        for side in (-1, 1):
            z_out = LINE_Z + side * (RIM_Y - APEX_Y - 0.02)
            beam(bm, (x, 0.05, LINE_Z + side * 0.06), (x, RIM_Y - 0.12, z_out), 0.1, 0.1, F)
            z_leg = LINE_Z + side * 0.42
            gbox(bm, x - 0.06, x + 0.06, FLOOR, 0.05, z_leg - 0.06, z_leg + 0.06, F)
            gbox(bm, x - 0.15, x + 0.15, FLOOR, FLOOR + 0.02, z_leg - 0.15, z_leg + 0.15, F)
        gbox(bm, x - 0.07, x + 0.07, -0.05, 0.05, LINE_Z - 0.55, LINE_Z + 0.55, F)
        # Channel saddle.
        gbox(bm, x - 0.06, x + 0.06, 0.05, CHANNEL_BOTTOM - 0.016, LINE_Z - 0.1, LINE_Z + 0.1, F)
        # Kicker shaft bearing on the far cradle.
        pz, py = KICK_PIVOT
        gbox(bm, x - 0.07, x + 0.07, py - 0.12, py - 0.06, pz - 0.1, pz + 0.1, F)
        cyl_x(bm, G(x, py, pz), 0.08, 0.12, mat_index=D)
    # Longitudinal ties between the legs.
    for side in (-1, 1):
        z_leg = LINE_Z + side * 0.42
        gbox(bm, STAND_X[0], STAND_X[-1], -0.75, -0.67, z_leg - 0.04, z_leg + 0.04, F)


def build_skids(bm, F, W):
    tz, ty = SKID_TOP
    fz, fy = SKID_FOOT
    for x in RIB_X:
        plate(bm, x, 0.05, [(tz - 0.02, ty), (fz, fy), (fz, fy - 0.12), (tz + 0.05, ty - 0.45),
                            (tz - 0.02, ty - 0.35)], F)
        # Hard-faced top edge.
        a, b = G(x, ty + 0.01, tz), G(x, fy + 0.01, fz)
        m, length = L.frame_between(a, b, up=(0, 0, 1))
        L.add_box(bm, (length, 0.07, 0.02), m, W)
        # Foot post.
        gbox(bm, x - 0.04, x + 0.04, FLOOR, fy - 0.1, fz - 0.06, fz + 0.02, F)


def build_sprockets(coll, mats, parent):
    out = []
    for name, x in (("LK_HeadShaft", HEAD_X), ("LK_TailShaft", TAIL_X)):
        root = empty(name, coll, parent, G(x, CHAIN_Y - SPROCKET_R, LINE_Z), 0.2)
        bm = bmesh.new()
        L.add_cyl(bm, SPROCKET_R - 0.02, 0.04, L.mat((0, 0, 0), (90, 0, 0)), segs=28, mat_index=0)
        L.add_cyl(bm, 0.045, 1.2 if name == "LK_HeadShaft" else 0.9, L.mat((0, 0.1, 0), (90, 0, 0)), segs=16,
                  mat_index=1)
        for k in range(10):
            a = 2 * math.pi * k / 10
            c = Vector((math.cos(a), 0, math.sin(a))) * (SPROCKET_R - 0.005)
            L.add_box(bm, (0.04, 0.035, 0.05), Matrix.Translation(c) @ L.mat(rot=(0, -math.degrees(a) + 90, 0)), 0)
        L.make_object(name + "Mesh", bm, coll, (mats["wear"], mats["dark"]), parent=root)
        out.append(root)
    return out


def build_drive_and_bearings(bm, F, MO, D):
    sy = CHAIN_Y - SPROCKET_R
    for x in (HEAD_X, TAIL_X):
        for side in (-1, 1):
            z = LINE_Z + side * 0.3
            gbox(bm, x - 0.09, x + 0.09, sy - 0.08, sy + 0.06, z - 0.07, z + 0.07, D)
            gbox(bm, x - 0.06, x + 0.06, FLOOR, sy - 0.08, z - 0.05, z + 0.05, F)
    # Shaft-mounted gearbox and motor on the head shaft, far side.
    z = LINE_Z - 0.62
    gbox(bm, HEAD_X - 0.2, HEAD_X + 0.2, sy - 0.25, sy + 0.2, z - 0.14, z + 0.14, MO)
    cyl_x(bm, G(HEAD_X + 0.05, sy + 0.38, z - 0.02), 0.13, 0.5, mat_index=MO)
    beam(bm, (HEAD_X, sy - 0.2, z), (HEAD_X, FLOOR, z - 0.25), 0.06, 0.06, F)
    gbox(bm, HEAD_X - 0.12, HEAD_X + 0.12, sy + 0.3, sy + 0.46, z - 0.2, z - 0.12, D)


def build_end_stop(bm, F, D, R):
    xs = (STOP_FACE_X + 0.45, STOP_FACE_X + 0.75)
    # Portal frame round the trough end.
    for z in (LINE_Z - 0.62, LINE_Z + 0.62):
        gbox(bm, xs[0], xs[1], FLOOR, 1.45, z - 0.1, z + 0.1, F)
        gbox(bm, xs[0] - 0.2, xs[1] + 0.2, FLOOR, FLOOR + 0.025, z - 0.25, z + 0.25, F)
        beam(bm, (xs[1] + 0.05, 1.3, z), (xs[1] + 0.85, FLOOR + 0.03, z), 0.12, 0.12, F)
    gbox(bm, xs[0], xs[1], 1.45, 1.62, LINE_Z - 0.75, LINE_Z + 0.75, F)
    # Heavy backstop block the absorbers sit in.
    gbox(bm, xs[0], xs[1], 0.45, 1.25, LINE_Z - 0.52, LINE_Z + 0.52, F)
    for z in (LINE_Z - 0.25, LINE_Z + 0.25):
        for y in (0.68, 1.02):
            cyl_x(bm, G(xs[0] - 0.13, y, z), 0.075, 0.26, mat_index=D)
            cyl_x(bm, G(xs[0] - 0.005, y, z), 0.095, 0.03, mat_index=D)
    # Warning stripes on the block face.
    for k in range(4):
        y0 = 0.5 + k * 0.2
        gbox(bm, xs[0] - 0.006, xs[0], y0, y0 + 0.08, LINE_Z - 0.5, LINE_Z + 0.5, R)


def build_hpu(bm, F, MO, D, RED):
    hx, hz = 14.6, 0.45
    gbox(bm, hx - 0.6, hx + 0.6, FLOOR, FLOOR + 0.08, hz - 0.4, hz + 0.4, F)
    gbox(bm, hx - 0.55, hx + 0.55, FLOOR + 0.08, FLOOR + 0.6, hz - 0.35, hz + 0.35, MO)
    cyl_x(bm, G(hx - 0.15, FLOOR + 0.8, hz), 0.14, 0.5, mat_index=MO)
    cyl_x(bm, G(hx + 0.2, FLOOR + 0.8, hz), 0.07, 0.2, mat_index=D)
    gbox(bm, hx + 0.25, hx + 0.45, FLOOR + 0.6, FLOOR + 0.95, hz - 0.15, hz + 0.15, D)
    # Valve stand with the kicker's directional valve and a lever.
    gbox(bm, hx - 0.5, hx - 0.44, FLOOR + 0.6, FLOOR + 1.35, hz + 0.2, hz + 0.26, F)
    gbox(bm, hx - 0.6, hx - 0.34, FLOOR + 1.1, FLOOR + 1.3, hz + 0.26, hz + 0.36, D)
    gbox(bm, hx - 0.5, hx - 0.46, FLOOR + 1.3, FLOOR + 1.55, hz + 0.3, hz + 0.32, RED)


def build_frame(coll, mats):
    root = empty("LK_Frame", coll, None, (0, 0, 0), 0.5)
    F, W, D, MO, RU, R = 0, 1, 2, 3, 4, 5
    bm = bmesh.new()
    build_trough(bm, F, W, D)
    build_stands(bm, F, D)
    build_skids(bm, F, W)
    build_drive_and_bearings(bm, F, MO, D)
    build_end_stop(bm, F, D, R)
    build_hpu(bm, F, MO, D, R)
    # Cylinder anchor bracket on the floor.
    az, ay = CYL_ANCHOR
    gbox(bm, CRANK_X - 0.15, CRANK_X + 0.15, FLOOR, FLOOR + 0.03, az - 0.2, az + 0.2, F)
    for s in (-1, 1):
        gbox(bm, CRANK_X + s * 0.07 - 0.012, CRANK_X + s * 0.07 + 0.012, FLOOR, ay + 0.08, az - 0.08, az + 0.08, F)
    cyl_x(bm, G(CRANK_X, ay, az), 0.03, 0.2, mat_index=D)
    L.make_object("LK_FrameMesh", bm, coll, (mats["frame"], mats["wear"], mats["dark"], mats["motor"],
                                             mats["rubber"], mats["moving"]), parent=root)
    build_sprockets(coll, mats, root)
    return root


# --- Moving parts ----------------------------------------------------------------------

def paddle_outline():
    """Paddle in Godot (z, y) at rest: lying under the far flank, hub on the pivot."""
    pz, py = KICK_PIVOT
    pts = [(pz + 0.02, flank_y(pz + 0.02) - 0.012), (1.70, flank_y(1.70) - 0.012), (1.60, 0.95),
           (1.56, 0.93), (1.64, 0.78), (pz - 0.1, py - 0.06)]
    hub = [(pz + 0.075 * math.cos(a), py + 0.075 * math.sin(a))
           for a in [math.radians(d) for d in range(-90, 50, 20)]]
    return pts + hub


def build_kicker(coll, mats):
    pz, py = KICK_PIVOT
    origin = G(0, py, pz)
    root = empty("LK_Kicker", coll, None, origin, 0.4)
    M, W, D = 0, 1, 2
    bm = bmesh.new()
    cyl_x(bm, G((CRANK_X + PADDLE_X[-1] + 0.3) / 2, py, pz) - origin, 0.05, PADDLE_X[-1] + 0.3 - CRANK_X + 0.1,
          mat_index=D)
    for x in PADDLE_X:
        plate(bm, x, PADDLE_T, paddle_outline(), M, origin)
        # Wear face where the paddle meets the log.
        a, b = G(x, flank_y(pz) - 0.005, pz - 0.01) - origin, G(x, flank_y(1.70) - 0.005, 1.70) - origin
        m, length = L.frame_between(a, b, up=(0, 0, 1))
        L.add_box(bm, (length, PADDLE_T + 0.02, 0.016), m, W)
        cyl_x(bm, G(x, py, pz) - origin, 0.09, PADDLE_T + 0.06, mat_index=D)
    # Crank on the shaft end for the cylinder.
    cz, cy = CRANK_PIN
    plate(bm, CRANK_X, 0.05, [(pz + 0.07, py), (pz + cz + 0.05, py + cy), (pz + cz - 0.05, py + cy),
                               (pz - 0.07, py)], M, origin)
    cyl_x(bm, G(CRANK_X, py, pz) - origin, 0.1, 0.1, mat_index=D)
    cyl_x(bm, G(CRANK_X, py + cy, pz + cz) - origin, 0.035, 0.16, mat_index=D)
    L.make_object("LK_KickerMesh", bm, coll, (mats["moving"], mats["wear"], mats["dark"]), parent=root)
    return root


def build_bumper(coll, mats):
    root = empty("LK_Bumper", coll, None, (0, 0, 0), 0.3)
    P, RU, CH = 0, 1, 2
    bm = bmesh.new()
    x = STOP_FACE_X
    gbox(bm, x + 0.04, x + 0.10, 0.55, 1.18, LINE_Z - 0.42, LINE_Z + 0.42, P)
    gbox(bm, x, x + 0.04, 0.6, 1.13, LINE_Z - 0.36, LINE_Z + 0.36, RU)
    for z in (LINE_Z - 0.25, LINE_Z + 0.25):
        for y in (0.68, 1.02):
            cyl_x(bm, G(x + 0.22, y, z), 0.04, 0.24, mat_index=CH)
    L.make_object("LK_BumperMesh", bm, coll, (mats["moving"], mats["rubber"], mats["chrome"]), parent=root)
    return root


def cyl_frame(direction, pin):
    y = Vector(direction).normalized()
    z = Vector(pin)
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


def build_cylinder(coll, mats):
    """Barrel at the floor anchor, rod at the crank pin; each +Y towards the other."""
    pz, py = KICK_PIVOT
    cz, cy = CRANK_PIN
    anchor = G(CRANK_X, CYL_ANCHOR[1], CYL_ANCHOR[0])
    pin = G(CRANK_X, py + cy, pz + cz)
    d = pin - anchor
    pin_axis = (1, 0, 0)
    barrel = empty("LK_CylBarrel", coll, None, anchor, 0.15)
    barrel.matrix_world = Matrix.Translation(anchor) @ cyl_frame(d, pin_axis).to_4x4()
    rod = empty("LK_CylRod", coll, None, pin, 0.15)
    rod.matrix_world = Matrix.Translation(pin) @ cyl_frame(-d, pin_axis).to_4x4()
    bm = bmesh.new()
    L.add_cyl(bm, 0.07, 0.95, L.mat((0, 0.55, 0), (-90, 0, 0)), segs=20, mat_index=0)
    L.add_cyl(bm, 0.03, 0.12, L.mat((0, 0, 0), (0, 90, 0)), segs=12, mat_index=1)
    L.add_cyl(bm, 0.075, 0.05, L.mat((0, 1.0, 0), (-90, 0, 0)), segs=20, mat_index=1)
    L.make_object("LK_CylBarrelMesh", bm, coll, (mats["dark"], mats["dark"]), parent=barrel)
    bm = bmesh.new()
    L.add_cyl(bm, 0.035, 1.15, L.mat((0, 0.575, 0), (-90, 0, 0)), segs=16, mat_index=0)
    L.add_cyl(bm, 0.05, 0.12, L.mat((0, 0, 0), (0, 90, 0)), segs=12, mat_index=1)
    L.make_object("LK_CylRodMesh", bm, coll, (mats["chrome"], mats["dark"]), parent=rod)
    return barrel, rod


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = build_materials()
    build_frame(coll, mats)
    build_kicker(coll, mats)
    build_bumper(coll, mats)
    build_cylinder(coll, mats)
    return {"objects": len(coll.all_objects), "apex": APEX_Y}


def pose(kick_deg=0.0, bumper=0.0):
    """Turn the kicker (deg, up through the V) and push the bumper back (m)."""
    k = bpy.data.objects["LK_Kicker"]
    k.rotation_euler = (math.radians(kick_deg), 0, 0)
    bpy.data.objects["LK_Bumper"].location = (bumper, 0, 0)
    bpy.context.view_layer.update()
    pin = k.matrix_world @ (G(CRANK_X, KICK_PIVOT[1] + CRANK_PIN[1], KICK_PIVOT[0] + CRANK_PIN[0]) - k.location)
    barrel = bpy.data.objects["LK_CylBarrel"]
    rod = bpy.data.objects["LK_CylRod"]
    d = pin - barrel.location
    barrel.matrix_world = Matrix.Translation(barrel.location) @ cyl_frame(d, (1, 0, 0)).to_4x4()
    rod.matrix_world = Matrix.Translation(pin) @ cyl_frame(-d, (1, 0, 0)).to_4x4()
