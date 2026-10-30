"""Board line, part 2: raised deck, lug loader, scanner lug chains, zero rollers and scanner (run inside Blender).

USNR job 3338 at true size, placed like part 1 (bl_build: mill z = Z_LINE - Ye * IN, board lead ends at
x = X_ZERO), on raised support steel 51 5/8 in above the mill floor:
  - raised deck: steel grating on beams and columns, stairs and handrails, kick plate at its edge over
    the unscrambler
  - lug loader: eight plain chains from the take-away to the scanner chains; two sets of air pop-up
    stops (halfway and at the scanner end) and the flipper D's on one shaft at the halfway stops: a
    quarter turn of the shaft rolls the board held there over its long edge
  - scanner chains: nine lug chains through the 24 ft 10 in scanner frame to the lineal infeed, one
    board between each pair of lugs
  - zero rollers between the scanner chains, upstream of the scanner, pull each board endwise to the
    zero line fence
  - scanner frame with its heads above and below and the blower duct

  BD_Frame                      all fixed steel
  BD_LugTail / BD_LugHead       lug loader shafts (spin about X)
  BD_ScanTail / BD_ScanHead     scanner chain shafts (spin about X)
  BD_StopsHalf / BD_StopsEnd    pop-up stop sets (move along Y)
  BD_Flipper                    flipper shaft with the D's (rotate about X; flat side up at rest)
  BD_ZeroRoll1..n               zero rollers (spin about Z)
  BD_ScanLug                    one scanner chain lug, for instancing (lug out of the loop along +Y)
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
import bl_build as B  # noqa: E402

G, gbox, beam, cyl_x, cyl_y, cyl_z, plate_zy, empty = H.G, H.gbox, H.beam, H.cyl_x, H.cyl_y, H.cyl_z, H.plate_zy, H.empty
M = H.M
FLOOR = H.FLOOR
IN = B.IN
zye = B.zye

COLL = "BoardLineDeck"
DECK_Y = B.RAISED_Y
# Chain tops step down a few millimetres at each hand-off (unscrambler top 1.118, take-away 1.114)
# so a board's leading edge never meets a higher run.
CHAIN_Y = 1.108                                 # lug loader
SCAN_Y = 1.101                                  # scanner chains
DECK_X = (36.3, 45.0)
DECK_Z = (zye(305.0), 22.6)                     # from the retaining edge to past the infeed line


def xin(d):
    """x of a drawing distance d (inches) upstream of the zero line."""
    return B.X_ZERO - d * IN


def _clear_of(xs, others, gap=3.5 * IN):
    out = []
    for x in xs:
        near = min(others, key=lambda o: abs(o - x))
        if abs(near - x) < gap:
            x = near + (gap if x >= near else -gap)
        out.append(x)
    return tuple(out)


SCAN_X = tuple(xin(9.0 + 26.0 * k) for k in range(9))
SCAN_Z = (zye(227.0), zye(43.5))
SCAN_R = 4.0 * IN
SCAN_LUG_PITCH = 26.0 * IN
SCAN_LUG_H = 2.5 * IN
LUG_X = _clear_of(tuple(xin(d) for d in (13, 39, 59, 85, 111, 140, 162.5, 207)), SCAN_X)
LUG_Z = (zye(292.0), zye(234.0))
LUG_R = 3.5 * IN
# The lug loader runs as two interleaved chain sections overlapping across the halfway stops; the
# downstream one is faster, so a board let go at the stops pulls away from the queue behind it and
# the stops can pop up in the gap.
LUG_A_Z = (LUG_Z[0], zye(260.0))
LUG_B_X = tuple(x - 0.07 for x in LUG_X)
LUG_B_Z = (zye(272.0), LUG_Z[1])
STOP_END_Z = zye(239.0)
STOP_HALF_Z = zye(266.0)
STOP_UP = 2.5 * IN                              # stop tops above the chain tops when up
STOP_DROP = 3.5 * IN
FLIP_Z = zye(268.0)
D_R = 3.2 * IN
ZERO_ROLL_Z = zye(196.0)
ZERO_ROLL_R = 2.0 * IN
ZERO_ROLL_TOP = SCAN_Y + 0.9 * IN
SCANNER_Z = zye(121.0)
DEAD_IN_Y = 1.111                               # take-away (1.114) to lug loader (1.108)
DEAD_OUT_Y = 1.1045                             # lug loader (1.108) to scanner chains (1.101)
FENCE_X = B.X_ZERO + 0.15                       # just past the longest board ends coming in


def zero_roll_xs():
    xs = sorted(SCAN_X)
    return tuple((a + b) / 2 for a, b in zip(xs, xs[1:]))


# --- Raised deck -------------------------------------------------------------------------------

def build_deck(bm):
    x0, x1 = DECK_X
    z0, z1 = DECK_Z
    y = DECK_Y
    # Grating and the beams under it, columns to the mill floor.
    gbox(bm, x0, x1, y - 0.03, y, z0, z1, M["dark"])
    for z in [z0 + 0.1] + [z0 + 1.5 * k for k in range(1, int((z1 - z0) / 1.5) + 1)] + [z1 - 0.1]:
        z = min(z, z1 - 0.1)
        gbox(bm, x0, x1, y - 0.25, y - 0.03, z - 0.05, z + 0.05, M["frame"])
    for x in (x0 + 0.1, (x0 + x1) / 2, x1 - 0.1):
        gbox(bm, x - 0.05, x + 0.05, y - 0.25, y - 0.03, z0, z1, M["frame"])
    for x in (x0 + 0.1, x0 + (x1 - x0) / 3, x0 + 2 * (x1 - x0) / 3, x1 - 0.1):
        for z in (z0 + 0.15, (z0 + z1) / 2, z1 - 0.15):
            gbox(bm, x - 0.08, x + 0.08, FLOOR, y - 0.25, z - 0.08, z + 0.08, M["frame"])
            gbox(bm, x - 0.15, x + 0.15, FLOOR, FLOOR + 0.02, z - 0.15, z + 0.15, M["dark"])
    # Kick plate along the edge over the unscrambler.
    gbox(bm, x0, x1, y, y + 0.15, z0, z0 + 0.01, M["moving"])
    # Handrails: the -X side (with a gap for the stairs) and the +Z end.
    stair_z = (20.0, 20.9)
    def rail(xa, za, xb, zb):
        for h in (0.55, 1.07):
            beam(bm, (xa, y + h, za), (xb, y + h, zb), 0.04, 0.04, M["moving"])
        n = max(1, int(math.hypot(xb - xa, zb - za) / 1.6))
        for k in range(n + 1):
            px, pz = xa + (xb - xa) * k / n, za + (zb - za) * k / n
            gbox(bm, px - 0.02, px + 0.02, y, y + 1.07, pz - 0.02, pz + 0.02, M["moving"])
    rail(x0 + 0.03, z0 + 0.05, x0 + 0.03, stair_z[0])
    rail(x0 + 0.03, stair_z[1], x0 + 0.03, z1 - 0.03)
    rail(x0 + 0.03, z1 - 0.03, x1 - 0.03, z1 - 0.03)
    # Stairs down off the -X side to the mill floor.
    steps = 7
    run = 0.27
    for k in range(steps):
        sy = y - (k + 1) * (y - FLOOR) / (steps + 1)
        sx = x0 - (k + 1) * run
        gbox(bm, sx - 0.0, sx + run, sy - 0.03, sy, stair_z[0], stair_z[1], M["dark"])
    for z in stair_z:
        beam(bm, (x0, y, z), (x0 - (steps + 1) * run, FLOOR, z), 0.04, 0.2, M["frame"])
        beam(bm, (x0, y + 0.9, z), (x0 - (steps + 1) * run, FLOOR + 0.9, z), 0.04, 0.04, M["moving"])


# --- Chain modules ----------------------------------------------------------------------------

def chain_frame(bm, xs, z0, z1, r, lugged=False, ytop=CHAIN_Y):
    """Stringers and wear strips under each chain, cross beams and legs to the deck, shaft bearings."""
    for x in xs:
        gbox(bm, x - 0.02, x + 0.02, ytop - 0.03, ytop - 0.012, z0 + r, z1 - r, M["wear"])
        gbox(bm, x - 0.03, x + 0.03, ytop - 2 * r + 0.03, ytop - 0.03, z0 + r, z1 - r, M["frame"])
    xa, xb = min(xs) - 0.15, max(xs) + 0.1
    beam_top = ytop - 2 * r - 0.03 - (0.08 if lugged else 0.0)
    n = max(2, int((z1 - z0) / 1.6) + 1)
    for k in range(n):
        z = z0 + r + 0.15 + (z1 - z0 - 2 * r - 0.3) * k / (n - 1)
        gbox(bm, xa, xb, beam_top - 0.1, beam_top, z - 0.04, z + 0.04, M["frame"])
        for x in xs:
            gbox(bm, x + 0.035, x + 0.055, beam_top, ytop - 0.03, z - 0.02, z + 0.02, M["frame"])
        for x in (xa + 0.05, (xa + xb) / 2, xb - 0.05):
            gbox(bm, x - 0.04, x + 0.04, DECK_Y, beam_top - 0.1, z - 0.04, z + 0.04, M["frame"])
    cy = ytop - r
    for z in (z0, z1):
        for x in (xa, xb):
            gbox(bm, x - 0.04, x + 0.04, cy - 0.05, cy + 0.05, z - 0.05, z + 0.05, M["dark"])
            gbox(bm, x - 0.03, x + 0.03, DECK_Y, cy - 0.05, z - 0.03, z + 0.03, M["frame"])
    # Gearmotor on the head shaft, -X end.
    gbox(bm, xa - 0.3, xa - 0.04, cy - 0.09, cy + 0.09, z1 - 0.09, z1 + 0.09, M["motor"])
    cyl_x(bm, G(xa - 0.5, cy, z1), 0.08, 0.28, mat_index=M["motor"])
    gbox(bm, xa - 0.62, xa - 0.04, DECK_Y, cy - 0.09, z1 - 0.1, z1 + 0.1, M["frame"])


def shaft(coll, mats, name, xs, z, r, ytop=CHAIN_Y):
    cy = ytop - r
    xa, xb = min(xs) - 0.15, max(xs) + 0.1
    xm = (xa + xb) / 2
    e = empty(name, coll, None, G(xm, cy, z), 0.1)
    bm = bmesh.new()
    L.add_cyl(bm, 0.025, xb - xa, L.mat(rot=(0, 90, 0)), segs=10, mat_index=M["chrome"])
    for x in xs:
        L.add_cyl(bm, r + 0.008, 0.025, L.mat(loc=(x - xm, 0, 0), rot=(0, 90, 0)), segs=14, mat_index=M["dark"])
    H.make(name + "Mesh", bm, coll, mats, e)


# --- Lug loader extras ------------------------------------------------------------------------

def build_stop_set(coll, mats, frame_bm, name, z):
    xm = (min(LUG_X) + max(LUG_X)) / 2
    up_y = CHAIN_Y + STOP_UP
    root = empty(name, coll, None, G(xm, up_y, z), 0.1)
    bm = bmesh.new()
    o = G(xm, up_y, z)
    for x in LUG_X:
        sx = x + 2.5 * IN
        # Stop blade: front face at z, rubber facing up-line.
        gbox(bm, sx - 0.015, sx + 0.015, up_y - 0.16, up_y, z - 0.015, z + 0.015, M["moving"], o)
        gbox(bm, sx - 0.015, sx + 0.015, up_y - 0.06, up_y, z - 0.022, z - 0.015, M["rubber"], o)
        # Air cylinder body (fixed) under each blade.
        cyl_z(frame_bm, G(sx, up_y - 0.32, z), 0.023, 0.18, mat_index=M["dark"])
    H.make(name + "Mesh", bm, coll, mats, root)


def build_flipper(coll, mats, frame_bm):
    """Flipper shaft at the halfway stops: a D between each pair of lug loader chains, flat side up
    flush with the chain tops; a rotary actuator on the -X end."""
    xs = sorted(LUG_X)
    xa, xb = xs[0] - 0.12, xs[-1] + 0.08
    cy = CHAIN_Y - 0.01
    piv = G((xa + xb) / 2, cy, FLIP_Z)
    root = empty("BD_Flipper", coll, None, piv, 0.12)
    bm = bmesh.new()
    cyl_x(bm, G((xa + xb) / 2, cy - D_R * 0.55, FLIP_Z) - piv, 0.022, xb - xa, mat_index=M["chrome"])
    for a, b in zip(xs, xs[1:]):
        x = (a + b) / 2
        pts = [(FLIP_Z + D_R * math.cos(math.pi + math.pi * k / 12), cy + D_R * math.sin(math.pi + math.pi * k / 12))
               for k in range(13)]
        plate_zy(bm, x, 0.025, pts, M["moving"], piv)
    H.make("BD_FlipperMesh", bm, coll, mats, root)
    gbox(frame_bm, xa - 0.3, xa - 0.05, cy - 0.18, cy + 0.05, FLIP_Z - 0.1, FLIP_Z + 0.1, M["dark"])
    gbox(frame_bm, xa - 0.3, xa - 0.05, DECK_Y, cy - 0.18, FLIP_Z - 0.06, FLIP_Z + 0.06, M["frame"])


# --- Zero rollers, fence, scanner --------------------------------------------------------------

def build_zero_rolls(coll, mats, frame_bm):
    cy = ZERO_ROLL_TOP - ZERO_ROLL_R
    for i, x in enumerate(zero_roll_xs()):
        e = empty("BD_ZeroRoll%d" % (i + 1), coll, None, G(x, cy, ZERO_ROLL_Z), 0.06)
        bm = bmesh.new()
        # Axis along Z (Blender Y): the roll turns to drive the board along +X.
        L.add_cyl(bm, ZERO_ROLL_R, 12 * IN, L.mat(rot=(90, 0, 0)), segs=18, mat_index=M["chrome"])
        L.add_cyl(bm, 0.012, 16 * IN, L.mat(rot=(90, 0, 0)), segs=8, mat_index=M["dark"])
        H.make("BD_ZeroRoll%dMesh" % (i + 1), bm, coll, mats, e)
        for s in (-1, 1):
            gbox(frame_bm, x - 0.035, x + 0.035, DECK_Y, cy + 0.01, ZERO_ROLL_Z + s * 7 * IN - 0.01,
                 ZERO_ROLL_Z + s * 7 * IN + 0.01, M["frame"])
        # Hydraulic motor on the +Z bearing.
        gbox(frame_bm, x - 0.04, x + 0.04, cy - 0.08, cy + 0.02, ZERO_ROLL_Z + 8 * IN, ZERO_ROLL_Z + 14 * IN, M["dark"])


def build_fence(bm):
    """Zero line fence the board ends are driven against, from the lug loader to the infeed."""
    z0, z1 = SCAN_Z[0] + 0.1, SCAN_Z[1] - 0.1
    gbox(bm, FENCE_X, FENCE_X + 0.02, SCAN_Y - 0.02, SCAN_Y + 0.12, z0, z1, M["wear"])
    for k in range(5):
        z = z0 + (z1 - z0) * k / 4
        gbox(bm, FENCE_X + 0.02, FENCE_X + 0.07, DECK_Y, SCAN_Y + 0.12, z - 0.03, z + 0.03, M["frame"])


def build_scanner(bm):
    z = SCANNER_Z
    xa, xb = B.X_ZERO - 290 * IN, B.X_ZERO + 6 * IN
    y0 = DECK_Y
    for x in (xa, xb):
        for s in (-1, 1):
            gbox(bm, x - 0.05, x + 0.05, y0, y0 + 66 * IN, z + s * 12 * IN - 0.05, z + s * 12 * IN + 0.05, M["mill"])
        gbox(bm, x - 0.05, x + 0.05, y0 + 62 * IN, y0 + 66 * IN, z - 14 * IN, z + 14 * IN, M["mill"])
    gbox(bm, xa, xb, y0 + 60 * IN, y0 + 66 * IN, z - 5 * IN, z + 5 * IN, M["mill"])
    gbox(bm, xa, xb, y0 + 22 * IN, y0 + 27 * IN, z - 5 * IN, z + 5 * IN, M["mill"])
    n = int((xb - xa - 12 * IN) / (14.5 * IN)) + 1
    for k in range(n):
        x = xa + 6 * IN + 14.5 * IN * k
        gbox(bm, x - 3 * IN, x + 3 * IN, y0 + 53 * IN, y0 + 60 * IN, z - 4 * IN, z + 4 * IN, M["motor"])
        # Laser window on the underside of each top head.
        gbox(bm, x - 2 * IN, x + 2 * IN, y0 + 52.8 * IN, y0 + 53 * IN, z - 0.5 * IN, z + 0.5 * IN, M["red"])
        if all(abs(x - cx) > 4 * IN for cx in SCAN_X):
            gbox(bm, x - 3 * IN, x + 3 * IN, y0 + 27 * IN, y0 + 33 * IN, z - 4 * IN, z + 4 * IN, M["motor"])
    cyl_x(bm, G((xa + xb) / 2, y0 + 72 * IN, z), 6 * IN, xb - xa, mat_index=M["wear"])


def scan_lug(coll, mats):
    e = empty("BD_ScanLug", coll, None, (0, 0, 0), 0.04)
    bm = bmesh.new()
    # Godot local: across X, out of the loop +Y (Blender Z), travel -Z (Blender +Y).
    L.add_box(bm, (0.035, 0.019, SCAN_LUG_H + 0.012), Matrix.Translation((0, 0, (SCAN_LUG_H - 0.012) / 2)), M["moving"])
    H.make("BD_ScanLugMesh", bm, coll, mats, e)


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("BD_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_deck(bm)
    chain_frame(bm, LUG_X, LUG_A_Z[0], LUG_A_Z[1], LUG_R)
    chain_frame(bm, LUG_B_X, LUG_B_Z[0], LUG_B_Z[1], LUG_R)
    chain_frame(bm, SCAN_X, SCAN_Z[0], SCAN_Z[1], SCAN_R, lugged=True, ytop=SCAN_Y)
    # Dead plates across the gaps: take-away to lug loader, lug loader to scanner chains.
    gbox(bm, min(LUG_X) - 0.1, max(LUG_X) + 0.1, DEAD_IN_Y - 0.009, DEAD_IN_Y, B.TAKE_ZS[1], LUG_Z[0], M["wear"])
    gbox(bm, min(SCAN_X) - 0.1, max(SCAN_X) + 0.1, DEAD_OUT_Y - 0.009, DEAD_OUT_Y, LUG_Z[1], SCAN_Z[0], M["wear"])
    build_fence(bm)
    build_scanner(bm)
    build_stop_set(coll, mats, bm, "BD_StopsHalf", STOP_HALF_Z)
    build_stop_set(coll, mats, bm, "BD_StopsEnd", STOP_END_Z)
    build_flipper(coll, mats, bm)
    build_zero_rolls(coll, mats, bm)
    H.make("BD_FrameMesh", bm, coll, mats, frame)
    shaft(coll, mats, "BD_LugTail", LUG_X, LUG_A_Z[0], LUG_R)
    shaft(coll, mats, "BD_LugMidA", LUG_X, LUG_A_Z[1], LUG_R)
    shaft(coll, mats, "BD_LugMidB", LUG_B_X, LUG_B_Z[0], LUG_R)
    shaft(coll, mats, "BD_LugHead", LUG_B_X, LUG_B_Z[1], LUG_R)
    shaft(coll, mats, "BD_ScanTail", SCAN_X, SCAN_Z[0], SCAN_R, SCAN_Y)
    shaft(coll, mats, "BD_ScanHead", SCAN_X, SCAN_Z[1], SCAN_R, SCAN_Y)
    scan_lug(coll, mats)
    return {"objects": len(coll.all_objects), "lug_x": [round(x, 4) for x in LUG_X], "lug_a_z": LUG_A_Z,
            "lug_b_z": LUG_B_Z, "fence_x": FENCE_X, "flip_y": CHAIN_Y - 0.01, "scan_x": [round(x, 4) for x in SCAN_X],
            "lug_z": LUG_Z, "scan_z": SCAN_Z, "stops": (STOP_HALF_Z, STOP_END_Z), "flip_z": FLIP_Z,
            "zero_z": ZERO_ROLL_Z, "zero_x": [round(x, 4) for x in zero_roll_xs()], "chain_y": CHAIN_Y, "scan_y": SCAN_Y, "zero_top": ZERO_ROLL_TOP,
            "deck_y": DECK_Y, "scanner_z": SCANNER_Z, "deck_z": DECK_Z}
