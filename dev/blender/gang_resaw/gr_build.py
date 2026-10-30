"""Cant transfer, flip turner, sharp-chain infeed and twin-arbor chipping gang (run inside Blender).

The cant kickers on the headrig outfeed throw two-sided cants (+Z) onto a short three-strand
chain transfer that carries them to a stop. A flip turner on a shaft beside the stop rolls each
cant 90 deg over onto a sharp chain, sawn faces down, and the chain feeds it end-first (+X)
under two press rolls into the gang:
  - a chipping canter: two conical chip heads on vertical spindles flatten the round sides
  - twin arbors of circular saws (top and bottom) split the cant into eight 2x12s on edge
  - chips go up a duct and over to the slab chipper's blow pipe
The boards come out on a lift-roll outfeed between the board transfer's strands; at the end
stop the rolls drop and the boards settle onto the transfer.

Built in mill coordinates like the headrig: Godot (x, y, z) = Blender (x, -z, y + 1.288), H.G().

  GR_Frame                          transfer frame, cant stop, sharp chain frame, gang housing,
                                    motors and guards, outfeed base, end stop, chip duct
  GR_TransferHead / GR_TransferTail cant transfer sprocket shafts (spin about X)
  GR_Turner                         flip turner shaft and arms (rotate about X)
  GR_Press1..2                      press roll arms (rotate about Z), each with GR_PressRoll1..2
  GR_TopArbor / GR_BottomArbor      saw arbors (spin about Z)
  GR_ChipHeadNear / GR_ChipHeadFar  chip heads (spin about Y)
  GR_Lift                           outfeed lift frame (moves along Y) with GR_ORoll1..n (spin about Z)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
import hr_build as H  # noqa: E402
import mesh_lib as L  # noqa: E402

G, gbox, beam, cyl_x, cyl_y, cyl_z, plate_zy, empty = H.G, H.gbox, H.beam, H.cyl_x, H.cyl_y, H.cyl_z, H.plate_zy, H.empty
M = H.M
FLOOR = H.FLOOR

COLL = "GangResaw"
# Cant transfer: strands along Z from the outfeed case to the stop.
XFER_X = (30.9, 32.7, 34.5)
XFER_Z = (5.95, 8.05)                 # tail and head sprocket centres
XFER_TOP_Y = -0.22
XFER_SPROCKET_R = 0.1
STOP_Z = 8.12                         # stop plate face
# Flip turner: pivot (z, y); at rest the arm tips lie under the cant at the stop.
TURNER_X = (31.8, 33.6)
TURNER_PIVOT = (8.45, -0.5)
# Sharp chain infeed (cant centre line z), gang, outfeed.
LINE_Z = 8.9
SHARP_X = (30.2, 36.35)
SHARP_TOP_Y = -0.15
CANT_H = 0.29                         # between the sawn faces
PRESS = ((34.0, 0.78), (35.25, 0.78))  # arm pivots (x, y); the roll hangs 0.62 m downstream
PRESS_ARM = 0.62
PRESS_R = 0.11
CHIP_X = 36.75
SAW_X = 37.25
SAW_R = 0.36
BOARD_T = 0.038
KERF = 0.005
N_BOARDS = 8
HOUSING_X = (36.4, 38.1)
HOUSING_Z = (8.1, 9.7)
OUT_X = (38.2, 43.7)
OUT_ROLL_X = tuple(38.25 + 0.5 * k for k in range(11))
OUT_ROLL_R = 0.075
OUT_TOP_Y = SHARP_TOP_Y               # roll tops when raised, level with the sharp chain
LIFT_DROP = 0.2
OUT_STOP_X = 43.65
# Chip duct to the slab chipper's blow pipe (its riser is at x 47.8, z 3.875).
DUCT_R = 0.12
DUCT_Y = 5.0
PIPE_X = 56.95
PIPE_Z = 12.0


def saw_zs():
    """Kerf centres across the cant: between the boards and at the two flattened sides."""
    pitch = BOARD_T + KERF
    half = N_BOARDS * pitch / 2
    return [LINE_Z - half + k * pitch for k in range(N_BOARDS + 1)]


# --- Cant transfer, stop, turner ----------------------------------------------------------

def build_transfer(bm):
    z0, z1 = XFER_Z
    yc = XFER_TOP_Y - XFER_SPROCKET_R
    for x in XFER_X:
        # Chain bed rail and the return guide below it.
        gbox(bm, x - 0.04, x + 0.04, XFER_TOP_Y - 0.06, XFER_TOP_Y - 0.02, z0, z1, M["wear"])
        gbox(bm, x - 0.05, x + 0.05, XFER_TOP_Y - 0.2, XFER_TOP_Y - 0.06, z0, z1, M["frame"])
        for z in (z0 + 0.3, z1 - 0.3):
            gbox(bm, x - 0.05, x + 0.05, FLOOR, XFER_TOP_Y - 0.2, z - 0.05, z + 0.05, M["frame"])
    for z in (z0 + 0.3, z1 - 0.3):
        gbox(bm, XFER_X[0] - 0.05, XFER_X[-1] + 0.05, FLOOR + 0.3, FLOOR + 0.38, z - 0.04, z + 0.04, M["frame"])
    # Shaft bearings, gearmotor on the head shaft.
    for z in (z0, z1):
        for x in (XFER_X[0] - 0.2, XFER_X[-1] + 0.2):
            gbox(bm, x - 0.07, x + 0.07, yc - 0.08, yc + 0.08, z - 0.08, z + 0.08, M["dark"])
            gbox(bm, x - 0.05, x + 0.05, FLOOR, yc - 0.08, z - 0.05, z + 0.05, M["frame"])
    gbox(bm, XFER_X[-1] + 0.3, XFER_X[-1] + 0.7, FLOOR, yc + 0.15, z1 - 0.25, z1 + 0.15, M["motor"])
    cyl_x(bm, G(XFER_X[-1] + 0.95, yc + 0.0, z1 - 0.05), 0.13, 0.4, mat_index=M["motor"])
    # Cant stop plates beside each strand.
    for x in XFER_X:
        gbox(bm, x + 0.08, x + 0.2, FLOOR, 0.05, STOP_Z, STOP_Z + 0.04, M["frame"])
        gbox(bm, x + 0.08, x + 0.2, -0.25, 0.04, STOP_Z - 0.015, STOP_Z, M["rubber"])
    # Turner shaft bearings.
    pz, py = TURNER_PIVOT
    for x in (TURNER_X[0] - 0.35, TURNER_X[-1] + 0.35):
        gbox(bm, x - 0.07, x + 0.07, py - 0.08, py + 0.08, pz - 0.09, pz + 0.09, M["dark"])
        gbox(bm, x - 0.05, x + 0.05, FLOOR, py - 0.08, pz - 0.06, pz + 0.06, M["frame"])
    # Turner drive: hydraulic rotary actuator on the downstream end.
    cyl_x(bm, G(TURNER_X[-1] + 0.6, py, pz), 0.14, 0.3, mat_index=M["dark"])
    gbox(bm, TURNER_X[-1] + 0.45, TURNER_X[-1] + 0.75, FLOOR, py - 0.14, pz - 0.12, pz + 0.12, M["frame"])


def build_transfer_shafts(coll, mats):
    yc = XFER_TOP_Y - XFER_SPROCKET_R
    out = []
    for name, z in (("GR_TransferTail", XFER_Z[0]), ("GR_TransferHead", XFER_Z[1])):
        e = empty(name, coll, None, G((XFER_X[0] + XFER_X[-1]) / 2, yc, z), 0.1)
        bm = bmesh.new()
        L.add_cyl(bm, 0.035, XFER_X[-1] - XFER_X[0] + 0.5, L.mat(rot=(0, 90, 0)), segs=10, mat_index=M["dark"])
        for x in XFER_X:
            xo = x - (XFER_X[0] + XFER_X[-1]) / 2
            L.add_cyl(bm, XFER_SPROCKET_R + 0.012, 0.025, L.mat(loc=(xo, 0, 0), rot=(0, 90, 0)), segs=12,
                      mat_index=M["dark"])
        H.make(name + "Mesh", bm, coll, mats, e)
        out.append(e)
    return out


def build_turner(coll, mats):
    pz, py = TURNER_PIVOT
    xm = (TURNER_X[0] + TURNER_X[-1]) / 2
    piv = G(xm, py, pz)
    root = empty("GR_Turner", coll, None, piv, 0.2)
    bm = bmesh.new()
    cyl_x(bm, G(xm, py, pz) - piv, 0.05, TURNER_X[-1] - TURNER_X[0] + 1.0, mat_index=M["dark"])
    for x in TURNER_X:
        # Arm from the pivot back under the cant with an upturned hook on its far side.
        pts = [(pz + 0.08, py - 0.08), (pz + 0.1, py + 0.07), (pz - 0.62, py + 0.25), (pz - 0.86, py + 0.27),
               (pz - 0.9, py + 0.42), (pz - 0.97, py + 0.42), (pz - 0.95, py + 0.17), (pz - 0.6, py + 0.13),
               (pz - 0.05, py - 0.1)]
        plate_zy(bm, x, 0.05, pts, M["moving"], piv)
        cyl_x(bm, G(x, py, pz) - piv, 0.1, 0.12, mat_index=M["moving"])
    H.make("GR_TurnerMesh", bm, coll, mats, root)
    return root


# --- Sharp chain infeed and press rolls -----------------------------------------------------

def build_sharp_chain(bm):
    x0, x1 = SHARP_X
    z = LINE_Z
    y = SHARP_TOP_Y
    # Chain bed and side guides (the chain links are instanced by the game).
    gbox(bm, x0, x1, y - 0.07, y - 0.035, z - 0.05, z + 0.05, M["wear"])
    for s in (-1, 1):
        gbox(bm, x0, x1, y - 0.25, y - 0.035, z + s * 0.09 - 0.015, z + s * 0.09 + 0.015, M["frame"])
    gbox(bm, x0, x1, y - 0.35, y - 0.3, z - 0.1, z + 0.1, M["wear"])
    x = x0 + 0.3
    while x < x1:
        gbox(bm, x - 0.06, x + 0.06, FLOOR, y - 0.25, z - 0.08, z + 0.08, M["frame"])
        gbox(bm, x - 0.2, x + 0.2, FLOOR, FLOOR + 0.02, z - 0.2, z + 0.2, M["dark"])
        x += 1.5
    # Sprocket bearings at each end, drive motor on the head end (+Z side).
    for xe in (x0 + 0.15, x1 - 0.1):
        for s in (-1, 1):
            gbox(bm, xe - 0.08, xe + 0.08, y - 0.27, y - 0.11, z + s * 0.16 - 0.04, z + s * 0.16 + 0.04, M["dark"])
    gbox(bm, x1 - 0.6, x1 - 0.1, FLOOR, y - 0.2, z + 0.25, z + 0.7, M["motor"])
    cyl_y(bm, G(x1 - 0.35, y - 0.42, z + 0.9), 0.16, 0.4, mat_index=M["motor"])
    # Press roll arm stands: posts on the far side carrying the arm pivots.
    for px, py in PRESS:
        gbox(bm, px - 0.08, px + 0.08, FLOOR, py + 0.1, z + 0.45, z + 0.6, M["frame"])
        gbox(bm, px - 0.06, px + 0.06, py - 0.06, py + 0.06, z + 0.2, z + 0.45, M["dark"])
        # Air cylinder from the post top down onto the arm.
        cyl_y(bm, G(px + 0.25, py + 0.32, z + 0.33), 0.06, 0.1, mat_index=M["dark"])
        beam(bm, (px + 0.1, py + 0.3, z + 0.48), (px + 0.25, py + 0.32, z + 0.33), 0.06, 0.06, M["frame"])


def build_press(coll, mats):
    out = []
    for i, (px, py) in enumerate(PRESS):
        piv = G(px, py, LINE_Z + 0.32)
        root = empty("GR_Press%d" % (i + 1), coll, None, piv, 0.12)
        bm = bmesh.new()
        cyl_y(bm, G(px, py, LINE_Z + 0.32) - piv, 0.05, 0.2, mat_index=M["dark"])
        ry = py - 0.32           # arm drops 0.32 to the roll axis at rest (raised)
        for zz in (LINE_Z + 0.22, LINE_Z - 0.22):
            beam(bm, (px, py, zz), (px + PRESS_ARM, ry, zz), 0.05, 0.08, M["moving"], piv)
        beam(bm, (px, py, LINE_Z + 0.22), (px, py, LINE_Z - 0.22), 0.06, 0.06, M["moving"], piv)
        H.make("GR_Press%dMesh" % (i + 1), bm, coll, mats, root)
        roll = empty("GR_PressRoll%d" % (i + 1), coll, root, G(px + PRESS_ARM, ry, LINE_Z), 0.08)
        rb = bmesh.new()
        L.add_cyl(rb, PRESS_R, 0.36, L.mat(rot=(90, 0, 0)), segs=20, mat_index=M["wear"])
        for k in range(10):
            L.add_box(rb, (0.02, 0.36, 0.02), Matrix.Rotation(k * math.tau / 10, 4, 'Y') @
                      Matrix.Translation((0, 0, PRESS_R)), M["wear"])
        L.add_cyl(rb, 0.03, 0.5, L.mat(rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
        H.make("GR_PressRoll%dMesh" % (i + 1), rb, coll, mats, roll)
        out.append(root)
    return out


# --- Gang -----------------------------------------------------------------------------------

def bottom_arbor_y():
    return SHARP_TOP_Y + CANT_H * 0.55 - SAW_R


def top_arbor_y():
    return SHARP_TOP_Y + CANT_H * 0.45 + SAW_R


def build_gang(bm):
    x0, x1 = HOUSING_X
    z0, z1 = HOUSING_Z
    top = top_arbor_y() + SAW_R + 0.12
    bot = FLOOR
    win_lo, win_hi = SHARP_TOP_Y - 0.05, SHARP_TOP_Y + CANT_H + 0.08
    wz0, wz1 = LINE_Z - 0.3, LINE_Z + 0.3
    # Side walls, roof, and end walls with the feed windows.
    gbox(bm, x0, x1, bot, top, z0, z0 + 0.03, M["mill"])
    gbox(bm, x0, x1, bot, top, z1 - 0.03, z1, M["mill"])
    gbox(bm, x0 - 0.03, x1 + 0.03, top, top + 0.04, z0 - 0.03, z1 + 0.03, M["mill"])
    for x in (x0, x1 - 0.03):
        gbox(bm, x, x + 0.03, bot, win_lo, z0, z1, M["mill"])
        gbox(bm, x, x + 0.03, win_hi, top, z0, z1, M["mill"])
        gbox(bm, x, x + 0.03, win_lo, win_hi, z0, wz0, M["mill"])
        gbox(bm, x, x + 0.03, win_lo, win_hi, wz1, z1, M["mill"])
    # Rubber kickback curtain at the infeed window.
    for k in range(6):
        z = wz0 + 0.05 + k * (wz1 - wz0 - 0.1) / 5
        gbox(bm, x0 - 0.02, x0 - 0.01, win_lo + 0.12, win_hi, z - 0.045, z + 0.045, M["rubber"])
    # Base and access door with handles on the near side.
    gbox(bm, x0 - 0.1, x1 + 0.1, bot, bot + 0.1, z0 - 0.1, z1 + 0.1, M["dark"])
    gbox(bm, x0 + 0.25, x1 - 0.25, win_hi + 0.05, top - 0.08, z0 - 0.02, z0, M["dark"])
    for y in (win_hi + 0.15, top - 0.2):
        gbox(bm, x1 - 0.32, x1 - 0.28, y - 0.03, y + 0.03, z0 - 0.06, z0 - 0.02, M["chrome"])
    # Arbor bearings, sheaves and belt guards on the far side out to two motors.
    for ay in (top_arbor_y(), bottom_arbor_y()):
        for zz in (z0 - 0.08, z1 + 0.08):
            gbox(bm, SAW_X - 0.15, SAW_X + 0.15, ay - 0.13, ay + 0.13, zz - 0.08, zz + 0.08, M["dark"])
    mz0, mz1 = z1 + 0.55, z1 + 1.75
    for k, ay in enumerate((top_arbor_y(), bottom_arbor_y())):
        my = FLOOR + 0.45 + k * 0.0
        mx = SAW_X - 0.55 + 1.1 * k
        gz = z1 + 0.3 + 0.18 * k
        L.add_prism(bm, [(SAW_X - 0.22, ay - 0.22 - FLOOR), (mx + 0.25, my - 0.25 - FLOOR),
                         (mx + 0.25, my + 0.25 - FLOOR), (SAW_X + 0.22, ay + 0.22 - FLOOR)],
                    -(gz + 0.07), -(gz - 0.07), None, M["moving"])
        gbox(bm, mx - 0.4, mx + 0.4, FLOOR, FLOOR + 0.1, mz0 - 0.05, mz1, M["dark"])
        cyl_y(bm, G(mx, my, (mz0 + mz1) / 2), 0.33, mz1 - mz0 - 0.1, segs=24, mat_index=M["motor"])
        for j in range(8):
            cyl_y(bm, G(mx, my, mz0 + 0.12 + j * (mz1 - mz0 - 0.3) / 7), 0.355, 0.025, segs=24, mat_index=M["motor"])
        gbox(bm, mx - 0.12, mx + 0.12, my + 0.3, my + 0.48, mz1 - 0.5, mz1 - 0.25, M["motor"])
    # Chip head spindle motors standing on the roof.
    for s in (-1, 1):
        zc = LINE_Z + s * (CANT_H * 0.0 + chip_offset())
        cyl_z(bm, G(CHIP_X, top + 0.32, zc), 0.17, 0.55, segs=20, mat_index=M["motor"])
        cyl_z(bm, G(CHIP_X, top + 0.03, zc), 0.12, 0.06, segs=20, mat_index=M["dark"])
    # Chip duct: from the hood up, across to z 12 and along to the big chipper's blow pipe by the
    # east wall (waste system), joining it from above.
    hx, hz = CHIP_X + 0.55, LINE_Z
    cyl_z(bm, G(hx, (top + DUCT_Y) / 2, hz), DUCT_R, DUCT_Y - top, segs=16, mat_index=M["wear"])
    for p in ((hx, DUCT_Y, hz), (hx, DUCT_Y, PIPE_Z)):
        L.add_sphere(bm, DUCT_R * 1.1, Matrix.Translation(G(*p)), segs=16, rings=8, mat_index=M["wear"])
    cyl_y(bm, G(hx, DUCT_Y, (hz + PIPE_Z) / 2), DUCT_R, abs(PIPE_Z - hz), segs=16, mat_index=M["wear"])
    cyl_x(bm, G((hx + PIPE_X) / 2, DUCT_Y, PIPE_Z), DUCT_R, PIPE_X - hx, segs=16, mat_index=M["wear"])
    for x in range(int(hx) + 2, int(PIPE_X), 3):
        gbox(bm, x - 0.02, x + 0.02, DUCT_Y + DUCT_R, 7.4, PIPE_Z - 0.02, PIPE_Z + 0.02, M["dark"])


def chip_offset():
    """Chip head spindle distance from the line: heads (radius 0.16) cut to the outer kerfs."""
    return saw_zs()[-1] - LINE_Z + 0.16


def build_arbors(coll, mats):
    out = []
    for name, ay in (("GR_TopArbor", top_arbor_y()), ("GR_BottomArbor", bottom_arbor_y())):
        e = empty(name, coll, None, G(SAW_X, ay, LINE_Z), 0.15)
        bm = bmesh.new()
        L.add_cyl(bm, 0.05, HOUSING_Z[1] - HOUSING_Z[0] + 0.5, L.mat(rot=(90, 0, 0)), segs=12, mat_index=M["chrome"])
        for z in saw_zs()[1:-1]:
            zo = -(z - LINE_Z)                   # Blender Y = -Godot Z
            L.add_cyl(bm, SAW_R, 0.004, L.mat(loc=(0, zo, 0), rot=(90, 0, 0)), segs=40, mat_index=M["blade"])
            L.add_cyl(bm, 0.12, 0.03, L.mat(loc=(0, zo, 0), rot=(90, 0, 0)), segs=20, mat_index=M["dark"])
            for k in range(24):
                L.add_box(bm, (0.03, 0.008, 0.02), Matrix.Rotation(k * math.tau / 24, 4, 'Y') @
                          Matrix.Translation((0, zo, SAW_R)), M["chrome"])
        H.make(name + "Mesh", bm, coll, mats, e)
        out.append(e)
    for name, s in (("GR_ChipHeadNear", -1), ("GR_ChipHeadFar", 1)):
        zc = LINE_Z + s * chip_offset()
        e = empty(name, coll, None, G(CHIP_X, SHARP_TOP_Y + CANT_H / 2, zc), 0.12)
        bm = bmesh.new()
        L.add_cyl(bm, 0.16, CANT_H + 0.04, None, segs=24, mat_index=M["dark"])
        for k in range(8):
            L.add_box(bm, (0.04, 0.012, CANT_H + 0.02), Matrix.Rotation(k * math.tau / 8, 4, 'Z') @
                      Matrix.Translation((0.16, 0, 0)), M["chrome"])
        L.add_cyl(bm, 0.04, 0.9, L.mat(loc=(0, 0, 0.35)), segs=10, mat_index=M["chrome"])
        H.make(name + "Mesh", bm, coll, mats, e)
        out.append(e)
    return out


# --- Outfeed lift rolls ---------------------------------------------------------------------

def build_outfeed(bm):
    x0, x1 = OUT_X
    z = LINE_Z
    base = OUT_TOP_Y - OUT_ROLL_R - 0.25 - LIFT_DROP
    # Fixed base under the lift frame, its two lift cylinders and the end stop.
    for s in (-1, 1):
        gbox(bm, x0, x1, base - 0.06, base, z + s * 0.4 - 0.04, z + s * 0.4 + 0.04, M["frame"])
    for xx in (x0 + 0.4, (x0 + x1) / 2, x1 - 0.4):
        for s in (-1, 1):
            gbox(bm, xx - 0.05, xx + 0.05, FLOOR, base - 0.06, z + s * 0.4 - 0.05, z + s * 0.4 + 0.05, M["frame"])
    for xx in (x0 + 1.2, x1 - 1.2):
        cyl_z(bm, G(xx, base + 0.08, z), 0.07, 0.16, mat_index=M["dark"])
    gbox(bm, OUT_STOP_X, OUT_STOP_X + 0.08, FLOOR, OUT_TOP_Y + 0.4, z - 0.35, z + 0.35, M["frame"])
    gbox(bm, OUT_STOP_X - 0.04, OUT_STOP_X, OUT_TOP_Y - 0.2, OUT_TOP_Y + 0.36, z - 0.3, z + 0.3, M["rubber"])
    for s in (-1, 1):
        beam(bm, (OUT_STOP_X + 0.06, OUT_TOP_Y + 0.3, z + s * 0.3), (OUT_STOP_X + 0.8, FLOOR, z + s * 0.3), 0.08, 0.08,
             M["frame"])
    # Board guides each side of the outfeed while the boards stand on edge.
    for s in (-1, 1):
        gbox(bm, x0, x0 + 1.4, OUT_TOP_Y + 0.05, OUT_TOP_Y + 0.25, z + s * 0.32 - 0.015, z + s * 0.32 + 0.015,
             M["wear"])


def build_lift(coll, mats):
    x0, x1 = OUT_X
    z = LINE_Z
    yc = OUT_TOP_Y - OUT_ROLL_R
    piv = G((x0 + x1) / 2, yc, z)
    root = empty("GR_Lift", coll, None, piv, 0.2)
    bm = bmesh.new()
    for s in (-1, 1):
        gbox(bm, x0, x1, yc - 0.2, yc - 0.04, z + s * 0.34 - 0.04, z + s * 0.34 + 0.04, M["frame"], piv)
    gbox(bm, x0, x1, yc - 0.26, yc - 0.2, z - 0.38, z + 0.38, M["frame"], piv)
    # Line shaft drive along the far side.
    cyl_x(bm, G((x0 + x1) / 2, yc - 0.12, z + 0.44) - piv, 0.03, x1 - x0, mat_index=M["dark"])
    gbox(bm, x1 - 0.5, x1 - 0.05, yc - 0.35, yc - 0.05, z + 0.48, z + 0.8, M["motor"], piv)
    H.make("GR_LiftMesh", bm, coll, mats, root)
    for i, x in enumerate(OUT_ROLL_X):
        r = empty("GR_ORoll%d" % (i + 1), coll, root, G(x, yc, z), 0.08)
        rb = bmesh.new()
        L.add_cyl(rb, OUT_ROLL_R, 0.6, L.mat(rot=(90, 0, 0)), segs=18, mat_index=M["wear"])
        L.add_cyl(rb, 0.025, 0.86, L.mat(loc=(0, -0.13, 0), rot=(90, 0, 0)), segs=8, mat_index=M["dark"])
        H.make("GR_ORoll%dMesh" % (i + 1), rb, coll, mats, r)
    return root


def pose(turner_deg=0.0, press_deg=0.0, lift=0.0):
    """Turner swing (deg), press arms down (deg), lift frame down (m)."""
    bpy.data.objects["GR_Turner"].rotation_euler = (math.radians(turner_deg), 0, 0)
    for i in range(len(PRESS)):
        bpy.data.objects["GR_Press%d" % (i + 1)].rotation_euler = (0, -math.radians(press_deg), 0)
    lf = bpy.data.objects["GR_Lift"]
    lf.location.z = OUT_TOP_Y - OUT_ROLL_R - FLOOR - lift


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = H.build_materials()
    frame = empty("GR_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_transfer(bm)
    build_sharp_chain(bm)
    build_gang(bm)
    build_outfeed(bm)
    H.make("GR_FrameMesh", bm, coll, mats, frame)
    build_transfer_shafts(coll, mats)
    build_turner(coll, mats)
    build_press(coll, mats)
    build_arbors(coll, mats)
    build_lift(coll, mats)
    pose()
    return {"objects": len(coll.all_objects), "saws": len(saw_zs()) - 2, "chip_offset": chip_offset(),
            "arbors_y": (top_arbor_y(), bottom_arbor_y())}
