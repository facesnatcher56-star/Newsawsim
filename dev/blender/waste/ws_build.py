"""Waste system: slashers, vibrating pan conveyors and the big drum chipper (run inside Blender).

All the mill's sawing waste ends here, chopped short first so it can turn corners on the pans:
  - slab slasher under the headrig outfeed's slab kickers: three strands of chain carry slabs
    sideways (-Z) over three circular saws on one arbor that chop them into ~1.2 m pieces, which fall
    off the head onto the slab pan
  - two edging slashers either side of the picker belt: the pendulum pickers sweep edgings onto
    short chains that carry them out over four saws each and off the deck edge down chutes
  - six vibrating pan conveyors on coil springs, each shaken by an eccentric drive: the slab pan
    and its cross pan, the two edging pans and their cross pan, and a collector into the chipper
  - big drum chipper by the east wall with infeed throat, rubber curtain, fluted feed roll, belt
    drive from a 500 hp motor, blower and a blow pipe out through the wall to a cyclone over a chip
    bin, with a truck bay under it

Built in mill coordinates like the headrig: Godot (x, y, z) = Blender (x, -z, y + 1.288), H.G().

  WS_Frame                    fixed steel and the chipper
  WS_Pan1..6                  pan troughs (the game shakes them; they sit on their springs)
  WS_SlabArbor, WS_EdgeArborNear/Far   slasher saw arbors (spin about X)
  WS_SlabTail/Head, WS_EdgeNearTail/Head, WS_EdgeFarTail/Head   slasher chain shafts (spin about X)
  WS_FeedRoll                 chipper feed roll (spins about Z)
  WS_Drum                     chipper drum with its knives (spins about Z)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
for d in (os.path.join(HERE, "..", "headrig"), os.path.join(HERE, "..", "common")):
    if d not in sys.path:
        sys.path.insert(0, d)
import hr_build as H  # noqa: E402
import mesh_lib as L  # noqa: E402

G, gbox, beam, cyl_x, cyl_y, cyl_z, plate_zy, empty = H.G, H.gbox, H.beam, H.cyl_x, H.cyl_y, H.cyl_z, H.plate_zy, H.empty
M = H.M
FLOOR = H.FLOOR

COLL = "WasteSystem"
DECK_Y = 0.0233
WALL_X = 65.85                                     # east wall (the mill was extended east)

# Slab slasher: chains running -Z from the kicker skids to over the slab pan.
SLAB_SL_X = (30.6, 32.7, 34.8)                     # chain strands
SLAB_SL_Z = (4.55, 3.15)                           # tail (upstream) and head, out over the slab pan
SLAB_SL_Y = -0.45                                  # chain tops
SLAB_SAW_X = (31.48, 32.70, 33.92)
SLAB_SAW_Z = 3.95
SLAB_SAW_R = 0.30
# Edging slashers (deck level): near side runs -Z, far side +Z.
EDGE_Y = 0.30
EDGE_NEAR_Z = (20.65, 19.85)
EDGE_FAR_Z = (22.55, 24.45)
EDGE_X = (46.9, 48.4, 49.9, 51.4, 52.4)
EDGE_SAW_X = (47.75, 48.95, 50.15, 51.35)
EDGE_SAW_R = 0.20
EDGE_NEAR_SAW_Z = 20.25
EDGE_FAR_SAW_Z = 23.5
SL_R = 0.08                                        # slasher sprockets
# Vibrating pans: (name, start (x, z), end (x, z), floor y). Pieces travel start -> end.
PAN_W = 1.4
PAN_WALL = 0.15                                    # each pan's floor is above the walls of the pan it empties into
PANS = (
    ("Pan1", (29.6, 2.7), (54.4, 2.7), -0.62),     # slab pan
    ("Pan2", (54.4, 2.0), (54.4, 11.45), -0.79),    # slab cross pan
    ("Pan3", (46.4, 19.2), (54.4, 19.2), -0.62),   # near edging pan
    ("Pan4", (46.4, 25.3), (54.4, 25.3), -0.62),   # far edging pan
    ("Pan5", (54.4, 26.0), (54.4, 12.55), -0.79),   # edging cross pan
    ("Pan6", (53.4, 12.0), (55.45, 12.0), -0.96),  # collector into the chipper
)
# Chipper (infeed +X).
CHIP_Z = 12.0
THROAT_X = 55.45
FEED_ROLL = (55.75, -0.60, 0.24)                   # x, y, r
DRUM = (56.75, -0.55, 0.75)                        # x, y of the axis, radius
MOTOR = (55.85, -0.66, 0.55)                       # x, y, r of the 500 hp motor (axis along Z)
PIPE_X = 56.95                                     # blow pipe riser
PIPE_R = 0.25
PIPE_Y = 5.0
CYCLONE = (69.5, 12.0)
BIN_Y = 2.6


def pan_frame(p0, p1):
    """Unit direction and the perpendicular across a pan, in (x, z)."""
    d = Vector((p1[0] - p0[0], p1[1] - p0[1]))
    d.normalize()
    return d, Vector((-d.y, d.x))


# --- Slashers -----------------------------------------------------------------------------------

def build_slab_slasher(bm):
    z0, z1 = SLAB_SL_Z
    y = SLAB_SL_Y
    for x in SLAB_SL_X:
        gbox(bm, x - 0.025, x + 0.025, y - 0.03, y - 0.012, z1 + 0.05, z0 - 0.05, M["wear"])
        gbox(bm, x - 0.03, x + 0.03, y - 0.16, y - 0.03, z1 + 0.05, z0 - 0.05, M["frame"])
    xa, xb = SLAB_SL_X[0] - 0.4, SLAB_SL_X[-1] + 0.4
    for z in (z0, z1):
        gbox(bm, xa, xb, y - 0.3, y - 0.22, z - 0.04, z + 0.04, M["frame"])
        for x in (xa, (xa + xb) / 2, xb):
            gbox(bm, x - 0.04, x + 0.04, FLOOR, y - 0.22, z - 0.04, z + 0.04, M["frame"])
    # Saw guard box under the deck, saw arbor bearings, drive motor on the +X end.
    ay = y - SLAB_SAW_R + 0.09
    gbox(bm, SLAB_SAW_X[0] - 0.25, SLAB_SAW_X[-1] + 0.25, ay - SLAB_SAW_R - 0.05, y - 0.06, SLAB_SAW_Z - 0.35,
         SLAB_SAW_Z - 0.3, M["mill"])
    gbox(bm, SLAB_SAW_X[0] - 0.25, SLAB_SAW_X[-1] + 0.25, ay - SLAB_SAW_R - 0.05, y - 0.06, SLAB_SAW_Z + 0.3,
         SLAB_SAW_Z + 0.35, M["mill"])
    for x in (SLAB_SAW_X[0] - 0.35, SLAB_SAW_X[-1] + 0.35):
        gbox(bm, x - 0.06, x + 0.06, FLOOR, ay + 0.06, SLAB_SAW_Z - 0.08, SLAB_SAW_Z + 0.08, M["dark"])
    gbox(bm, SLAB_SAW_X[-1] + 0.5, SLAB_SAW_X[-1] + 1.1, FLOOR, ay + 0.1, SLAB_SAW_Z - 0.3, SLAB_SAW_Z + 0.3, M["motor"])
    cyl_x(bm, G(SLAB_SAW_X[-1] + 0.8, ay, SLAB_SAW_Z), 0.25, 0.6, mat_index=M["motor"])


def build_edge_slasher(bm, zs, saw_z, side):
    z0, z1 = zs
    y = EDGE_Y
    lo, hi = min(z0, z1), max(z0, z1)
    for x in EDGE_X:
        gbox(bm, x - 0.02, x + 0.02, y - 0.025, y - 0.01, lo + 0.04, hi - 0.04, M["wear"])
        gbox(bm, x - 0.025, x + 0.025, y - 0.12, y - 0.025, lo + 0.04, hi - 0.04, M["frame"])
    xa, xb = EDGE_X[0] - 0.2, EDGE_X[-1] + 0.2
    for z in (lo + 0.1, hi - 0.1):
        gbox(bm, xa, xb, y - 0.2, y - 0.14, z - 0.03, z + 0.03, M["frame"])
        for x in (xa, (xa + xb) / 2, xb):
            gbox(bm, x - 0.03, x + 0.03, DECK_Y, y - 0.14, z - 0.03, z + 0.03, M["frame"])
    ay = y - EDGE_SAW_R + 0.06
    gbox(bm, EDGE_SAW_X[0] - 0.2, EDGE_SAW_X[-1] + 0.2, DECK_Y, y - 0.05, saw_z - 0.24, saw_z - 0.21, M["mill"])
    gbox(bm, EDGE_SAW_X[0] - 0.2, EDGE_SAW_X[-1] + 0.2, DECK_Y, y - 0.05, saw_z + 0.21, saw_z + 0.24, M["mill"])
    gbox(bm, xb + 0.1, xb + 0.5, DECK_Y, ay + 0.1, saw_z - 0.2, saw_z + 0.2, M["motor"])
    # Chute from the chain head over the deck edge down to its pan.
    pan_z = 19.2 if side < 0 else 25.3
    beam(bm, ((xa + xb) / 2, y - 0.02, z1 + side * 0.02), ((xa + xb) / 2, -0.40, pan_z - side * 0.45), xb - xa, 0.012,
         M["wear"])
    for x in (xa, xb):
        L.add_prism(bm, [(-(z1), y + 0.15 - FLOOR), (-(pan_z - side * 0.45), -0.25 - FLOOR),
                         (-(pan_z - side * 0.45), -0.40 - FLOOR), (-(z1), y - 0.02 - FLOOR)], -0.006, 0.006,
                    Matrix(((0, 1, 0, x), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))), M["frame"])


def slasher_parts(coll, mats):
    def arbor(name, xs, z, ay, r):
        xm = (xs[0] + xs[-1]) / 2
        e = empty(name, coll, None, G(xm, ay, z), 0.08)
        bm = bmesh.new()
        L.add_cyl(bm, 0.04, xs[-1] - xs[0] + 0.9, L.mat(rot=(0, 90, 0)), segs=12, mat_index=M["chrome"])
        for x in xs:
            L.add_cyl(bm, r, 0.005, L.mat(loc=(x - xm, 0, 0), rot=(0, 90, 0)), segs=36, mat_index=M["blade"])
            L.add_cyl(bm, 0.08, 0.03, L.mat(loc=(x - xm, 0, 0), rot=(0, 90, 0)), segs=16, mat_index=M["dark"])
            for k in range(24):
                L.add_box(bm, (0.012, 0.02, 0.02), L.mat(rot=(k * 15, 0, 0)) @ Matrix.Translation((x - xm, 0, r)),
                          M["chrome"])
        H.make(name + "Mesh", bm, coll, mats, e)

    def shaft(name, xs, z, y, r):
        xm = (xs[0] + xs[-1]) / 2
        e = empty(name, coll, None, G(xm, y - r, z), 0.06)
        bm = bmesh.new()
        L.add_cyl(bm, 0.025, xs[-1] - xs[0] + 0.5, L.mat(rot=(0, 90, 0)), segs=10, mat_index=M["chrome"])
        for x in xs:
            L.add_cyl(bm, r + 0.008, 0.025, L.mat(loc=(x - xm, 0, 0), rot=(0, 90, 0)), segs=14, mat_index=M["dark"])
        H.make(name + "Mesh", bm, coll, mats, e)

    arbor("WS_SlabArbor", SLAB_SAW_X, SLAB_SAW_Z, SLAB_SL_Y - SLAB_SAW_R + 0.09, SLAB_SAW_R)
    arbor("WS_EdgeArborNear", EDGE_SAW_X, EDGE_NEAR_SAW_Z, EDGE_Y - EDGE_SAW_R + 0.06, EDGE_SAW_R)
    arbor("WS_EdgeArborFar", EDGE_SAW_X, EDGE_FAR_SAW_Z, EDGE_Y - EDGE_SAW_R + 0.06, EDGE_SAW_R)
    shaft("WS_SlabTail", SLAB_SL_X, SLAB_SL_Z[0], SLAB_SL_Y, SL_R)
    shaft("WS_SlabHead", SLAB_SL_X, SLAB_SL_Z[1], SLAB_SL_Y, SL_R)
    shaft("WS_EdgeNearTail", EDGE_X, EDGE_NEAR_Z[0], EDGE_Y, SL_R)
    shaft("WS_EdgeNearHead", EDGE_X, EDGE_NEAR_Z[1], EDGE_Y, SL_R)
    shaft("WS_EdgeFarTail", EDGE_X, EDGE_FAR_Z[0], EDGE_Y, SL_R)
    shaft("WS_EdgeFarHead", EDGE_X, EDGE_FAR_Z[1], EDGE_Y, SL_R)


# --- Vibrating pans --------------------------------------------------------------------------------

def build_pans(coll, mats, bm):
    for name, p0, p1, fy in PANS:
        d, n = pan_frame(p0, p1)
        length = (Vector(p1) - Vector(p0)).length
        mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
        piv = G(mid[0], fy, mid[1])
        e = empty("WS_" + name, coll, None, piv, 0.1)
        pb = bmesh.new()
        along_x = abs(d.x) > 0.5
        hl, hw = length / 2, PAN_W / 2

        def pbox(a0, a1, y0, y1, c0, c1, mat):
            # a = along the pan, c = across; mapped to x/z.
            if along_x:
                gbox(pb, mid[0] + a0, mid[0] + a1, y0, y1, mid[1] + c0, mid[1] + c1, mat, piv)
            else:
                gbox(pb, mid[0] + c0, mid[0] + c1, y0, y1, mid[1] + a0, mid[1] + a1, mat, piv)
        pbox(-hl, hl, fy - 0.012, fy, -hw, hw, M["wear"])
        for s in (-1, 1):
            pbox(-hl, hl, fy - 0.012, fy + PAN_WALL, s * hw - 0.006, s * hw + 0.006, M["mill"])
            pbox(-hl, hl, fy + PAN_WALL - 0.04, fy + PAN_WALL, s * hw - 0.03 * (-s), s * hw + 0.03 * s, M["mill"])
        # Tail end plate (pieces never go back past it), stiffening ribs under the pan.
        tail = -hl if (d.x + d.y) > 0 else hl
        pbox(tail - 0.006, tail + 0.006, fy - 0.012, fy + PAN_WALL, -hw, hw, M["mill"])
        k = 0
        while -hl + 0.3 + k * 1.2 < hl:
            a = -hl + 0.3 + k * 1.2
            pbox(a - 0.03, a + 0.03, fy - 0.1, fy - 0.012, -hw, hw, M["mill"])
            k += 1
        H.make("WS_%sMesh" % name, pb, coll, mats, e)
        # Fixed base: two sills on legs, coil springs up to the pan every 1.8 m, drive at the tail.
        base_y = fy - 0.22
        k = 0
        while -hl + 0.4 + k * 1.8 < hl:
            a = -hl + 0.4 + k * 1.8
            for s in (-1, 1):
                c = s * (hw - 0.12)
                px, pz = (mid[0] + a, mid[1] + c) if along_x else (mid[0] + c, mid[1] + a)
                cyl_z(bm, G(px, (base_y + fy - 0.1) / 2, pz), 0.05, fy - 0.1 - base_y, segs=12, mat_index=M["dark"])
                for t in range(4):
                    cyl_z(bm, G(px, base_y + 0.03 + t * (fy - 0.13 - base_y) / 4, pz), 0.065, 0.012, segs=12,
                          mat_index=M["red"])
                gbox(bm, px - 0.06, px + 0.06, FLOOR, base_y, pz - 0.06, pz + 0.06, M["frame"])
            k += 1
        for s in (-1, 1):
            c = s * (hw - 0.12)
            if along_x:
                gbox(bm, mid[0] - hl, mid[0] + hl, base_y - 0.06, base_y, mid[1] + c - 0.05, mid[1] + c + 0.05, M["frame"])
            else:
                gbox(bm, mid[0] + c - 0.05, mid[0] + c + 0.05, base_y - 0.06, base_y, mid[1] - hl, mid[1] + hl, M["frame"])
        # Eccentric drive: motor and a drive arm on the tail end.
        tx, tz = (mid[0] + tail * 1.0, mid[1]) if along_x else (mid[0], mid[1] + tail)
        off = -0.35 if tail < 0 else 0.35
        dx, dz = (tx + off, tz) if along_x else (tx, tz + off)
        gbox(bm, dx - 0.22, dx + 0.22, FLOOR, base_y - 0.05, dz - 0.22, dz + 0.22, M["frame"])
        cyl_z(bm, G(dx, base_y + 0.08, dz), 0.18, 0.3, segs=20, mat_index=M["motor"])


# --- Chipper -------------------------------------------------------------------------------------

def build_chipper(bm):
    z = CHIP_Z
    z0, z1 = z - 0.6, z + 0.6
    fy = -0.96
    tx = THROAT_X
    dx, dy, dr = DRUM
    # Infeed throat: cheeks, floor, roof, rubber curtain strips.
    for zz in (z0, z1):
        gbox(bm, tx, dx - 0.6, fy - 0.03, 0.15, zz - 0.03, zz + 0.03, M["mill"])
    gbox(bm, tx, dx - 0.6, 0.12, 0.18, z0 - 0.03, z1 + 0.03, M["mill"])
    gbox(bm, tx, dx - 0.6, fy - 0.06, fy, z0, z1, M["wear"])
    for k in range(9):
        zz = z0 + 0.08 + k * (z1 - z0 - 0.16) / 8
        gbox(bm, tx + 0.02, tx + 0.03, fy + 0.2, 0.12, zz - 0.06, zz + 0.06, M["rubber"])
    # Drum housing: base, hood, inspection doors.
    gbox(bm, dx - 0.95, dx + 0.95, FLOOR, dy, z0 - 0.08, z1 + 0.08, M["mill"])
    cyl_y(bm, G(dx, dy, z), dr + 0.12, z1 - z0 + 0.16, segs=40, mat_index=M["mill"])
    gbox(bm, dx - 1.0, dx + 1.0, FLOOR, FLOOR + 0.1, z0 - 0.3, z1 + 0.3, M["dark"])
    gbox(bm, dx - 0.4, dx + 0.4, dy + 0.1, dy + 0.75, z1 + 0.08, z1 + 0.1, M["dark"])
    # Drum bearings and shaft; the shaft runs out on the +Z side to a sheave, belts to the 500 hp
    # motor beside it (clear of both cross pans, which run along x 53.7-55.1).
    for zz in (z0 - 0.25, z1 + 0.25):
        gbox(bm, dx - 0.25, dx + 0.25, FLOOR, dy - 0.15, zz - 0.15, zz + 0.15, M["mill"])
        gbox(bm, dx - 0.2, dx + 0.2, dy - 0.15, dy + 0.15, zz - 0.13, zz + 0.13, M["dark"])
    cyl_y(bm, G(dx, dy, z + 0.2), 0.12, z1 - z0 + 1.0, segs=16, mat_index=M["chrome"])
    mx, my, mr = MOTOR
    gz = z1 + 0.6
    L.add_prism(bm, [(dx - 0.42, dy - 0.42 - FLOOR), (mx - 0.36, my - 0.36 - FLOOR), (mx + 0.36, my - 0.36 - FLOOR),
                     (dx + 0.42, dy - 0.42 - FLOOR), (dx + 0.42, dy + 0.42 - FLOOR), (dx - 0.42, dy + 0.42 - FLOOR)],
                -(gz + 0.12), -(gz - 0.12), None, M["moving"])
    mz0, mz1 = gz + 0.15, gz + 2.1
    gbox(bm, mx - 0.55, mx + 0.55, FLOOR, FLOOR + 0.12, mz0 - 0.05, mz1 + 0.1, M["dark"])
    gbox(bm, mx - 0.42, mx + 0.42, FLOOR + 0.12, my - mr * 0.6, mz0 + 0.1, mz1 - 0.1, M["motor"])
    cyl_y(bm, G(mx, my, (mz0 + mz1) / 2), mr, mz1 - mz0 - 0.2, segs=32, mat_index=M["motor"])
    for k in range(14):
        zz = mz0 + 0.25 + k * (mz1 - mz0 - 0.4) / 13
        cyl_y(bm, G(mx, my, zz), mr + 0.035, 0.035, segs=32, mat_index=M["motor"])
    cyl_y(bm, G(mx, my, mz1 + 0.02), mr - 0.05, 0.25, segs=32, mat_index=M["dark"])
    gbox(bm, mx - 0.2, mx + 0.2, my + mr - 0.05, my + mr + 0.28, mz0 + 0.4, mz0 + 0.8, M["motor"])
    # Blowing drum: the knives throw the chips up a discharge spout on top of the hood straight into
    # the blow pipe, up and out through the wall.
    px = PIPE_X
    top = dy + dr + 0.12
    gbox(bm, px - 0.3, px + 0.3, top - 0.25, top + 0.2, z - 0.35, z + 0.35, M["mill"])
    cyl_z(bm, G(px, (top + PIPE_Y) / 2, z), PIPE_R, PIPE_Y - top, segs=24, mat_index=M["wear"])
    L.add_sphere(bm, PIPE_R * 1.08, Matrix.Translation(G(px, PIPE_Y, z)), segs=24, rings=12, mat_index=M["wear"])
    for y in (1.0, 2.5, 4.0):
        cyl_z(bm, G(px, y, z), PIPE_R + 0.03, 0.08, segs=24, mat_index=M["dark"])
    # Wall sleeve where the pipe goes through.
    cyl_x(bm, G(WALL_X + 0.15, PIPE_Y, z), PIPE_R + 0.08, 0.5, segs=24, mat_index=M["dark"])
    cx, cz = CYCLONE
    cyl_x(bm, G((px + cx) / 2, PIPE_Y, z), PIPE_R, cx - px, segs=24, mat_index=M["wear"])
    for y in (0.5, 2.5, 4.0):
        cyl_z(bm, G(px, y, z), PIPE_R + 0.03, 0.08, segs=24, mat_index=M["dark"])
    # Wall sleeve where the pipe goes through.
    cyl_x(bm, G(WALL_X + 0.15, PIPE_Y, z), PIPE_R + 0.08, 0.5, segs=24, mat_index=M["dark"])
    # Outside: cyclone on top of a chip bin on legs, with a truck bay under it.
    cyl_z(bm, G(cx, PIPE_Y + 0.2, cz), 0.9, 1.6, segs=32, mat_index=M["wear"])
    cyl_z(bm, G(cx, PIPE_Y - 1.0, cz), 0.9, 0.8, segs=32, mat_index=M["wear"], r2=0.25)
    cyl_z(bm, G(cx, PIPE_Y + 1.2, cz), 0.3, 0.6, segs=20, mat_index=M["wear"])
    # Bin: a square hopper on four legs.
    b0, b1 = cx - 1.8, cx + 1.8
    c0, c1 = cz - 1.8, cz + 1.8
    gbox(bm, b0, b1, BIN_Y + 1.0, PIPE_Y - 1.3, c0, c1, M["frame"])
    L.add_loft(bm, [[G(b0, BIN_Y + 1.0, c0), G(b1, BIN_Y + 1.0, c0), G(b1, BIN_Y + 1.0, c1), G(b0, BIN_Y + 1.0, c1)],
                    [G(cx - 0.35, BIN_Y, cz - 0.35), G(cx + 0.35, BIN_Y, cz - 0.35), G(cx + 0.35, BIN_Y, cz + 0.35),
                     G(cx - 0.35, BIN_Y, cz + 0.35)]], mat_index=M["frame"])
    gbox(bm, cx - 0.35, cx + 0.35, BIN_Y - 0.3, BIN_Y, cz - 0.35, cz + 0.35, M["dark"])
    for x in (b0 + 0.1, b1 - 0.1):
        for zz in (c0 + 0.1, c1 - 0.1):
            gbox(bm, x - 0.1, x + 0.1, FLOOR, BIN_Y + 1.0, zz - 0.1, zz + 0.1, M["frame"])
    # Ladder and platform rail on the bin.
    for zz in (c1 + 0.1, c1 + 0.5):
        gbox(bm, b1 - 0.4 - 0.02, b1 - 0.4 + 0.02, FLOOR, PIPE_Y - 1.3, zz - 0.02, zz + 0.02, M["moving"])
    for k in range(int((PIPE_Y - 1.3 - FLOOR) / 0.3)):
        gbox(bm, b1 - 0.42, b1 - 0.38, FLOOR + 0.3 * (k + 1) - 0.01, FLOOR + 0.3 * (k + 1) + 0.01, c1 + 0.1, c1 + 0.5,
             M["moving"])


def chipper_parts(coll, mats):
    fx, fy, fr = FEED_ROLL
    e = empty("WS_FeedRoll", coll, None, G(fx, fy, CHIP_Z), 0.1)
    bm = bmesh.new()
    L.add_cyl(bm, fr - 0.03, 1.12, L.mat(rot=(90, 0, 0)), segs=24, mat_index=M["wear"])
    for k in range(14):
        L.add_box(bm, (0.05, 1.1, 0.05), Matrix.Rotation(k * math.tau / 14, 4, 'Y') @ Matrix.Translation((0, 0, fr - 0.03))
                  @ Matrix.Rotation(math.radians(45), 4, 'Y'), M["wear"])
    L.add_cyl(bm, 0.06, 1.5, L.mat(rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
    H.make("WS_FeedRollMesh", bm, coll, mats, e)
    dx, dy, dr = DRUM
    d = empty("WS_Drum", coll, None, G(dx, dy, CHIP_Z), 0.1)
    bm = bmesh.new()
    L.add_cyl(bm, dr - 0.05, 1.1, L.mat(rot=(90, 0, 0)), segs=32, mat_index=M["dark"])
    L.add_cyl(bm, 0.12, 1.9, L.mat(rot=(90, 0, 0)), segs=16, mat_index=M["chrome"])
    for k in range(4):
        L.add_box(bm, (0.04, 1.08, 0.08), Matrix.Rotation(k * math.tau / 4, 4, 'Y') @ Matrix.Translation((0, 0, dr - 0.02)),
                  M["chrome"])
    H.make("WS_DrumMesh", bm, coll, mats, d)


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("WS_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_slab_slasher(bm)
    build_edge_slasher(bm, EDGE_NEAR_Z, EDGE_NEAR_SAW_Z, -1)
    build_edge_slasher(bm, EDGE_FAR_Z, EDGE_FAR_SAW_Z, 1)
    build_pans(coll, mats, bm)
    build_chipper(bm)
    H.make("WS_FrameMesh", bm, coll, mats, frame)
    slasher_parts(coll, mats)
    chipper_parts(coll, mats)
    return {"objects": len(coll.all_objects)}
