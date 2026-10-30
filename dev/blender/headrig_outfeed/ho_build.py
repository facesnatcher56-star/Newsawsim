"""Headrig outfeed: live roll case with kicker arms (run inside Blender).

Slabs are kicked onto the slab slasher of the waste system (dev/blender/waste); the slab flight
trough and small drum chipper this file still has builders for are no longer built or exported.

What comes off the band headrig rides the outfeed live rolls on down a roll case:
  - slab kickers (four arms on one shaft, -Z side pivot) tip slabs off the -Z edge down skid
    plates into the slab conveyor: a single-strand flight chain in a steel trough running
    end-first into the drum chipper
  - cant kickers (+Z side pivot) in the same zone throw the cant to +Z, to the gang resaw
  - boards ride to the cushioned end stop where the board kickers throw them to +Z onto the
    board line's transfer chains
  - drum chipper: infeed throat with rubber curtain and a fluted top feed roll, drum housing,
    belt drive from a side motor, blower under the drum and a chip pipe out through the wall

Each kicker shaft swings on an air cylinder off a crank at its upstream end. Built in mill
coordinates like the headrig: Godot (x, y, z) = Blender (x, -z, y + 1.288), see H.G().

  HO_Frame                          case frame, end stop, skids, trough, chipper, blower, pipe
  HO_Roll1..n                       live rolls (spin about Z)
  HO_SlabKick / HO_CantKick / HO_BoardKick   kicker shafts with arms and crank (rotate about X)
  HO_<Kick>Cyl / HO_<Kick>Rod       cylinder body and rod at the floor anchor, along local -Z
                                    (Godot aims them at the crank pin; the rod is 1 m, scaled)
  HO_TroughHead / HO_TroughTail     trough chain sprockets (spin about Z)
  HO_Flight                         one chain flight with its link, for instancing
  HO_FeedRoll                       chipper top feed roll (spins about Z)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
import hr_build as H  # noqa: E402
import mesh_lib as L  # noqa: E402

G, gbox, beam, cyl_x, cyl_y, cyl_z, plate_zy, empty = H.G, H.gbox, H.beam, H.cyl_x, H.cyl_y, H.cyl_z, H.plate_zy, H.empty
M = H.M
FLOOR = H.FLOOR

COLL = "HeadrigOutfeed"
# Roll case, continuing the headrig's outfeed rolls.
CASE_X = (29.0, 43.6)
CASE_Z = H.OUT_Z                       # (4.8, 5.7)
TOP_Y = H.OUT_TOP_Y                    # -0.15
ROLL_R = H.OUT_ROLL_R
ROLL_X = tuple(29.3 + 0.6 * k for k in range(24))
STOP_X = 43.45                         # end stop face
# Kickers: arms between the rolls, shaft pivot (z, y); the arm tip reaches across the case.
KICKERS = {
    "Slab": {"xs": (30.8, 32.0, 33.2, 34.4), "pivot": (4.60, -0.58)},
    "Cant": {"xs": (31.4, 32.6, 33.8, 35.0), "pivot": (5.90, -0.58)},
    "Board": {"xs": (39.2, 40.4, 41.6, 42.8), "pivot": (5.90, -0.58)},
}
ARM_LEN = 1.12
CRANK = 0.28
KICK_DEG = 34.0
# Slab conveyor trough.
TROUGH_X = (29.4, 44.5)
TROUGH_Z = (3.55, 4.20)
TROUGH_FLOOR_Y = -0.86
SPROCKET_R = 0.12
FLIGHT_PITCH = 0.6
# Drum chipper.
CHIP_MOUTH_X = 44.55
FEED_ROLL = (45.1, -0.52, 0.2)        # x, y, r
DRUM = (46.25, -0.60, 0.75)           # x, y of the axis, hood radius
CHIP_Z = (3.42, 4.33)
MOTOR = (48.05, -0.66, 0.42)          # x, y, r (axis along Z)
BLOWER = (47.55, -0.80, 0.42)
PIPE_R = 0.17
PIPE_TOP_Y = 4.2
WALL_X = 57.8


def side(pz):
    """+1 when the arm reaches toward +Z from this pivot (its shaft is on the -Z side)."""
    return 1 if pz < (CASE_Z[0] + CASE_Z[1]) / 2 else -1


def crank_x(xs):
    return xs[0] - 0.42


def anchor(pz, s):
    """Floor clevis of the kicker cylinder, (z, y)."""
    return pz - s * 0.75, FLOOR + 0.16


# --- Roll case -------------------------------------------------------------------------------

def build_case(bm):
    x0, x1 = CASE_X
    z0, z1 = CASE_Z
    yc = TOP_Y - ROLL_R
    for z in (z0 - 0.06, z1 + 0.06):
        gbox(bm, x0, x1 + 0.1, yc - 0.17, yc + 0.05, z - 0.05, z + 0.05, M["frame"])
        gbox(bm, x0, x1 + 0.1, FLOOR + 0.25, FLOOR + 0.33, z - 0.04, z + 0.04, M["frame"])
    x = x0 + 0.15
    while x < x1 + 0.2:
        for z in (z0 - 0.06, z1 + 0.06):
            gbox(bm, x - 0.06, x + 0.06, FLOOR, yc - 0.17, z - 0.06, z + 0.06, M["frame"])
            gbox(bm, x - 0.12, x + 0.12, FLOOR, FLOOR + 0.02, z - 0.12, z + 0.12, M["dark"])
        gbox(bm, x - 0.04, x + 0.04, FLOOR + 0.25, FLOOR + 0.33, z0 - 0.06, z1 + 0.06, M["frame"])
        x += 1.8
    # Chain drive on the +Z ends of the rolls, under a guard, from gearmotors at the far end.
    gbox(bm, x0, x1, yc - 0.13, yc + 0.08, z1 + 0.12, z1 + 0.16, M["moving"])
    gbox(bm, x0, x1, yc + 0.08, yc + 0.1, z1 + 0.02, z1 + 0.16, M["moving"])
    gbox(bm, x1 - 0.9, x1 - 0.2, FLOOR + 0.35, FLOOR + 0.75, z1 + 0.25, z1 + 0.65, M["motor"])
    cyl_y(bm, G(x1 - 0.55, FLOOR + 0.55, z1 + 0.75), 0.17, 0.3, mat_index=M["motor"])
    gbox(bm, x1 - 0.65, x1 - 0.45, FLOOR + 0.75, yc - 0.13, z1 + 0.14, z1 + 0.2, M["moving"])
    # End stop: heavy post pair, a cross plate and a rubber bumper pad.
    for z in (z0 - 0.15, z1 + 0.15):
        gbox(bm, STOP_X + 0.14, STOP_X + 0.34, FLOOR, TOP_Y + 0.45, z - 0.1, z + 0.1, M["frame"])
        beam(bm, (STOP_X + 0.3, TOP_Y + 0.3, z), (STOP_X + 1.0, FLOOR, z), 0.12, 0.12, M["frame"])
    gbox(bm, STOP_X + 0.1, STOP_X + 0.16, TOP_Y - 0.05, TOP_Y + 0.42, z0 - 0.2, z1 + 0.2, M["frame"])
    gbox(bm, STOP_X, STOP_X + 0.1, TOP_Y - 0.02, TOP_Y + 0.36, z0 + 0.05, z1 - 0.05, M["rubber"])
    for z in (z0 + 0.25, z1 - 0.25):
        cyl_x(bm, G(STOP_X + 0.11, TOP_Y + 0.17, z), 0.06, 0.08, mat_index=M["chrome"])
    # Side guide rails between the kick zones keep pieces on the case.
    for xa, xb in ((35.6, 38.7),):
        for z in (z0 - 0.08, z1 + 0.08):
            gbox(bm, xa, xb, TOP_Y + 0.02, TOP_Y + 0.2, z - 0.03, z + 0.03, M["wear"])
            for xp in (xa + 0.2, xb - 0.2):
                gbox(bm, xp - 0.03, xp + 0.03, TOP_Y - 0.2, TOP_Y + 0.02, z - 0.03, z + 0.03, M["frame"])


def build_rolls(coll, mats):
    z0, z1 = CASE_Z
    yc = TOP_Y - ROLL_R
    rolls = []
    for i, x in enumerate(ROLL_X):
        r = empty("HO_Roll%d" % (i + 1), coll, None, G(x, yc, (z0 + z1) / 2), 0.1)
        rb = bmesh.new()
        L.add_cyl(rb, ROLL_R, z1 - z0, L.mat(rot=(90, 0, 0)), segs=20, mat_index=M["wear"])
        L.add_cyl(rb, 0.03, z1 - z0 + 0.3, L.mat(loc=(0, -0.08, 0), rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
        L.add_cyl(rb, 0.075, 0.025, L.mat(loc=(0, -(z1 - z0) / 2 - 0.2, 0), rot=(90, 0, 0)), segs=16,
                  mat_index=M["dark"])
        for k in range(3):
            L.add_box(rb, (0.012, z1 - z0 - 0.04, 0.012),
                      Matrix.Rotation(k * 2 * math.pi / 3, 4, 'Y') @ Matrix.Translation((0, 0, ROLL_R)), M["dark"])
        H.make("HO_Roll%dMesh" % (i + 1), rb, coll, mats, r)
        rolls.append(r)
    return rolls


def arm_outline(pz, py, s):
    pts = [(pz - s * 0.1, py - 0.08), (pz + s * 0.08, py - 0.1), (pz + s * ARM_LEN, py + 0.3),
           (pz + s * (ARM_LEN + 0.02), py + 0.37), (pz + s * (ARM_LEN - 0.08), py + 0.37),
           (pz - s * 0.09, py + 0.08)]
    return pts if s > 0 else list(reversed(pts))


def build_kicker(coll, mats, frame_bm, name, spec):
    xs = spec["xs"]
    pz, py = spec["pivot"]
    s = side(pz)
    xc = crank_x(xs)
    piv = G((xs[0] + xs[-1]) / 2, py, pz)
    root = empty("HO_%sKick" % name, coll, None, piv, 0.2)
    bm = bmesh.new()
    o = piv
    cyl_x(bm, G((xc + xs[-1] + 0.1) / 2, py, pz) - o, 0.05, xs[-1] + 0.1 - xc + 0.1, mat_index=M["dark"])
    for x in xs:
        plate_zy(bm, x, 0.04, arm_outline(pz, py, s), M["moving"], o)
        cyl_x(bm, G(x, py, pz) - o, 0.09, 0.1, mat_index=M["moving"])
    # Crank hanging down from the shaft at its upstream end, with the rod-end pin.
    plate_zy(bm, xc, 0.04, [(pz - 0.07, py + 0.07), (pz + 0.07, py + 0.07), (pz + 0.05, py - CRANK - 0.05),
                            (pz - 0.05, py - CRANK - 0.05)], M["moving"], o)
    cyl_x(bm, G(xc + 0.05, py - CRANK, pz) - o, 0.025, 0.16, mat_index=M["chrome"])
    H.make("HO_%sKickMesh" % name, bm, coll, mats, root)
    # Shaft bearings on stands (frame).
    for x in (xc + 0.1, xs[-1] + 0.15):
        gbox(frame_bm, x - 0.07, x + 0.07, py - 0.08, py + 0.08, pz - 0.1, pz + 0.1, M["dark"])
        gbox(frame_bm, x - 0.05, x + 0.05, FLOOR, py - 0.08, pz - 0.06, pz + 0.06, M["frame"])
    # Cylinder: clevis on the floor, body and rod as separate parts aimed by the game.
    az, ay = anchor(pz, s)
    gbox(frame_bm, xc - 0.1, xc + 0.2, FLOOR, ay - 0.04, az - 0.12, az + 0.12, M["frame"])
    cyl_x(frame_bm, G(xc + 0.05, ay, az), 0.03, 0.2, mat_index=M["chrome"])
    cyl = empty("HO_%sCyl" % name, coll, None, G(xc + 0.05, ay, az), 0.1)
    cb = bmesh.new()
    # Along local Godot -Z = Blender +Y.
    L.add_cyl(cb, 0.06, 0.5, L.mat(loc=(0, 0.3, 0), rot=(90, 0, 0)), segs=16, mat_index=M["dark"])
    L.add_cyl(cb, 0.075, 0.05, L.mat(loc=(0, 0.06, 0), rot=(90, 0, 0)), segs=16, mat_index=M["dark"])
    L.add_cyl(cb, 0.075, 0.05, L.mat(loc=(0, 0.54, 0), rot=(90, 0, 0)), segs=16, mat_index=M["dark"])
    L.add_box(cb, (0.05, 0.1, 0.1), Matrix.Translation((0, 0.02, 0)), M["dark"])
    H.make("HO_%sCylMesh" % name, cb, coll, mats, cyl)
    rod = empty("HO_%sRod" % name, coll, None, G(xc + 0.05, ay, az), 0.1)
    rb = bmesh.new()
    L.add_cyl(rb, 0.022, 1.0, L.mat(loc=(0, 0.5, 0), rot=(90, 0, 0)), segs=12, mat_index=M["chrome"])
    H.make("HO_%sRodMesh" % name, rb, coll, mats, rod)
    return root


def build_skids(bm):
    """Skid plates off the -Z edge into the trough (slab zone) and off the +Z edge onto the
    board transfer (board zone), slotted round the arms."""
    z0, z1 = CASE_Z
    def runs(xa, xb, arms):
        edges = [xa] + [v for a in sorted(arms) for v in (a - 0.07, a + 0.07)] + [xb]
        return [(edges[i], edges[i + 1]) for i in range(0, len(edges), 2)]
    slab_arms = KICKERS["Slab"]["xs"] + KICKERS["Cant"]["xs"]
    for xa, xb in runs(30.1, 35.6, slab_arms):
        beam(bm, ((xa + xb) / 2, TOP_Y - 0.04, z0 - 0.04), ((xa + xb) / 2, -0.43, 4.6), xb - xa, 0.02,
             M["wear"])
    for xa, xb in runs(38.7, 43.4, KICKERS["Board"]["xs"]):
        beam(bm, ((xa + xb) / 2, TOP_Y - 0.04, z1 + 0.18), ((xa + xb) / 2, TOP_Y - 0.12, 6.35), xb - xa, 0.02,
             M["wear"])
    for x in (30.1, 35.6):
        gbox(bm, x - 0.04, x + 0.04, FLOOR, TOP_Y - 0.05, z0 - 0.3, z0 - 0.22, M["frame"])
    for x in (38.75, 43.35):
        gbox(bm, x - 0.04, x + 0.04, FLOOR, TOP_Y - 0.15, 6.2, 6.28, M["frame"])


# --- Slab conveyor --------------------------------------------------------------------------

def trough_loop():
    """Closed chain line in (x, y): top run along the trough floor towards +X, round the head
    sprocket, back under the floor, round the tail. Centres of the two sprockets."""
    x0, x1 = TROUGH_X[0] + 0.25, TROUGH_X[1] - 0.25
    yc = TROUGH_FLOOR_Y - SPROCKET_R
    return (x0, yc), (x1, yc)


def build_trough(bm):
    x0, x1 = TROUGH_X
    z0, z1 = TROUGH_Z
    zc = (z0 + z1) / 2
    fy = TROUGH_FLOOR_Y
    # Floor in two halves either side of the chain slot, sides flared out at the top.
    gbox(bm, x0, x1, fy - 0.025, fy, z0, zc - 0.05, M["wear"])
    gbox(bm, x0, x1, fy - 0.025, fy, zc + 0.05, z1, M["wear"])
    gbox(bm, x0, x1, fy - 0.12, fy - 0.025, zc - 0.07, zc - 0.05, M["frame"])
    gbox(bm, x0, x1, fy - 0.12, fy - 0.025, zc + 0.05, zc + 0.07, M["frame"])
    for z, out in ((z0, -1), (z1, 1)):
        top = -0.48 if out < 0 else -0.56
        gbox(bm, x0, x1, fy - 0.025, top, z - 0.012, z + 0.012, M["frame"])
        gbox(bm, x0, x1, top - 0.06, top, z + out * 0.012, z + out * 0.06, M["frame"])
    # Return-run guide and legs.
    gbox(bm, x0, x1, fy - 2 * SPROCKET_R - 0.06, fy - 2 * SPROCKET_R - 0.03, zc - 0.08, zc + 0.08, M["wear"])
    x = x0 + 0.3
    while x < x1:
        for z in (z0 + 0.05, z1 - 0.05):
            gbox(bm, x - 0.05, x + 0.05, FLOOR, fy - 0.025, z - 0.04, z + 0.04, M["frame"])
        gbox(bm, x - 0.04, x + 0.04, fy - 0.2, fy - 0.12, z0, z1, M["frame"])
        x += 1.8
    # Tail take-up and head drive bearings, gearmotor at the head on the -Z side.
    (tx, ty), (hx, hy) = trough_loop()
    for px in (tx, hx):
        for z in (z0 - 0.06, z1 + 0.06):
            gbox(bm, px - 0.1, px + 0.1, ty - 0.08, ty + 0.08, z - 0.05, z + 0.05, M["dark"])
            gbox(bm, px - 0.05, px + 0.05, FLOOR, ty - 0.08, z - 0.04, z + 0.04, M["frame"])
    cyl_y(bm, G(hx, hy, z0 - 0.25), 0.03, 0.4, mat_index=M["dark"])
    gbox(bm, hx - 0.25, hx + 0.25, FLOOR, hy - 0.12, z0 - 0.65, z0 - 0.25, M["frame"])
    gbox(bm, hx - 0.2, hx + 0.2, hy - 0.12, hy + 0.22, z0 - 0.62, z0 - 0.3, M["motor"])
    cyl_y(bm, G(hx, hy + 0.05, z0 - 0.85), 0.14, 0.45, mat_index=M["motor"])


def build_trough_parts(coll, mats):
    (tx, ty), (hx, hy) = trough_loop()
    zc = sum(TROUGH_Z) / 2
    out = []
    for name, x in (("HO_TroughTail", tx), ("HO_TroughHead", hx)):
        e = empty(name, coll, None, G(x, ty, zc), 0.1)
        bm = bmesh.new()
        L.add_cyl(bm, SPROCKET_R + 0.015, 0.03, L.mat(rot=(90, 0, 0)), segs=12, mat_index=M["dark"])
        L.add_cyl(bm, 0.04, 0.9, L.mat(rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
        H.make(name + "Mesh", bm, coll, mats, e)
        out.append(e)
    # One flight: a link along X and a paddle across the trough, pointing up (local +Y Godot).
    f = empty("HO_Flight", coll, None, (0, 0, 0), 0.05)
    bm = bmesh.new()
    L.add_box(bm, (FLIGHT_PITCH - 0.02, 0.025, 0.035), Matrix.Translation((0, 0, 0)), M["dark"])
    L.add_box(bm, (0.025, TROUGH_Z[1] - TROUGH_Z[0] - 0.06, 0.09), Matrix.Translation((0, 0, 0.055)), M["wear"])
    H.make("HO_FlightMesh", bm, coll, mats, f)
    out.append(f)
    return out


# --- Drum chipper ---------------------------------------------------------------------------

def build_chipper(bm):
    z0, z1 = CHIP_Z
    fy = TROUGH_FLOOR_Y
    mx = CHIP_MOUTH_X
    dx, dy, dr = DRUM
    # Infeed throat: side cheeks, roof and floor, rubber curtain strips over the mouth.
    for z in (z0, z1):
        gbox(bm, mx, dx - 0.5, fy - 0.03, 0.08, z - 0.03, z + 0.03, M["mill"])
    gbox(bm, mx, dx - 0.5, 0.05, 0.11, z0 - 0.03, z1 + 0.03, M["mill"])
    gbox(bm, mx, dx - 0.5, fy - 0.06, fy, z0, z1, M["wear"])
    for k in range(7):
        z = z0 + 0.07 + k * (z1 - z0 - 0.14) / 6
        gbox(bm, mx + 0.02, mx + 0.03, fy + 0.15, 0.05, z - 0.055, z + 0.055, M["rubber"])
    gbox(bm, mx - 0.04, mx + 0.04, fy - 0.03, 0.12, z0 - 0.06, z1 + 0.06, M["mill"])
    # Feed roll hinge arms and its counterweight spring cans.
    fx, fry, frr = FEED_ROLL
    for z in (z0 - 0.06, z1 + 0.06):
        beam(bm, (fx, fry, z), (dx - 0.55, 0.0, z), 0.06, 0.1, M["mill"])
        cyl_z(bm, G(fx - 0.12, -0.1, z), 0.05, 0.35, mat_index=M["dark"])
    # Drum housing: base box, the hood (half cylinder over the drum), an inspection door.
    gbox(bm, dx - 0.6, dx + 0.75, FLOOR, dy, z0 - 0.04, z1 + 0.04, M["mill"])
    cyl_y(bm, G(dx, dy, (z0 + z1) / 2), dr, z1 - z0 + 0.08, segs=32, mat_index=M["mill"])
    gbox(bm, dx - 0.6, dx + 0.75, FLOOR, FLOOR + 0.08, z0 - 0.15, z1 + 0.15, M["dark"])
    gbox(bm, dx - 0.3, dx + 0.3, dy + 0.05, dy + 0.6, z1 + 0.04, z1 + 0.06, M["dark"])
    for y in (dy + 0.1, dy + 0.55):
        gbox(bm, dx - 0.36, dx - 0.3, y - 0.04, y + 0.04, z1 + 0.04, z1 + 0.09, M["chrome"])
    # Drum bearings and shaft, sheave and belt guard on the -Z side out to the motor.
    for z in (z0 - 0.17, z1 + 0.17):
        gbox(bm, dx - 0.18, dx + 0.18, FLOOR, dy - 0.12, z - 0.12, z + 0.12, M["mill"])
        gbox(bm, dx - 0.14, dx + 0.14, dy - 0.12, dy + 0.12, z - 0.1, z + 0.1, M["dark"])
    cyl_y(bm, G(dx, dy, (z0 + z1) / 2 - 0.25), 0.08, z1 - z0 + 0.9, mat_index=M["chrome"])
    mxx, my, mr = MOTOR
    gz = z0 - 0.45
    # Belt guard: outline in Godot (x, y), across Z (Blender Y = -Z).
    L.add_prism(bm, [(dx - 0.3, dy - 0.32 - FLOOR), (mxx + 0.32, my - 0.3 - FLOOR),
                     (mxx + 0.32, my + 0.3 - FLOOR), (dx - 0.3, dy + 0.32 - FLOOR)],
                -(gz + 0.1), -(gz - 0.1), None, M["moving"])
    # Motor: frame, body, fan cowl, terminal box, on a base with slide rails.
    mz0, mz1 = gz - 1.55, gz - 0.12
    gbox(bm, mxx - 0.45, mxx + 0.45, FLOOR, FLOOR + 0.12, mz0 - 0.1, mz1 + 0.05, M["dark"])
    gbox(bm, mxx - 0.35, mxx + 0.35, FLOOR + 0.12, my - mr * 0.6, mz0 + 0.1, mz1 - 0.1, M["motor"])
    cyl_y(bm, G(mxx, my, (mz0 + mz1) / 2), mr, mz1 - mz0 - 0.15, segs=28, mat_index=M["motor"])
    for k in range(10):
        z = mz0 + 0.15 + k * (mz1 - mz0 - 0.4) / 9
        cyl_y(bm, G(mxx, my, z), mr + 0.03, 0.03, segs=28, mat_index=M["motor"])
    cyl_y(bm, G(mxx, my, mz0 - 0.02), mr - 0.04, 0.2, segs=28, mat_index=M["dark"])
    gbox(bm, mxx - 0.15, mxx + 0.15, my + mr - 0.05, my + mr + 0.2, mz1 - 0.6, mz1 - 0.3, M["motor"])
    cyl_y(bm, G(mxx, my, mz1 + 0.05), 0.06, 0.4, mat_index=M["chrome"])
    # Blower beside the drum: scroll housing and its own motor, chips drop in from the drum.
    bx, by, br = BLOWER
    cyl_y(bm, G(bx, by, (z0 + z1) / 2), br, 0.42, segs=28, mat_index=M["mill"])
    gbox(bm, dx + 0.7, bx - 0.15, FLOOR + 0.1, dy - 0.05, z0 + 0.15, z1 - 0.15, M["mill"])
    gbox(bm, bx - 0.4, bx + 0.4, FLOOR, by - br + 0.05, z0 + 0.1, z1 - 0.1, M["dark"])
    cyl_y(bm, G(bx, by, z1 + 0.3), 0.22, 0.4, segs=24, mat_index=M["motor"])
    # Chip pipe: up from the blower outlet, over and out through the wall.
    px = bx + br - PIPE_R
    cyl_z(bm, G(px, (by + PIPE_TOP_Y) / 2, (z0 + z1) / 2), PIPE_R, PIPE_TOP_Y - by, segs=20, mat_index=M["wear"])
    L.add_sphere(bm, PIPE_R * 1.08, Matrix.Translation(G(px, PIPE_TOP_Y, (z0 + z1) / 2)), segs=20, rings=10,
                 mat_index=M["wear"])
    cyl_x(bm, G((px + WALL_X) / 2, PIPE_TOP_Y, (z0 + z1) / 2), PIPE_R, WALL_X - px, segs=20, mat_index=M["wear"])
    for x in range(int(px) + 2, int(WALL_X), 3):
        # Hangers from the roof steel.
        gbox(bm, x - 0.02, x + 0.02, PIPE_TOP_Y + PIPE_R, 7.4, (z0 + z1) / 2 - 0.02, (z0 + z1) / 2 + 0.02,
             M["dark"])
        cyl_x(bm, G(x, PIPE_TOP_Y, (z0 + z1) / 2), PIPE_R + 0.02, 0.06, segs=20, mat_index=M["dark"])
    for y in (0.5, 2.2):
        cyl_z(bm, G(px, y, (z0 + z1) / 2), PIPE_R + 0.02, 0.06, segs=20, mat_index=M["dark"])
    # Guard rail round the chipper top for the walkway side.
    for z in (z0 - 0.75,):
        for x in (mx + 0.2, dx + 0.9):
            gbox(bm, x - 0.025, x + 0.025, FLOOR, FLOOR + 1.07, z - 0.025, z + 0.025, M["moving"])


def build_feed_roll(coll, mats):
    fx, fy, fr = FEED_ROLL
    z0, z1 = CHIP_Z
    e = empty("HO_FeedRoll", coll, None, G(fx, fy, (z0 + z1) / 2), 0.1)
    bm = bmesh.new()
    L.add_cyl(bm, fr - 0.03, z1 - z0 - 0.04, L.mat(rot=(90, 0, 0)), segs=24, mat_index=M["wear"])
    for k in range(12):
        L.add_box(bm, (0.05, z1 - z0 - 0.06, 0.05),
                  Matrix.Rotation(k * 2 * math.pi / 12, 4, 'Y') @ Matrix.Translation((0, 0, fr - 0.03)) @
                  Matrix.Rotation(math.radians(45), 4, 'Y'), M["wear"])
    L.add_cyl(bm, 0.05, z1 - z0 + 0.2, L.mat(rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
    H.make("HO_FeedRollMesh", bm, coll, mats, e)
    return e


def pose(slab_deg=0.0, cant_deg=0.0, board_deg=0.0):
    """Kicker swings (deg, 0 = rest) with the cylinders aimed at their crank pins."""
    for name, deg in (("Slab", slab_deg), ("Cant", cant_deg), ("Board", board_deg)):
        spec = KICKERS[name]
        pz, py = spec["pivot"]
        s = side(pz)
        # Godot rotation about X; the arm tip rises for -s (see side()).
        a = -s * math.radians(deg)
        k = bpy.data.objects["HO_%sKick" % name]
        k.rotation_euler = (a, 0, 0)        # a turn about X is the same angle in both axis sets
        # Crank pin in Godot (z, y) after the swing.
        pin_z = pz - CRANK * math.sin(a)
        pin_y = py - CRANK * math.cos(a)
        az, ay = anchor(pz, s)
        pin = G(crank_x(spec["xs"]) + 0.05, pin_y, pin_z)
        base = G(crank_x(spec["xs"]) + 0.05, ay, az)
        d = pin - base
        for part in ("Cyl", "Rod"):
            o = bpy.data.objects["HO_%s%s" % (name, part)]
            o.rotation_mode = 'QUATERNION'
            o.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(d.normalized())
            o.scale = (1, d.length if part == "Rod" else 1, 1)


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("HO_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_case(bm)
    build_skids(bm)
    kicks = [build_kicker(coll, mats, bm, n, s) for n, s in KICKERS.items()]
    H.make("HO_FrameMesh", bm, coll, mats, frame)
    rolls = build_rolls(coll, mats)
    pose()
    return {"objects": len(coll.all_objects), "rolls": len(rolls), "kickers": len(kicks)}
