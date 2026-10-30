"""Board line, part 4: landing table and transfer from the picker belt end to the sorter's lug incline
(run inside Blender).

Boards run off the end of the picker belt onto a landing table of live lift rolls between five
transfer chain strands, to a cushioned end stop. The rolls then drop below the chains, the board
settles on them and the chains carry it sideways (+Z), level for a short way, then down an 11 deg
run to a level end whose chains interleave with the lug incline's (the incline's lugs rise through
here and pick the board up), as the old landing deck did.

Built in mill coordinates like the headrig: Godot (x, y, z) = Blender (x, -z, y + 1.288), H.G().

  LT_Frame                         fixed steel, end stop, legs, drive
  LT_Lift (> LT_Roll1..n)          lift frame with its live rolls (frame moves along Y, rolls spin about Z)
  LT_Tail / LT_Head                transfer chain shafts (spin about X)
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

COLL = "BoardLineLanding"
BELT_END_X = 52.64
BOARD_X = 55.6                                   # board centre on the table (sorter line)
STOP_X = 58.04                                   # end stop face
STRAND_X = tuple(BOARD_X + d for d in (-2.75, -1.375, 0.0, 1.375, 2.75))
LANE_Z = 21.6
# Transfer chain path (z, y) of the chain tops, tail to head.
PATH = ((21.25, 1.060), (22.10, 1.060), (26.82, 0.127), (27.82, 0.127))
SPROCKET_R = 0.0762
ROLL_TOP = 1.080                                 # lift roll tops when up
ROLL_DROP = 0.08
ROLL_R = 0.06
ROLL_LEN = 0.6


def roll_xs():
    xs, x = [], BELT_END_X + 0.22
    while x < STOP_X - 0.1:
        if all(abs(x - s) > 0.13 for s in STRAND_X):
            xs.append(x)
        x += 0.42
    return xs


def build_frame(bm):
    # Strand stringers along the path, wear strips on top.
    for x in STRAND_X:
        for (za, ya), (zb, yb) in zip(PATH, PATH[1:]):
            beam(bm, (x, ya - 0.01, za), (x, yb - 0.01, zb), 0.04, 0.02, M["wear"])
            beam(bm, (x, ya - 0.08, za), (x, yb - 0.08, zb), 0.05, 0.12, M["frame"])
    xa, xb = STRAND_X[0] - 0.15, STRAND_X[-1] + 0.15
    # Cross beams and legs: clear of the edging pans and cross pan (x 46.4-55.1, z 12.5-26.0).
    for z, y in ((21.35, 0.92), (22.0, 0.92), (27.6, 0.0)):
        gbox(bm, xa, xb, y - 0.08, y, z - 0.04, z + 0.04, M["frame"])
        for x in (STRAND_X[0] - 0.12, 56.2, STRAND_X[-1] + 0.12):
            gbox(bm, x - 0.05, x + 0.05, FLOOR, y - 0.08, z - 0.05, z + 0.05, M["frame"])
            gbox(bm, x - 0.1, x + 0.1, FLOOR, FLOOR + 0.015, z - 0.1, z + 0.1, M["dark"])
    # A long spine under the sloped run, carried by the end frames.
    for x in (STRAND_X[0] - 0.12, STRAND_X[-1] + 0.12):
        beam(bm, (x, 0.84, 22.0), (x, -0.08, 27.6), 0.06, 0.1, M["frame"])
    # Shaft bearings, drive at the head on the +X side.
    for (z, y) in (PATH[0], PATH[-1]):
        for x in (xa, xb):
            gbox(bm, x - 0.04, x + 0.04, y - SPROCKET_R - 0.05, y - SPROCKET_R + 0.05, z - 0.05, z + 0.05, M["dark"])
    hz, hy = PATH[-1]
    gbox(bm, xb + 0.05, xb + 0.4, hy - 0.25, hy + 0.05, hz - 0.2, hz + 0.1, M["motor"])
    cyl_x(bm, G(xb + 0.6, hy - 0.1, hz - 0.05), 0.1, 0.35, mat_index=M["motor"])
    # End stop: posts, plate and rubber pad facing the belt.
    for z in (LANE_Z - 0.3, LANE_Z + 0.3):
        gbox(bm, STOP_X + 0.06, STOP_X + 0.18, FLOOR, ROLL_TOP + 0.35, z - 0.06, z + 0.06, M["frame"])
    gbox(bm, STOP_X + 0.03, STOP_X + 0.08, ROLL_TOP - 0.02, ROLL_TOP + 0.33, LANE_Z - 0.38, LANE_Z + 0.38, M["frame"])
    gbox(bm, STOP_X, STOP_X + 0.03, ROLL_TOP + 0.0, ROLL_TOP + 0.28, LANE_Z - 0.33, LANE_Z + 0.33, M["rubber"])
    # Lift cylinders under the roll frame.
    for x in (roll_xs()[1], roll_xs()[-2]):
        cyl_z(bm, G(x, 0.62, LANE_Z), 0.06, 0.3, mat_index=M["dark"])
        gbox(bm, x - 0.08, x + 0.08, FLOOR, 0.47, LANE_Z - 0.08, LANE_Z + 0.08, M["frame"])


def build_lift(coll, mats):
    xs = roll_xs()
    cy = ROLL_TOP - ROLL_R
    piv = G((xs[0] + xs[-1]) / 2, cy, LANE_Z)
    root = empty("LT_Lift", coll, None, piv, 0.15)
    bm = bmesh.new()
    for s in (-1, 1):
        gbox(bm, xs[0] - 0.1, xs[-1] + 0.1, cy - 0.12, cy - 0.03, LANE_Z + s * 0.36 - 0.03, LANE_Z + s * 0.36 + 0.03,
             M["frame"], piv)
    gbox(bm, xs[0] - 0.1, xs[-1] + 0.1, cy - 0.2, cy - 0.12, LANE_Z - 0.39, LANE_Z + 0.39, M["frame"], piv)
    # Line shaft and gearmotor on the far side driving the rolls.
    cyl_x(bm, G((xs[0] + xs[-1]) / 2, cy - 0.08, LANE_Z + 0.45) - piv, 0.025, xs[-1] - xs[0], mat_index=M["dark"])
    gbox(bm, xs[-1] - 0.45, xs[-1], cy - 0.3, cy - 0.05, LANE_Z + 0.48, LANE_Z + 0.75, M["motor"], piv)
    H.make("LT_LiftMesh", bm, coll, mats, root)
    for i, x in enumerate(xs):
        r = empty("LT_Roll%d" % (i + 1), coll, root, G(x, cy, LANE_Z), 0.06)
        rb = bmesh.new()
        L.add_cyl(rb, ROLL_R, ROLL_LEN, L.mat(rot=(90, 0, 0)), segs=18, mat_index=M["wear"])
        L.add_cyl(rb, 0.02, 0.8, L.mat(loc=(0, -0.08, 0), rot=(90, 0, 0)), segs=8, mat_index=M["dark"])
        H.make("LT_Roll%dMesh" % (i + 1), rb, coll, mats, r)


def build_shafts(coll, mats):
    xm = (STRAND_X[0] + STRAND_X[-1]) / 2
    for name, (z, y) in (("LT_Tail", PATH[0]), ("LT_Head", PATH[-1])):
        e = empty(name, coll, None, G(xm, y - SPROCKET_R, z), 0.06)
        bm = bmesh.new()
        L.add_cyl(bm, 0.025, STRAND_X[-1] - STRAND_X[0] + 0.4, L.mat(rot=(0, 90, 0)), segs=10, mat_index=M["chrome"])
        for x in STRAND_X:
            L.add_cyl(bm, SPROCKET_R + 0.008, 0.025, L.mat(loc=(x - xm, 0, 0), rot=(0, 90, 0)), segs=14,
                      mat_index=M["dark"])
        H.make(name + "Mesh", bm, coll, mats, e)


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("LT_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_frame(bm)
    H.make("LT_FrameMesh", bm, coll, mats, frame)
    build_lift(coll, mats)
    build_shafts(coll, mats)
    return {"objects": len(coll.all_objects), "rolls": [round(x, 3) for x in roll_xs()], "strands": STRAND_X}
