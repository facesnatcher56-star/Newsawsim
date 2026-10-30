"""Board line, part 3: positioners, lineal infeed, 4TA36 edger and picker belt (run inside Blender).

USNR job 3338 (line_3338, edger_4ta36 and the project notes), placed like parts 1 and 2: mill
z = Z_LINE - Ye * IN, drawing X (edger feed, inches, 0 at the edger infeed) at mill x = X0 + X * IN.
  - deck extension under the infeed, edger and picker belt
  - positioning skids from the scanner chain heads to the parking ramps
  - four positioners: a carriage on a rail under each station, a pivoting head that comes up behind
    the board, pushed by a long setworks cylinder from the drive side; cushion shoes on the drive
    side clamp the board against the heads
  - parking ramps on one shaft (lowered together by a linkage and cylinder) hold the board just over
    the sharp chain while it is set; three overhead hold-down rolls press it onto the chain
  - lineal infeed: frame and race for a single sharp-top chain (links instanced by the game)
  - the 4TA36 edger (edger_4ta36/edger_build), mirrored so its drive side faces away from the transfer
  - 20 ft picker belt with two pendulum pickers, one over each side, and edging chutes down off both
    sides of the belt

  ED_Frame                    fixed steel (deck extension, skids, infeed frame, rail, picker belt frame)
  ED_Pos1..4                  positioner carriages (move along Z) > ED_PosHead1..4 (rotate about X)
  ED_Cush1..4                 cushion shoes (move along Z)
  ED_Ramps                    parking ramps on their shaft (rotate about X)
  ED_Hold1..3                 hold-down roll, yoke and rod (move along Y)
  ED_InfeedTail/Head          sharp chain sprocket shafts (spin about Z)
  ED_BeltHead/Tail            picker belt pulleys (spin about Z)
  ED_Picker1..2               pendulum pickers (rotate about X)
  ED_Edger                    the edger, mirrored (scale Y -1): its moving parts keep their names
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
for d in (os.path.join(HERE, "..", "headrig"), os.path.join(HERE, "..", "common"),
          os.path.join(HERE, "..", "edger_4ta36"), os.path.join(HERE, "..", "line_3338")):
    if d not in sys.path:
        sys.path.insert(0, d)
import hr_build as H  # noqa: E402
import mesh_lib as L  # noqa: E402
import bl_build as B  # noqa: E402
import bd_build as BD  # noqa: E402

G, gbox, beam, cyl_x, cyl_y, cyl_z, plate_zy, empty = H.G, H.gbox, H.beam, H.cyl_x, H.cyl_y, H.cyl_z, H.plate_zy, H.empty
M = H.M
FLOOR = H.FLOOR
IN = B.IN
zye = B.zye
Z_LINE = B.Z_LINE
DECK_Y = BD.DECK_Y

COLL = "BoardLineEdger"
X0 = B.X_ZERO + 7.75 * IN                       # edger infeed (drawing X = 0)


def xd(X):
    return X0 + X * IN


# Heights: each hand-off a few mm lower than the last (scanner chains 1.101).
SKID_Y = 1.098
RAMP_Y = 1.104                                   # parking ramp tops when up (board just over the chain)
RAMP_DROP_DEG = 25.0
SHARP_Y = 1.095                                  # sharp chain points
EDGER_LL = 1.090                                 # edger feed roll tops
BELT_Y = 1.086                                   # picker belt
EDGER_ORIGIN_Y = EDGER_LL - 31.0 * IN            # edger model: lumber line 30 in over its 1 in pads

SCAN_HEAD_Z = BD.SCAN_Z[1]
SKID_Z = (SCAN_HEAD_Z - 0.08, zye(14.0))
RAMP_X = tuple(xd(X) for X in (-18.0, -52.0, -95.0, -140.0, -190.0, -225.0))
RAMP_Z = (zye(16.0), zye(2.6))
RAMP_SHAFT = (zye(10.0), DECK_Y + 30.0 * IN)     # (z, y)
STATION_X = tuple(xd(X) for X in (-28.25, -75.25, -113.25, -165.25))
POS_RAIL_Z = (SCAN_HEAD_Z - 0.2, zye(-12.0))
POS_PARK_Z = SCAN_HEAD_Z - 0.12                  # head face when parked, behind a board just off the chains
HEAD_PIVOT_Y = DECK_Y + 0.42
CUSH_PARK_Z = zye(-8.0)
HOLD_X = tuple(xd(X) for X in (-24.0, -68.6, -108.0))
HOLD_ROLL_R = 4.0 * IN
HOLD_UP = 0.12
INFEED_X = (xd(-239.75), xd(-6.0))
SHARP_R = 4.0 * IN
BELT_X = (xd(112.0), xd(352.0))
BELT_HALF = 12.0 * IN
BELT_R = 4.0 * IN
PICKER_X = (xd(190.0), xd(290.0))
PICKER_PIVOT_Y = DECK_Y + 84.0 * IN
EXT_X = (BD.DECK_X[1], 53.6)
# Edging chutes off the belt end on the edging slashers (waste system), just over their chains.
CHUTE_OUT = 0.95
CHUTE_END_Y = 0.335
EXT_Z = (19.8, 24.6)


# --- Deck extension, skids, rails --------------------------------------------------------------

def build_deck(bm):
    x0, x1 = EXT_X
    z0, z1 = EXT_Z
    y = DECK_Y
    gbox(bm, x0, x1, y - 0.03, y, z0, z1, M["dark"])
    for z in (z0 + 0.1, (z0 + z1) / 2, z1 - 0.1):
        gbox(bm, x0, x1, y - 0.25, y - 0.03, z - 0.05, z + 0.05, M["frame"])
    for x in [x0 + 0.1 + k * 2.1 for k in range(int((x1 - x0) / 2.1) + 1)] + [x1 - 0.1]:
        x = min(x, x1 - 0.1)
        gbox(bm, x - 0.05, x + 0.05, y - 0.25, y - 0.03, z0, z1, M["frame"])
        for z in (z0 + 0.15, z1 - 0.15):
            gbox(bm, x - 0.08, x + 0.08, FLOOR, y - 0.25, z - 0.08, z + 0.08, M["frame"])
            gbox(bm, x - 0.15, x + 0.15, FLOOR, FLOOR + 0.02, z - 0.15, z + 0.15, M["dark"])
    # Handrails round the outer edges of the extension (the main deck has its own).
    def rail(xa, za, xb, zb):
        for h in (0.55, 1.07):
            beam(bm, (xa, y + h, za), (xb, y + h, zb), 0.04, 0.04, M["moving"])
        n = max(1, int(math.hypot(xb - xa, zb - za) / 1.6))
        for k in range(n + 1):
            px, pz = xa + (xb - xa) * k / n, za + (zb - za) * k / n
            gbox(bm, px - 0.02, px + 0.02, y, y + 1.07, pz - 0.02, pz + 0.02, M["moving"])
    # The far edging slasher's chute goes out over the far edge: no rail there.
    rail(x0, z1 - 0.03, BELT_X[0] - 0.1, z1 - 0.03)
    rail(BELT_X[1] - 0.1, z1 - 0.03, x1 - 0.03, z1 - 0.03)
    # End rail, open where boards run off the belt onto the landing table.
    rail(x1 - 0.03, z1 - 0.03, x1 - 0.03, Z_LINE + 0.6)
    rail(x1 - 0.03, Z_LINE - 0.6, x1 - 0.03, z0 + 0.03)
    rail(x0, z0 + 0.03, BELT_X[0] - 0.3, z0 + 0.03)


def build_skids(bm):
    """Wear-strip skids between the scanner chain heads, out to the parking ramps."""
    xs = sorted(BD.SCAN_X)
    for a, b in zip(xs, xs[1:]):
        x = (a + b) / 2
        gbox(bm, x - 0.02, x + 0.02, SKID_Y - 0.012, SKID_Y, SKID_Z[0], SKID_Z[1], M["wear"])
        gbox(bm, x - 0.025, x + 0.025, DECK_Y, SKID_Y - 0.012, SKID_Z[1] - 0.05, SKID_Z[1], M["frame"])
        gbox(bm, x - 0.025, x + 0.025, DECK_Y, SKID_Y - 0.012, SKID_Z[0], SKID_Z[0] + 0.05, M["frame"])


# --- Positioners, cushion shoes, ramps, hold-downs --------------------------------------------

def build_positioners(coll, mats, bm):
    for i, x in enumerate(STATION_X):
        # Rail on posts, the setworks cylinder on the drive side under the race.
        gbox(bm, x - 0.06, x + 0.06, DECK_Y + 0.38, DECK_Y + 0.43, POS_RAIL_Z[0], POS_RAIL_Z[1], M["frame"])
        for z in POS_RAIL_Z:
            gbox(bm, x - 0.05, x + 0.05, DECK_Y, DECK_Y + 0.38, z - 0.05, z + 0.05, M["frame"])
        cyl_y(bm, G(x, DECK_Y + 0.5, zye(-34.0)), 1.5 * IN, 44 * IN, mat_index=M["dark"])
        gbox(bm, x - 0.05, x + 0.05, DECK_Y, DECK_Y + 0.5, zye(-56.0) - 0.03, zye(-56.0) + 0.03, M["frame"])
        car = empty("ED_Pos%d" % (i + 1), coll, None, G(x, DECK_Y + 0.43, POS_PARK_Z), 0.08)
        cb = bmesh.new()
        o = G(x, DECK_Y + 0.43, POS_PARK_Z)
        gbox(cb, x - 0.065, x + 0.065, DECK_Y + 0.43, DECK_Y + 0.55, POS_PARK_Z - 0.12, POS_PARK_Z + 0.04, M["moving"], o)
        # Rod back to the cylinder on the drive side.
        cyl_y(cb, G(x, DECK_Y + 0.5, POS_PARK_Z + 0.55) - o, 0.5 * IN, 1.0, mat_index=M["chrome"])
        H.make("ED_Pos%dMesh" % (i + 1), cb, coll, mats, car)
        head = empty("ED_PosHead%d" % (i + 1), coll, car, G(x, HEAD_PIVOT_Y, POS_PARK_Z - 0.05), 0.06)
        hb = bmesh.new()
        ho = G(x, HEAD_PIVOT_Y, POS_PARK_Z - 0.05)
        # Arm up from the pivot to the head; its face (+Z) meets the board's back edge.
        gbox(hb, x - 0.025, x + 0.025, HEAD_PIVOT_Y, SKID_Y + 0.07, POS_PARK_Z - 0.07, POS_PARK_Z - 0.03, M["moving"], ho)
        gbox(hb, x - 0.05, x + 0.05, SKID_Y + 0.005, SKID_Y + 0.1, POS_PARK_Z - 0.06, POS_PARK_Z, M["moving"], ho)
        gbox(hb, x - 0.04, x + 0.04, SKID_Y + 0.01, SKID_Y + 0.09, POS_PARK_Z, POS_PARK_Z + 0.006, M["rubber"], ho)
        H.make("ED_PosHead%dMesh" % (i + 1), hb, coll, mats, head)
        # Cushion shoe on the drive side, its cylinder behind it.
        cyl_y(bm, G(x, SKID_Y + 0.065, CUSH_PARK_Z + 0.32), 1.6 * IN, 12 * IN, mat_index=M["dark"])
        gbox(bm, x - 0.05, x + 0.05, DECK_Y, SKID_Y + 0.02, CUSH_PARK_Z + 0.42, CUSH_PARK_Z + 0.48, M["frame"])
        shoe = empty("ED_Cush%d" % (i + 1), coll, None, G(x, SKID_Y + 0.06, CUSH_PARK_Z), 0.06)
        sb = bmesh.new()
        so = G(x, SKID_Y + 0.06, CUSH_PARK_Z)
        gbox(sb, x - 0.075, x + 0.075, SKID_Y + 0.012, SKID_Y + 0.12, CUSH_PARK_Z - 0.006, CUSH_PARK_Z + 0.03, M["moving"], so)
        gbox(sb, x - 0.065, x + 0.065, SKID_Y + 0.02, SKID_Y + 0.11, CUSH_PARK_Z - 0.012, CUSH_PARK_Z - 0.006, M["rubber"], so)
        cyl_y(sb, G(x, SKID_Y + 0.065, CUSH_PARK_Z + 0.2) - so, 0.5 * IN, 0.36, mat_index=M["chrome"])
        H.make("ED_Cush%dMesh" % (i + 1), sb, coll, mats, shoe)


def build_ramps(coll, mats, bm):
    sz, sy = RAMP_SHAFT
    xs = RAMP_X
    piv = G((min(xs) + max(xs)) / 2, sy, sz)
    root = empty("ED_Ramps", coll, None, piv, 0.1)
    rb = bmesh.new()
    cyl_x(rb, G((min(xs) + max(xs)) / 2, sy, sz) - piv, 1.1 * IN, max(xs) - min(xs) + 0.2, mat_index=M["chrome"])
    for x in xs:
        z0, z1 = RAMP_Z
        pts = [(sz - 0.02, sy - 0.03), (z0, RAMP_Y - 0.02), (z0 + 0.01, RAMP_Y), (z1, RAMP_Y - 0.004),
               (z1, RAMP_Y - 0.03), (sz + 0.03, sy - 0.02)]
        plate_zy(rb, x, 0.02, pts, M["moving"], piv)
    H.make("ED_RampsMesh", rb, coll, mats, root)
    for x in xs:
        for dx in (-0.075, 0.075):
            gbox(bm, x + dx - 0.012, x + dx + 0.012, DECK_Y, sy - 0.02, sz - 0.06, sz + 0.06, M["frame"])
    cyl_x(bm, G(min(xs) - 0.25, sy - 0.1, sz), 1.4 * IN, 0.3, mat_index=M["dark"])


def build_hold_downs(coll, mats, bm):
    for i, x in enumerate(HOLD_X):
        pz = zye(-18.0)
        gbox(bm, x - 0.05, x + 0.05, DECK_Y, DECK_Y + 1.83, pz - 0.05, pz + 0.05, M["frame"])
        gbox(bm, x - 0.05, x + 0.05, DECK_Y + 1.73, DECK_Y + 1.83, Z_LINE - 0.1, pz + 0.05, M["frame"])
        cyl_z(bm, G(x, DECK_Y + 1.57, Z_LINE), 2.5 * IN, 12 * IN, mat_index=M["dark"])
        roll_y = SHARP_Y + 0.038 + HOLD_ROLL_R + HOLD_UP
        e = empty("ED_Hold%d" % (i + 1), coll, None, G(x, roll_y, Z_LINE), 0.06)
        hb = bmesh.new()
        o = G(x, roll_y, Z_LINE)
        L.add_cyl(hb, HOLD_ROLL_R, 12 * IN, L.mat(rot=(90, 0, 0)), segs=20, mat_index=M["wear"])
        L.add_cyl(hb, 0.8 * IN, 14 * IN, L.mat(rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
        for s in (-1, 1):
            gbox(hb, x - 0.025, x + 0.025, roll_y, roll_y + 0.17, Z_LINE + s * 6.6 * IN - 0.01, Z_LINE + s * 6.6 * IN + 0.01,
                 M["moving"], o)
        gbox(hb, x - 0.025, x + 0.025, roll_y + 0.17, roll_y + 0.2, Z_LINE - 0.18, Z_LINE + 0.18, M["moving"], o)
        cyl_z(hb, G(x, roll_y + 0.4, Z_LINE) - o, 0.6 * IN, 0.4, mat_index=M["chrome"])
        H.make("ED_Hold%dMesh" % (i + 1), hb, coll, mats, e)


# --- Lineal infeed and picker belt -------------------------------------------------------------

def build_infeed(coll, mats, bm):
    x0, x1 = INFEED_X
    z = Z_LINE
    for s in (-1, 1):
        gbox(bm, x0, x1, DECK_Y + 0.6, DECK_Y + 0.76, z + s * 9 * IN - 0.006, z + s * 9 * IN + 0.006, M["frame"])
    gbox(bm, x0 + 0.15, x1 - 0.03, SHARP_Y - 0.06, SHARP_Y - 0.035, z - 0.045, z + 0.045, M["wear"])   # race
    for s in (-1, 1):
        gbox(bm, x0 + 0.15, x1 - 0.03, DECK_Y + 0.76, SHARP_Y - 0.035, z + s * 1.75 * IN - 0.004, z + s * 1.75 * IN + 0.004,
             M["frame"])
    x = x0 + 0.05
    while x < x1:
        for s in (-1, 1):
            gbox(bm, x - 0.035, x + 0.035, DECK_Y, DECK_Y + 0.6, z + s * 9 * IN - 0.035, z + s * 9 * IN + 0.035, M["frame"])
        gbox(bm, x - 0.035, x + 0.035, DECK_Y + 0.6, DECK_Y + 0.65, z - 9 * IN, z + 9 * IN, M["frame"])
        x += 1.0
    # Gearmotor at the tail end.
    gbox(bm, x0 - 0.35, x0 - 0.05, SHARP_Y - SHARP_R - 0.1, SHARP_Y - SHARP_R + 0.1, z - 0.25, z + 0.1, M["motor"])
    for name, xs in (("ED_InfeedTail", x0 + 0.2), ("ED_InfeedHead", x1 - 0.1)):
        e = empty(name, coll, None, G(xs, SHARP_Y - SHARP_R, z), 0.06)
        sb = bmesh.new()
        L.add_cyl(sb, SHARP_R + 0.01, 0.03, L.mat(rot=(90, 0, 0)), segs=14, mat_index=M["dark"])
        L.add_cyl(sb, 0.02, 0.3, L.mat(rot=(90, 0, 0)), segs=8, mat_index=M["chrome"])
        H.make(name + "Mesh", sb, coll, mats, e)


def build_picker_belt(coll, mats, bm):
    x0, x1 = BELT_X
    z = Z_LINE
    yt = BELT_Y
    # Belt (static band), side channels, slider bed, legs, drive.
    gbox(bm, x0, x1, yt - 0.006, yt, z - BELT_HALF, z + BELT_HALF, M["rubber"])
    gbox(bm, x0, x1, yt - 2 * BELT_R, yt - 2 * BELT_R + 0.006, z - BELT_HALF, z + BELT_HALF, M["rubber"])
    for s in (-1, 1):
        gbox(bm, x0 - 0.1, x1 + 0.1, yt - 0.28, yt - 0.03, z + s * 13.5 * IN - 0.006, z + s * 13.5 * IN + 0.006, M["frame"])
    xs = x0 + 0.1
    while xs < x1:
        for s in (-1, 1):
            gbox(bm, xs - 0.03, xs + 0.03, DECK_Y, yt - 0.28, z + s * 13.5 * IN - 0.03, z + s * 13.5 * IN + 0.03, M["frame"])
        xs += 1.2
    # Drive under the head end, clear of the landing table past the belt end.
    gbox(bm, x1 - 0.5, x1 - 0.1, yt - 0.62, yt - 0.33, z - 0.15, z + 0.15, M["motor"])
    for name, xp in (("ED_BeltTail", x0), ("ED_BeltHead", x1)):
        e = empty(name, coll, None, G(xp, yt - BELT_R, z), 0.06)
        pb = bmesh.new()
        L.add_cyl(pb, BELT_R - 0.004, 25 * IN, L.mat(rot=(90, 0, 0)), segs=20, mat_index=M["chrome"])
        L.add_cyl(pb, 0.025, 31 * IN, L.mat(rot=(90, 0, 0)), segs=8, mat_index=M["dark"])
        H.make(name + "Mesh", pb, coll, mats, e)
    # Edging chutes down off both sides of the belt, to the vibrating conveyors below the deck.
    for s in (-1, 1):
        ze = z + s * (BELT_HALF + 0.02)
        zo = z + s * CHUTE_OUT
        beam(bm, ((x0 + x1) / 2, yt - 0.03, ze), ((x0 + x1) / 2, CHUTE_END_Y, zo), x1 - x0 - 0.8, 0.012, M["wear"])
    # Pendulum pickers: posts each side, pivot beam overhead, an air cylinder to each arm.
    for i, xp in enumerate(PICKER_X):
        for s in (-1, 1):
            gbox(bm, xp - 0.05, xp + 0.05, DECK_Y, PICKER_PIVOT_Y + 0.12, z + s * 30 * IN - 0.05, z + s * 30 * IN + 0.05,
                 M["frame"])
        gbox(bm, xp - 0.06, xp + 0.06, PICKER_PIVOT_Y + 0.05, PICKER_PIVOT_Y + 0.12, z - 32 * IN, z + 32 * IN, M["frame"])
        side = -1 if i == 0 else 1
        cyl_y(bm, G(xp, PICKER_PIVOT_Y - 0.2, z - side * 18 * IN), 1.75 * IN, 20 * IN, mat_index=M["dark"])
        e = empty("ED_Picker%d" % (i + 1), coll, None, G(xp, PICKER_PIVOT_Y, z + side * 6 * IN), 0.08)
        pb = bmesh.new()
        o = G(xp, PICKER_PIVOT_Y, z + side * 6 * IN)
        cyl_x(pb, G(xp, PICKER_PIVOT_Y, z + side * 6 * IN) - o, 0.75 * IN, 0.2, mat_index=M["chrome"])
        gbox(pb, xp - 0.025, xp + 0.025, BELT_Y + 0.15, PICKER_PIVOT_Y, z + side * 6 * IN - 0.02, z + side * 6 * IN + 0.02,
             M["moving"], o)
        # Paddle over this side's half of the belt only, clear of the board in the middle.
        za, zb = sorted((z + side * 0.155, z + side * BELT_HALF))
        gbox(pb, xp - 0.12, xp + 0.12, BELT_Y + 0.012, BELT_Y + 0.15, za, zb, M["moving"], o)
        H.make("ED_Picker%dMesh" % (i + 1), pb, coll, mats, e)


# --- The edger -------------------------------------------------------------------------------

def place_edger(coll):
    import line_materials as LM
    import edger_build as E
    E.build(LM.build_all())
    ec = bpy.data.collections[E.COLL]
    root = bpy.data.objects.get("ED_Edger") or bpy.data.objects.new("ED_Edger", None)
    for c in list(root.users_collection):
        c.objects.unlink(root)
    coll.objects.link(root)
    # Edger local: +X feed, +Y drive side, Z up from the pads. Mill (Blender): X feed, -Y = +Z mill
    # (away from the transfer) so the drive side needs Y mirrored.
    root.location = (X0, -Z_LINE, EDGER_ORIGIN_Y - FLOOR)
    root.scale = (1, -1, 1)
    for o in list(ec.objects):
        if o.parent is None:
            o.parent = root
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    # Fonts don't export to glTF: turn the nameplate text into meshes. The edger is mirrored, so mirror
    # the lettering back about its own middle (and turn its faces round) or it reads backwards.
    for o in list(coll.objects):
        if o.type == 'FONT':
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.ops.object.convert(target='MESH')
            bm = bmesh.new()
            bm.from_mesh(o.data)
            xs = [v.co.x for v in bm.verts]
            mid = (min(xs) + max(xs)) / 2
            for v in bm.verts:
                v.co.x = 2 * mid - v.co.x
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(o.data)
            bm.free()
    return root


def sharp_link(coll, mats):
    """One link of the lineal infeed's sharp-top chain, for instancing: 1 1/2 in pitch, side bars
    along local -Z (travel), a hardened point standing up (+Y) out of the loop."""
    e = empty("ED_SharpLink", coll, None, (0, 0, 0), 0.03)
    bm = bmesh.new()
    p = 1.5 * IN
    for s in (-1, 1):
        L.add_box(bm, (0.005, p, 0.022), Matrix.Translation((s * 0.012, 0, -0.011)), M["dark"])
    L.add_cyl(bm, 0.006, 0.03, L.mat(loc=(0, p / 2, -0.011), rot=(0, 90, 0)), segs=8, mat_index=M["chrome"])
    # The point: a wedge rising to a sharp edge across the chain (Blender Y = travel, Z = up).
    v = [bm.verts.new(c) for c in ((-0.014, -0.009, 0.0), (-0.014, 0.009, 0.0), (-0.014, 0.0, 0.012),
                                   (0.014, -0.009, 0.0), (0.014, 0.009, 0.0), (0.014, 0.0, 0.012))]
    faces = [bm.faces.new(f) for f in ((v[0], v[1], v[2]), (v[3], v[5], v[4]), (v[0], v[3], v[4], v[1]),
                                       (v[1], v[4], v[5], v[2]), (v[2], v[5], v[3], v[0]))]
    for f in faces:
        f.material_index = M["chrome"]
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    H.make("ED_SharpLinkMesh", bm, coll, mats, e)
    return e


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("ED_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_deck(bm)
    build_skids(bm)
    build_positioners(coll, mats, bm)
    build_ramps(coll, mats, bm)
    build_hold_downs(coll, mats, bm)
    build_infeed(coll, mats, bm)
    build_picker_belt(coll, mats, bm)
    H.make("ED_FrameMesh", bm, coll, mats, frame)
    sharp_link(coll, mats)
    place_edger(coll)
    return {"objects": len(coll.all_objects), "x0": X0, "stations": STATION_X, "ramps": RAMP_X, "holds": HOLD_X,
            "infeed": INFEED_X, "belt": BELT_X, "pickers": PICKER_X, "skid_z": SKID_Z, "ramp_z": RAMP_Z,
            "ramp_shaft": RAMP_SHAFT, "pos_park_z": POS_PARK_Z, "cush_park_z": CUSH_PARK_Z, "edger_y": EDGER_ORIGIN_Y}
