"""Board line, part 1: feed chains, pocket, unscrambler and take-away chains (run inside Blender).

Fits the USNR job 3338 transfer (dev/blender/line_3338, project notes) into the mill at true size.
Boards cross the line toward +Z; the lineal infeed (edger line) is at z = Z_LINE and the board lead
ends (zero lumber line) at x = X_ZERO, so a drawing Ye (inches from the infeed centre line) sits at
mill z = Z_LINE - Ye * IN.
  - feed chains: five strands, level at the board transfer height from the headrig outfeed's board
    kickers (and under the gang's lift rolls), a short slope down at the end into the pocket
  - pocket: a steep back plate from the feed chain head down to the unscrambler foot
  - unscrambler: five pairs of 81XH bar chain up a 40 deg incline and over the 6 ft radius to the
    raised deck, carrier bars with two lugs across each pair every 30 in, deck plate and UHMW
    chainways, 25 hp drive on the head shaft from a stand on the floor
  - take-away (speed-up) chains: six short strands at the deck height spacing the boards out

Built in mill coordinates like the headrig: Godot (x, y, z) = Blender (x, -z, y + 1.288), H.G().
The chains themselves (links and carrier bars) are instanced by the game along the same loops.

  BL_Frame                          all fixed steel
  BL_FeedTail / BL_FeedHead         feed chain shafts (spin about X)
  BL_UnsFoot / BL_UnsHead           unscrambler shafts (spin about X)
  BL_TakeTail / BL_TakeHead         take-away shafts (spin about X)
  BL_Carrier                        one carrier bar with its two lugs, for instancing: bar along
                                    local X, lugs out of the loop (+Y), travel along local -Z
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

COLL = "BoardLine"
IN = 0.0254
Z_LINE = 21.6
X_ZERO = 43.5
RAISED_Y = FLOOR + 51.625 * IN          # top of the raised steel deck
LL_Y = RAISED_Y + 44.0 * IN             # lumber line (top of chain) on the deck


def zye(ye):
    return Z_LINE - ye * IN


def yin(z_in):
    """Height of a drawing z (inches above the raised floor) in the mill."""
    return RAISED_Y + z_in * IN


# Feed chains (not on the drawings; level with the headrig outfeed's board transfer).
FEED_X = (38.5, 39.5, 40.5, 41.5, 42.5, 43.0)  # between the gang's lift rolls; 43.0 so a 6 ft board even-ended at the zero line lies on two
FEED_TOP_Y = -0.2
FEED_Z0 = 6.25                                  # tail sprocket
FEED_LEVEL_END = zye(484.0)                     # level run ends, 10 in short of the head
FEED_Z1 = zye(474.0)                            # head, over the pocket
FEED_DROP = 6.0 * IN
FEED_R = 0.09
# Unscrambler.
UNS_PAIRS = tuple((X_ZERO - a * IN, X_ZERO - b * IN) for a, b in ((25, 47), (62, 84), (99, 125), (140, 166),
                                                                    (181, 207)))
UNS_TOP_YE, UNS_R_IN, UNS_ANGLE = 322.0, 72.0, 40.0
UNS_SPROCKET_R = 5.0 * IN
CARRIER_PITCH = 30.0 * IN
LUG_TOP = 0.05                                  # lug tip above the chain tops
POCKET_X = (37.95, X_ZERO + 0.3)                # wider than the longest board, lead ends at the zero line
# Double reject: arms over the incline sweep down-slope just clear of the lug tips.
REJECT_S = 1.9                                  # station, along the incline from the foot
REJECT_PIVOT_N = 0.95                           # shaft height off the chain line
REJECT_ARMS_X = (39.3, 40.5, 41.7, 42.9)
# Take-away chains.
TAKE_X = tuple(X_ZERO - d * IN for d in (20.75, 51.25, 88.25, 129.25, 170.25, 211.25))
# The head runs on over the lug loader's tail (bd_build LUG_Z[0], Ye 292 in), the two sets of chains
# interleaved, so a board is still carried by the take-away until it lies on the lug chains: a dead
# plate here was narrower than a board and boards stalled on it once off the take-away.
TAKE_ZS = (zye(313.5), zye(284.0))
TAKE_R = 3.0 * IN
TAKE_FRAME_END = zye(294.0)                     # stringers stop short of the lug loader's tail shaft
TAKE_HEAD_XB = 43.36                            # head bearing outboard of the outer lug chain (x 43.17)


def unscrambler_path():
    """Carrying run (chain top) as (z, y): foot, up the incline, over the radius, short level top."""
    zc = 44.0 - 0.9
    a = math.radians(UNS_ANGLE)
    c = Vector((UNS_TOP_YE, zc - UNS_R_IN))
    top = [c + Vector((math.cos(t), math.sin(t))) * UNS_R_IN
           for t in [math.pi / 2 - a + a * k / 12 for k in range(13)]]
    foot_z = -51.625 + 15.75
    run = (top[0].y - foot_z) / math.sin(a)
    foot = top[0] + Vector((math.cos(a), -math.sin(a))) * run
    pts = [foot] + top + [Vector((UNS_TOP_YE - 2.0, zc))]
    return [(zye(p.x), yin(p.y)) for p in pts]


def feed_path():
    return [(FEED_Z0, FEED_TOP_Y), (FEED_LEVEL_END, FEED_TOP_Y), (FEED_Z1, FEED_TOP_Y - FEED_DROP)]


def offset(path, d):
    """Offset a (z, y) polyline by d toward the outside of the loop (up on a run travelling +Z)."""
    out = []
    for i, p in enumerate(path):
        a = Vector(path[max(i - 1, 0)])
        b = Vector(path[min(i + 1, len(path) - 1)])
        t = (b - a).normalized()
        n = Vector((-t.y, t.x))
        out.append(tuple(Vector(p) + n * d))
    return out


def sprocket_centres(path, r):
    def nrm(a, b):
        t = (Vector(b) - Vector(a)).normalized()
        return Vector((-t.y, t.x))
    return tuple(Vector(path[0]) - nrm(path[0], path[1]) * r), tuple(Vector(path[-1]) - nrm(path[-2], path[-1]) * r)


def legs_to_floor(bm, x, z, top, w=0.08):
    gbox(bm, x - w / 2, x + w / 2, FLOOR, top, z - w / 2, z + w / 2, M["frame"])
    gbox(bm, x - w, x + w, FLOOR, FLOOR + 0.015, z - w, z + w, M["dark"])


def zy_prism(bm, pts, x0, x1, mat):
    """Polygon in the (z, y) plane extruded from x0 to x1."""
    plate_zy(bm, (x0 + x1) / 2, x1 - x0, pts, mat)


# --- Feed chains and pocket -------------------------------------------------------------------

def build_feed(bm):
    path = feed_path()
    c0, c1 = sprocket_centres(path, FEED_R)
    for x in FEED_X:
        # Stringer and UHMW wear strip under the carrying run, along the level part and the slope.
        for i in range(len(path) - 1):
            (za, ya), (zb, yb) = path[i], path[i + 1]
            za2 = za + (0.12 if i == 0 else 0.0)
            zb2 = zb - (0.12 if i == len(path) - 2 else 0.0)
            beam(bm, (x, ya - 0.03, za2), (x, yb - 0.03, zb2), 0.05, 0.03, M["wear"])
            beam(bm, (x, ya - 0.13, za2), (x, yb - 0.13, zb2), 0.06, 0.16, M["frame"])
    xa, xb = FEED_X[0] - 0.2, FEED_X[-1] + 0.2
    for (cz, cy) in (c0, c1):
        for x in (xa, xb):
            gbox(bm, x - 0.06, x + 0.06, cy - 0.07, cy + 0.07, cz - 0.07, cz + 0.07, M["dark"])
            legs_to_floor(bm, x, cz, cy - 0.07, 0.07)
    for z in (FEED_Z0 + 1.0, (FEED_Z0 + FEED_LEVEL_END) / 2 + 0.4, FEED_LEVEL_END - 0.4):
        gbox(bm, xa, xb, FEED_TOP_Y - 0.38, FEED_TOP_Y - 0.3, z - 0.04, z + 0.04, M["frame"])
        for x in (xa + 0.05, (xa + xb) / 2, xb - 0.05):
            legs_to_floor(bm, x, z, FEED_TOP_Y - 0.38, 0.07)
    # Gearmotor on the tail shaft end (-X side).
    cz, cy = c0
    gbox(bm, xa - 0.35, xa - 0.08, cy - 0.12, cy + 0.12, cz - 0.12, cz + 0.12, M["motor"])
    cyl_x(bm, G(xa - 0.6, cy, cz), 0.11, 0.35, mat_index=M["motor"])
    gbox(bm, xa - 0.75, xa - 0.08, FLOOR, cy - 0.12, cz - 0.15, cz + 0.15, M["frame"])


def pocket_plate():
    """Back plate (z, y) ends: from just under the feed chain head down to the V at the unscrambler
    foot, where the lugs come round the foot sprocket under the boards."""
    # Top edge a little under the end of the feed chains' slope so boards step down onto it; the
    # foot of the plate stops just outside the circle the lug tips sweep round the foot sprocket.
    fz, fy = sprocket_centres(unscrambler_path(), UNS_SPROCKET_R)[0]
    u = Vector((-0.946, -0.323))
    r = UNS_SPROCKET_R + LUG_TOP + 0.013
    return (zye(473.2), FEED_TOP_Y - FEED_DROP - 0.048), (fz + u.x * r, fy + u.y * r)


def finger_tip():
    """End of a comb finger, just off the chain wrap round the foot sprocket, toward the plate."""
    fz, fy = sprocket_centres(unscrambler_path(), UNS_SPROCKET_R)[0]
    r = UNS_SPROCKET_R + 0.018
    return (fz - 0.946 * r, fy - 0.323 * r)


def finger_spans():
    """x spans of the comb fingers: everywhere across the pocket except a slot round each chain pair."""
    slots = sorted((min(p) - 0.04, max(p) + 0.04) for p in UNS_PAIRS)
    spans, x = [], POCKET_X[0]
    for a, b in slots:
        spans.append((x, a))
        x = b
    spans.append((x, POCKET_X[1]))
    return spans


def build_pocket(bm):
    """Back plate from the feed chain head down to the unscrambler foot, and the pocket cheeks."""
    uns = unscrambler_path()
    fz, fy = uns[0]
    xa, xb = POCKET_X
    top, low = pocket_plate()
    zy_prism(bm, [top, low, (low[0] - 0.012, low[1]), (top[0] - 0.012, top[1])], xa, xb, M["wear"])
    # Comb fingers between the chain pairs reach in to the chain wrap, so no board can drop
    # through; the lugs come round in the slots between them.
    for f0, f1 in finger_spans():
        tip = finger_tip()
        zy_prism(bm, [low, tip, (tip[0] - 0.01, tip[1] - 0.012), (low[0] - 0.01, low[1] - 0.012)], f0, f1, M["wear"])
    # Ribs and posts behind the plate.
    for x in (xa + 0.1, (xa + xb) / 2, xb - 0.1):
        zy_prism(bm, [(top[0] - 0.012, top[1]), (low[0] - 0.012, low[1]), (low[0] - 0.012, FLOOR),
                      (top[0] - 0.012, FLOOR)], x - 0.02, x + 0.02, M["frame"])
    # End cheeks so boards can't slide out of the pocket lengthwise.
    for x in (xa - 0.01, xb + 0.01):
        zy_prism(bm, [(top[0], top[1] + 0.25), (low[0], FLOOR), (fz + 0.35, FLOOR), (fz + 0.35, fy + 0.6)], x - 0.008,
                 x + 0.008, M["frame"])


# --- Unscrambler ------------------------------------------------------------------------------

def build_unscrambler(bm):
    path = unscrambler_path()
    foot, head = sprocket_centres(path, UNS_SPROCKET_R)
    xs = [x for p in UNS_PAIRS for x in p]
    xa, xb = min(xs) - 0.2, max(xs) + 0.2
    # Deck plate under the carrying run and UHMW chainways under each chain.
    under = [p for p in path]
    for x in xs:
        _strip(bm, under, -0.02, -0.04, x - 0.03, x + 0.03, M["wear"])
    _strip(bm, under, -0.045, -0.06, xa, xb, M["frame"])
    # Side stringers (deep plates following the run) on each side.
    for x in (xa - 0.01, xb + 0.01):
        _strip(bm, under, 0.02, -0.3, x - 0.007, x + 0.007, M["frame"])
    # Legs under the incline and the radius, cross beams.
    low = offset(path, -0.3)
    for i in (2, 5, 8, 11):
        z, y = low[i]
        gbox(bm, xa - 0.05, xb + 0.05, y - 0.1, y, z - 0.05, z + 0.05, M["frame"])
        for x in (xa - 0.02, (xa + xb) / 2, xb + 0.02):
            legs_to_floor(bm, x, z, y - 0.1, 0.08)
    # Shafts' bearings and stands; the head (top) shaft carries the drive.
    for (cz, cy), stand in ((foot, True), (head, True)):
        for x in (xa - 0.08, xb + 0.08):
            gbox(bm, x - 0.05, x + 0.05, cy - 0.07, cy + 0.07, cz - 0.07, cz + 0.07, M["dark"])
            legs_to_floor(bm, x, cz, cy - 0.07, 0.07)
    hz, hy = head
    # 25 hp gearmotor on its own stand off the -X end of the head shaft.
    gbox(bm, xa - 1.15, xa - 0.5, FLOOR, hy - 0.17, hz - 0.25, hz + 0.25, M["frame"])
    gbox(bm, xa - 0.75, xa - 0.4, hy - 0.17, hy + 0.17, hz - 0.17, hz + 0.17, M["motor"])
    cyl_x(bm, G(xa - 1.0, hy, hz), 0.16, 0.5, mat_index=M["motor"])
    cyl_x(bm, G(xa - 0.25, hy, hz), 0.035, 0.35, mat_index=M["chrome"])


def _strip(bm, path, d0, d1, x0, x1, mat):
    top, bot = offset(path, d0), offset(path, d1)
    for i in range(len(path) - 1):
        zy_prism(bm, [top[i], top[i + 1], bot[i + 1], bot[i]], x0, x1, mat)


# --- Double reject kicker -----------------------------------------------------------------------

def incline_frame():
    """Foot point, unit up-slope and unit normal (z, y) of the straight part of the incline."""
    path = unscrambler_path()
    a, b = Vector(path[0]), Vector(path[1])
    t = (b - a).normalized()
    return a, t, Vector((-t.y, t.x))


def reject_pivot():
    a, t, n = incline_frame()
    s = a + t * REJECT_S
    return tuple(s + n * REJECT_PIVOT_N)


def build_reject_frame(bm):
    """Bridge over the incline carrying the reject arm shaft, its air cylinder, and the photo eye."""
    pz, py = reject_pivot()
    a, t, n = incline_frame()
    xa, xb = POCKET_X[0] - 0.05, POCKET_X[1] + 0.05
    for x in (xa, xb):
        gbox(bm, x - 0.06, x + 0.06, FLOOR, py + 0.12, pz - 0.06, pz + 0.06, M["frame"])
        gbox(bm, x - 0.08, x + 0.08, py - 0.08, py + 0.08, pz - 0.08, pz + 0.08, M["dark"])
    gbox(bm, xa, xb, py + 0.12, py + 0.22, pz - 0.05, pz + 0.05, M["frame"])
    # Air cylinder from the bridge beam to a crank on the shaft's +X end.
    cyl_y(bm, G(xb - 0.25, py + 0.32, pz + 0.15), 0.05, 0.42, mat_index=M["dark"])
    # Photo eye: emitter and receiver on short posts beside the chains, just over a lug's height.
    eye = Vector((a.x, a.y)) + t * REJECT_S + n * (LUG_TOP + 0.012)
    for x, mat in ((xa - 0.04, M["red"]), (xb + 0.04, M["dark"])):
        gbox(bm, x - 0.03, x + 0.03, FLOOR, eye.y - 0.04, eye.x - 0.03, eye.x + 0.03, M["frame"])
        gbox(bm, x - 0.04, x + 0.04, eye.y - 0.04, eye.y + 0.04, eye.x - 0.04, eye.x + 0.04, mat)


def build_reject_arm(coll, mats):
    """Shaft and arms; modelled hanging at bottom dead centre, tip just clear of the lug tips."""
    pz, py = reject_pivot()
    a, t, n = incline_frame()
    xa, xb = POCKET_X[0] - 0.05, POCKET_X[1] + 0.05
    piv = G((xa + xb) / 2, py, pz)
    root = empty("BL_Reject", coll, None, piv, 0.15)
    bm = bmesh.new()
    cyl_x(bm, G((xa + xb) / 2, py, pz) - piv, 0.04, xb - xa + 0.1, mat_index=M["chrome"])
    arm = REJECT_PIVOT_N - LUG_TOP - 0.012
    tip = (pz - n.x * arm, py - n.y * arm)
    for x in REJECT_ARMS_X:
        beam(bm, (x, py, pz), (x, tip[1], tip[0]), 0.05, 0.03, M["moving"], piv)
        # Rubber pad on the tip that meets the board.
        beam(bm, (x - 0.12, tip[1], tip[0]), (x + 0.12, tip[1], tip[0]), 0.03, 0.035, M["rubber"], piv)
        cyl_x(bm, G(x, py, pz) - piv, 0.07, 0.08, mat_index=M["moving"])
    # Crank for the cylinder rod on the +X end.
    beam(bm, (xb - 0.25, py, pz), (xb - 0.25, py + 0.2, pz + 0.12), 0.04, 0.04, M["moving"], piv)
    H.make("BL_RejectMesh", bm, coll, mats, root)
    return root


# --- Take-away chains -------------------------------------------------------------------------

TAKE_Y = 1.114                                  # a few mm under the unscrambler's top run
TOP_DEAD_Y = 1.116                              # dead plate between the two


def take_path():
    y = TAKE_Y
    return [(TAKE_ZS[0], y), (TAKE_ZS[1], y)]


def build_takeaway(bm):
    path = take_path()
    c0, c1 = sprocket_centres(path, TAKE_R)
    xa, xb = min(TAKE_X) - 0.15, max(TAKE_X) + 0.15
    for x in TAKE_X:
        gbox(bm, x - 0.025, x + 0.025, path[0][1] - 0.03, path[0][1] - 0.01, TAKE_ZS[0] + 0.05, TAKE_FRAME_END,
             M["wear"])
        gbox(bm, x - 0.03, x + 0.03, path[0][1] - 0.12, path[0][1] - 0.03, TAKE_ZS[0] + 0.05, TAKE_FRAME_END,
             M["frame"])
    for (cz, cy), bx in ((c0, xb), (c1, TAKE_HEAD_XB)):
        for x in (xa, bx):
            gbox(bm, x - 0.05, x + 0.05, cy - 0.06, cy + 0.06, cz - 0.06, cz + 0.06, M["dark"])
    # Dead plate from the unscrambler's top run across to the take-away chains.
    gbox(bm, xa, xb, TOP_DEAD_Y - 0.009, TOP_DEAD_Y, unscrambler_path()[-1][0], TAKE_ZS[0], M["wear"])
    zc = (TAKE_ZS[0] + TAKE_ZS[1]) / 2
    gbox(bm, xa, xb, path[0][1] - 0.22, path[0][1] - 0.14, zc - 0.05, zc + 0.05, M["frame"])
    for x in (xa, (xa + xb) / 2, xb):
        legs_to_floor(bm, x, zc, path[0][1] - 0.22, 0.09)
    cz, cy = c0
    gbox(bm, xa - 0.35, xa - 0.06, cy - 0.1, cy + 0.1, cz - 0.1, cz + 0.1, M["motor"])
    cyl_x(bm, G(xa - 0.55, cy, cz), 0.09, 0.3, mat_index=M["motor"])
    gbox(bm, xa - 0.7, xa - 0.06, FLOOR, cy - 0.1, cz - 0.12, cz + 0.12, M["frame"])


# --- Moving parts -----------------------------------------------------------------------------

def shaft(coll, mats, name, centre, xs, r, width=0.03, xb=None):
    cz, cy = centre
    xa, xb = min(xs) - 0.12, (xb if xb is not None else max(xs) + 0.12)
    xm = (xa + xb) / 2
    e = empty(name, coll, None, G(xm, cy, cz), 0.1)
    bm = bmesh.new()
    L.add_cyl(bm, 0.035, xb - xa + 0.1, L.mat(rot=(0, 90, 0)), segs=12, mat_index=M["chrome"])
    for x in xs:
        L.add_cyl(bm, r + 0.012, width, L.mat(loc=(x - xm, 0, 0), rot=(0, 90, 0)), segs=14, mat_index=M["dark"])
        for k in range(10):
            L.add_box(bm, (width * 1.2, 0.02, 0.025), L.mat(rot=(k * 36, 0, 0)) @
                      Matrix.Translation((x - xm, 0, r + 0.01)), M["dark"])
    H.make(name + "Mesh", bm, coll, mats, e)
    return e


def carrier(coll, mats):
    """One carrier bar across a chain pair with its two lugs (pair gauge from the drawings)."""
    a, b = UNS_PAIRS[0]
    span = abs(a - b)
    e = empty("BL_Carrier", coll, None, (0, 0, 0), 0.05)
    bm = bmesh.new()
    # Godot local: bar along X, lugs out of the loop along +Y; Blender Y = -Godot Z, Z = Godot Y.
    # The bar rides just under the chain tops; the lugs stand one 2x board (and a bit) proud.
    L.add_box(bm, (span + 0.06, 0.025, 0.025), Matrix.Translation((0, 0, -0.012)), M["dark"])
    for s in (-1, 1):
        L.add_box(bm, (0.05, 0.025, LUG_TOP + 0.025), Matrix.Translation((s * (span / 2 - 0.05), 0,
                                                                          (LUG_TOP - 0.025) / 2)), M["moving"])
    H.make("BL_CarrierMesh", bm, coll, mats, e)
    return e


ROLLER_PITCH = 2.609 * IN                      # 81X roller chain


def roller_link(coll, mats):
    """One pitch of the board line's roller chain, for instancing round every chain loop: side
    plates either side, a roller and pin; the plate tops are at the origin (the chain-top line the
    boards ride on), local X across the chain, Y out of the loop, travel along -Z."""
    e = empty("BL_RollerLink", coll, None, (0, 0, 0), 0.03)
    bm = bmesh.new()
    p = ROLLER_PITCH
    h = 0.03
    for s in (-1, 1):
        # Plates alternate inner/outer pitch to pitch: draw one inner and one outer pair per pitch.
        L.add_box(bm, (0.004, p * 0.98, h), Matrix.Translation((s * 0.012, 0, -h / 2)), M["dark"])
        L.add_box(bm, (0.004, p * 0.98, h * 0.94), Matrix.Translation((s * 0.017, p / 2, -h / 2)), M["dark"])
    L.add_cyl(bm, 0.011, 0.02, L.mat(loc=(0, p / 2, -h / 2), rot=(0, 90, 0)), segs=10, mat_index=M["wear"])
    L.add_cyl(bm, 0.0045, 0.042, L.mat(loc=(0, p / 2, -h / 2), rot=(0, 90, 0)), segs=8, mat_index=M["chrome"])
    H.make("BL_RollerLinkMesh", bm, coll, mats, e)
    return e


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("BL_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_feed(bm)
    build_pocket(bm)
    build_unscrambler(bm)
    build_takeaway(bm)
    build_reject_frame(bm)
    H.make("BL_FrameMesh", bm, coll, mats, frame)
    build_reject_arm(coll, mats)
    fc0, fc1 = sprocket_centres(feed_path(), FEED_R)
    shaft(coll, mats, "BL_FeedTail", fc0, FEED_X, FEED_R)
    shaft(coll, mats, "BL_FeedHead", fc1, FEED_X, FEED_R)
    uf, uh = sprocket_centres(unscrambler_path(), UNS_SPROCKET_R)
    xs = [x for p in UNS_PAIRS for x in p]
    shaft(coll, mats, "BL_UnsFoot", uf, xs, UNS_SPROCKET_R, 0.04)
    shaft(coll, mats, "BL_UnsHead", uh, xs, UNS_SPROCKET_R, 0.04)
    tc0, tc1 = sprocket_centres(take_path(), TAKE_R)
    shaft(coll, mats, "BL_TakeTail", tc0, TAKE_X, TAKE_R)
    shaft(coll, mats, "BL_TakeHead", tc1, TAKE_X, TAKE_R, xb=TAKE_HEAD_XB)
    carrier(coll, mats)
    roller_link(coll, mats)
    return {"objects": len(coll.all_objects), "uns_path": [tuple(round(v, 3) for v in p) for p in unscrambler_path()],
            "feed": feed_path(), "take": take_path(), "uns_foot": uf, "uns_head": uh, "ll_y": LL_Y}
