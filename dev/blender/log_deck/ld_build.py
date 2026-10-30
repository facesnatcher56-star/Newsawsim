"""Debarker infeed log deck with a step feeder (run inside Blender).

A live chain log deck in the style of USNR / Nicholson debarker infeed decks, sized for the
mill's 0.58 m (23 in) by 4.92 m logs:
  - 7 m live deck on a 3 deg slope down to the feeder: four strands of welded drag chain
    with dog links, riding in wear-strip troughs on W-beam stringers; head shaft with
    the drive at the feeder end, take-up tail shaft at the loader end, log end guards
  - four-stroke step feeder (log ladder): five fixed stepped plates with moving stepped
    plates between them. Every stroke the moving plates lift every log one step and it
    rolls forward onto the next fixed tread; the top tread hands onto the debarker
    infeed's dump skids. Four vertical hydraulic cylinders and guide posts lift the
    moving frame.
  - service side: shaft-mounted drive, hydraulic power unit, catwalk with stairs

Built in the game deck's own frame (Godot root of LiveLogDeck), with the floor at z = 0:
Godot (x, y, z) = Blender (x, -y, z - 1.288) the other way round, i.e. G() below. The deck
on the other side of the infeed is the same deck turned 180 deg about the infeed line.

  LD_Frame        frame, fixed plates, cylinder barrels; LD_Bed (tilted deck frame) >
                  LD_HeadShaft, LD_TailShaft (spin about local X)
  LD_MovingSteps  moving plates, lift tubes, cylinder rods (moves straight up STEP_LIFT)
  LD_Drive        gearbox and motor on the head shaft end, HPU (service side, +X)
  LD_Catwalk      catwalk and stairs (service side, +X)
  LD_ChainLink / LD_ChainDog   one chain pitch each, for the game to instance round the loop
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

COLL = "LogDeck"

FLOOR = -1.288
LOG_R = 0.292
LOG_LEN = 4.92
# Log centre line across the deck (Godot x) and the debarker infeed line (Godot z).
C = -0.823
LINE_Z = 2.118
LINE_Y = 0.872
# Top edge of the debarker infeed's dump skid on this side.
SKID_Z = 2.978
SKID_Y = 1.472

# Step feeder: riser k at Godot z A[k]; tread k runs from A[k] (back, height T[k]) down at
# TREAD_SLOPE to A[k+1] (front, height CN[k]), where the log rests against the next riser.
TREAD = 0.65
TREAD_SLOPE = math.tan(math.radians(4.0))
RISER = 0.37            # riser height above the log's resting point
STEP_LIFT = 0.45        # moving plate stroke
A = [None, 5.38, 4.73, 4.08, 3.43]
T = [None, 0.0, 0.0, 0.0, SKID_Y + (A[4] - SKID_Z) * math.tan(math.radians(4.0))]
CN = [0.0] * 4
CN[3] = T[4] - RISER
for _k in (3, 2, 1):
    T[_k] = CN[_k] + TREAD * TREAD_SLOPE
    CN[_k - 1] = T[_k] - RISER

# Deck bed: origin at the riser foot (C, CN[0], A[1]), tilted so local +Z runs up-slope.
SLOPE_DEG = 3.0
BED_LEN = 7.0
BED_HALF_W = 3.0
STRANDS = (-1.375, -0.275, 0.275, 1.375)
CHAIN_Y = -0.02         # chain link centre below the bed surface (log contact at 0)
SPROCKET_R = 0.25
HEAD_Z = 0.30
TAIL_Z = 6.70
SHAFT_Y = CHAIN_Y - SPROCKET_R
FIXED_X = (-2.2, -1.1, 0.0, 1.1, 2.2)
MOVING_X = (-1.65, -0.55, 0.55, 1.65)
PLATE_T = 0.05
# Moving frame lift tubes (Godot z, down-pose centre height) and the cylinders under them.
TUBE_L = (4.98, -0.40)
TUBE_H = (3.98, -0.02)
CYL_X = (-1.65, 1.65)
GUIDE_X = 2.45
# Catwalk on the service side.
WALK_X = (3.95, 4.75)
WALK_Y = -0.05
WALK_Z = (3.6, 12.3)


def G(x, y, z):
    """Godot root-local point to Blender."""
    return Vector((x, -z, y - FLOOR))


def B(x, y, z):
    """Deck-bed-local point (x across, y up off the bed, z up-slope) to LD_Bed space."""
    return Vector((x, -z, y))


def bed_to_godot(x, y, z):
    a = math.radians(-SLOPE_DEG)
    return (C + x, CN[0] + y * math.cos(a) - z * math.sin(a), A[1] + y * math.sin(a) + z * math.cos(a))


def GB(x, y, z):
    """Deck-bed-local point to Blender world (for parts outside LD_Bed)."""
    return G(*bed_to_godot(x, y, z))


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


def _span_box(bm, a, b, mat_index):
    lo = Vector((min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)))
    hi = Vector((max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
    box(bm, (lo + hi) / 2, (hi - lo), mat_index)


def gbox(bm, x0, x1, y0, y1, z0, z1, mat_index=0):
    """Axis-aligned box between Godot coordinates."""
    _span_box(bm, G(x0, y0, z0), G(x1, y1, z1), mat_index)


def bbox(bm, x0, x1, y0, y1, z0, z1, mat_index=0):
    """Axis-aligned box between deck-bed coordinates (LD_Bed space)."""
    _span_box(bm, B(x0, y0, z0), B(x1, y1, z1), mat_index)


def plate(bm, x, thick, zy, mat_index=0):
    """Vertical plate at Godot x, outline given as Godot (z, y) points."""
    m = Matrix(((0, 1, 0, x), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
    pts = [(-z, y - FLOOR) for z, y in zy]
    L.add_prism(bm, pts, -thick / 2, thick / 2, m, mat_index)


def strip(bm, x, w, p0, p1, thick, mat_index):
    """Wear strip on a plate edge between Godot (z, y) points, lying on top of it."""
    a, b = G(x, p0[1], p0[0]), G(x, p1[1], p1[0])
    m, length = L.frame_between(a, b)
    L.add_box(bm, (length, w, thick), m @ Matrix.Translation((0, 0, thick / 2)), mat_index)


def cyl_x(bm, centre, r, length, segs=20, mat_index=0):
    L.add_cyl(bm, r, length, Matrix.Translation(centre) @ L.mat(rot=(0, 90, 0)), segs=segs, mat_index=mat_index)


def cyl_z(bm, centre, r, length, segs=20, mat_index=0, r2=None):
    L.add_cyl(bm, r, length, Matrix.Translation(centre), segs=segs, r2=r2, mat_index=mat_index)


def build_materials():
    frame = ((0.05, 0.11, 0.16), (0.09, 0.18, 0.25), (0.15, 0.26, 0.33))
    yellow = ((0.42, 0.26, 0.012), (0.62, 0.40, 0.02), (0.78, 0.55, 0.08))
    return {
        "frame": ML.painted_steel("LD_Frame", *frame, chip_amount=0.55, dirt_height=1.2),
        "moving": ML.painted_steel("LD_Moving", *yellow, chip_amount=0.7, dirt_height=1.0),
        "wear": ML.simple("LD_Wear", (0.24, 0.235, 0.225), 0.38, 0.9, 50, 0.05),
        "chain": ML.simple("LD_Chain", (0.06, 0.055, 0.05), 0.5, 0.8, 40, 0.1),
        "dark": ML.painted_steel("LD_Dark", (0.02, 0.02, 0.02), (0.04, 0.04, 0.04), (0.07, 0.07, 0.065),
                                 chip_amount=0.8, dirt_height=1.5),
        "chrome": ML.simple("LD_Chrome", (0.75, 0.75, 0.74), 0.08, 1.0),
        "motor": ML.painted_steel("LD_Motor", (0.03, 0.06, 0.12), (0.05, 0.10, 0.20), (0.09, 0.15, 0.27),
                                  chip_amount=0.4, dirt_height=0.5),
        "rail": ML.painted_steel("LD_Rail", *yellow, chip_amount=0.3, dirt_height=0.6),
        "grate": ML.simple("LD_Grate", (0.11, 0.11, 0.105), 0.6, 0.7, 120, 0.4),
        "red": ML.simple("LD_Red", (0.5, 0.03, 0.02), 0.5, 0.0),
    }


VIEWPORT = {
    "LD_Frame": ((0.09, 0.18, 0.25), 0.3, 0.55),
    "LD_Moving": ((0.62, 0.40, 0.02), 0.2, 0.55),
    "LD_Wear": ((0.30, 0.295, 0.285), 0.45, 0.42),
    "LD_Chain": ((0.07, 0.065, 0.06), 0.55, 0.5),
    "LD_Dark": ((0.04, 0.04, 0.04), 0.5, 0.5),
    "LD_Chrome": ((0.78, 0.78, 0.77), 1.0, 0.08),
    "LD_Motor": ((0.05, 0.10, 0.20), 0.4, 0.5),
    "LD_Rail": ((0.70, 0.48, 0.04), 0.2, 0.5),
    "LD_Grate": ((0.12, 0.12, 0.115), 0.4, 0.65),
    "LD_Red": ((0.5, 0.03, 0.02), 0.0, 0.5),
}


# --- Deck bed ------------------------------------------------------------------------

def sprocket(bm, x, teeth=12, mat_index=0):
    """Toothed sprocket in the bed's YZ plane at bed x, centred on the shaft origin."""
    L.add_cyl(bm, SPROCKET_R - 0.025, 0.045, L.mat((x, 0, 0), (0, 90, 0)), segs=36, mat_index=mat_index)
    L.add_cyl(bm, 0.09, 0.12, L.mat((x, 0, 0), (0, 90, 0)), segs=20, mat_index=mat_index)
    for k in range(teeth):
        a = 2 * math.pi * k / teeth
        c = Vector((0, math.cos(a), math.sin(a))) * (SPROCKET_R - 0.005)
        m = Matrix.Translation(c + Vector((x, 0, 0))) @ L.mat(rot=(math.degrees(a) - 90, 0, 0))
        L.add_box(bm, (0.04, 0.05, 0.06), m, mat_index)


def build_shaft(name, coll, mats, parent, z, with_drive_hub):
    root = empty(name, coll, parent, B(0, SHAFT_Y, z), 0.3)
    bm = bmesh.new()
    cyl_x(bm, Vector((0, 0, 0)), 0.05, 2 * BED_HALF_W + 0.55, segs=20, mat_index=1)
    for x in STRANDS:
        sprocket(bm, x, mat_index=0)
    if with_drive_hub:
        cyl_x(bm, Vector((BED_HALF_W + 0.42, 0, 0)), 0.07, 0.12, mat_index=1)
    L.make_object(name + "Mesh", bm, coll, (mats["wear"], mats["dark"]), parent=root)
    return root


def build_bed(coll, mats, parent):
    a = math.radians(-SLOPE_DEG)
    bed = empty("LD_Bed", coll, parent, G(C, CN[0], A[1]), 0.5)
    bed.rotation_euler = (a, 0, 0)
    F, W, D, R = 0, 1, 2, 3
    bm = bmesh.new()
    z0, z1 = HEAD_Z + SPROCKET_R + 0.05, TAIL_Z - SPROCKET_R - 0.05
    for x in STRANDS:
        # Wear-strip trough the chain rides in.
        bbox(bm, x - 0.08, x + 0.08, -0.058, -0.046, z0, z1, W)
        for s in (-1, 1):
            bbox(bm, x + s * 0.074 - 0.006, x + s * 0.074 + 0.006, -0.058, -0.008, z0, z1, W)
        # W-beam stringer under it.
        bbox(bm, x - 0.075, x + 0.075, -0.072, -0.058, z0, z1, F)
        bbox(bm, x - 0.006, x + 0.006, -0.29, -0.072, z0, z1, F)
        bbox(bm, x - 0.075, x + 0.075, -0.304, -0.29, z0, z1, F)
        # Return-run shoes on the cross beams.
    cross = (0.95, 2.35, 3.75, 5.15, 6.25)
    for z in cross:
        # C-channel cross beam below the chain return run.
        bbox(bm, -BED_HALF_W, BED_HALF_W, -0.64, -0.62, z - 0.05, z + 0.05, F)
        bbox(bm, -BED_HALF_W, BED_HALF_W, -0.87, -0.64, z - 0.05, z - 0.038, F)
        bbox(bm, -BED_HALF_W, BED_HALF_W, -0.87, -0.85, z - 0.05, z + 0.05, F)
        for x in STRANDS:
            for s in (-1, 1):
                bbox(bm, x + s * 0.11 - 0.035, x + s * 0.11 + 0.035, -0.62, -0.304, z - 0.035, z + 0.035, F)
            bbox(bm, x - 0.06, x + 0.06, -0.62, -0.60, z - 0.08, z + 0.08, W)
    # Edge beams with the bearing brackets and the log end guards.
    for s in (-1, 1):
        x = s * BED_HALF_W
        bbox(bm, x - 0.04, x + 0.04, -0.62, -0.10, 0.05, BED_LEN - 0.05, F)
        bbox(bm, x - 0.08, x + 0.08, -0.12, -0.10, 0.05, BED_LEN - 0.05, F)
        bbox(bm, x - 0.08, x + 0.08, -0.64, -0.62, 0.05, BED_LEN - 0.05, F)
        for z in (HEAD_Z, TAIL_Z):
            # Pillow block on a bracket outboard of the edge beam.
            bbox(bm, x + s * 0.04, x + s * 0.32, SHAFT_Y - 0.12, SHAFT_Y - 0.09, z - 0.16, z + 0.16, F)
            bbox(bm, x + s * 0.10, x + s * 0.26, SHAFT_Y - 0.09, SHAFT_Y + 0.06, z - 0.12, z + 0.12, D)
            L.add_cyl(bm, 0.075, 0.13, L.mat(B(x + s * 0.18, SHAFT_Y, z), (0, 90, 0)), segs=20, mat_index=D)
        # Screw take-up on the tail bearing.
        L.add_cyl(bm, 0.022, 0.5, L.mat(B(x + s * 0.18, SHAFT_Y - 0.03, TAIL_Z + 0.35), (90, 0, 0)), segs=10,
                  mat_index=W)
        # Guard posts and rail at the log ends.
        for z in (0.35, 1.75, 3.15, 4.55, 5.95, 6.9):
            bbox(bm, x + s * 0.02 - 0.04, x + s * 0.02 + 0.04, -0.10, 0.34, z - 0.04, z + 0.04, R)
        bbox(bm, x + s * 0.02 - 0.05, x + s * 0.02 + 0.05, 0.28, 0.34, 0.31, 6.94, R)
        bbox(bm, x + s * 0.02 - 0.006, x + s * 0.02 + 0.006, 0.0, 0.16, 0.31, 6.94, R)
    # Tail end plate.
    bbox(bm, -BED_HALF_W, BED_HALF_W, -0.62, -0.30, BED_LEN - 0.06, BED_LEN, F)
    L.make_object("LD_BedMesh", bm, coll, (mats["frame"], mats["wear"], mats["dark"], mats["rail"]), parent=bed)
    build_shaft("LD_HeadShaft", coll, mats, bed, HEAD_Z, True)
    build_shaft("LD_TailShaft", coll, mats, bed, TAIL_Z, False)
    return bed


def build_bed_legs(coll, mats, parent):
    bm = bmesh.new()
    for z in (0.95, 2.35, 3.75, 5.15, 6.25):
        for x in (-2.4, 0.0, 2.4):
            top = Vector(bed_to_godot(x, -0.87, z))
            gx, gy, gz = top
            gbox(bm, gx - 0.1, gx + 0.1, FLOOR + 0.02, gy, gz - 0.006, gz + 0.006, 0)
            for s in (-1, 1):
                gbox(bm, gx - 0.1, gx + 0.1, FLOOR + 0.02, gy, gz + s * 0.1 - 0.008, gz + s * 0.1 + 0.008, 0)
            gbox(bm, gx - 0.2, gx + 0.2, FLOOR, FLOOR + 0.025, gz - 0.2, gz + 0.2, 0)
    # Knee braces along the outer leg lines.
    for x in (-2.4, 2.4):
        for za, zb in ((0.95, 2.35), (3.75, 5.15)):
            pa = Vector(bed_to_godot(x, -0.87, za))
            pb = Vector(bed_to_godot(x, -0.87, zb))
            L.add_beam(bm, G(pa.x, FLOOR + 0.35, pa.z), G(pb.x, pb.y - 0.05, pb.z), 0.08, 0.08, mat_index=0)
    return L.make_object("LD_BedLegs", bm, coll, (mats["frame"],), parent=parent)


# --- Step feeder ---------------------------------------------------------------------

def fixed_band():
    """Outline of a fixed stepped plate's band (Godot z, y)."""
    top = [(A[1], T[1]), (A[2], CN[1]), (A[2], T[2]), (A[3], CN[2]), (A[3], T[3]), (A[4], CN[3]),
           (A[4], T[4]), (SKID_Z + 0.02, SKID_Y)]
    return top + [(SKID_Z + 0.02, 1.17), (A[1], 0.23)]


def moving_outline(lift=0.0):
    """Outline of a moving stepped plate in the down pose (Godot z, y)."""
    h = lambda y: y + lift  # noqa: E731
    deck_rise = TREAD * math.tan(math.radians(SLOPE_DEG))
    pts = [(A[1] + TREAD, h(CN[0] - 0.06 + deck_rise)), (A[1] + 0.02, h(CN[0] - 0.06))]
    for k in (1, 2, 3):
        pts += [(A[k] + 0.02, h(T[k] - 0.05)), (A[k + 1] + 0.02, h(CN[k] - 0.05))]
    front = A[4] + 0.02
    back = A[1] + 0.08
    slope = 0.373
    pts += [(front, h(CN[3] - 0.95)), (back, h(CN[3] - 0.95 - (back - front) * slope)),
            (back, h(0.01)), (A[1] + TREAD, h(0.01 + deck_rise))]
    return pts


def build_feeder(coll, mats, parent):
    F, W, D = 0, 1, 2
    bm = bmesh.new()
    for x in FIXED_X:
        gx = C + x
        plate(bm, gx, PLATE_T, fixed_band(), F)
        # Back leg under riser 1, front leg under the top tread.
        plate(bm, gx, PLATE_T, [(A[1], 0.30), (A[1] - 0.12, 0.30), (A[1] - 0.12, FLOOR + 0.12), (A[1], FLOOR + 0.12)], F)
        plate(bm, gx, PLATE_T, [(3.14, 1.25), (3.0, 1.25), (3.0, FLOOR + 0.12), (3.14, FLOOR + 0.12)], F)
        # Stiffener flanges down the legs.
        gbox(bm, gx - 0.07, gx + 0.07, FLOOR + 0.12, 0.25, A[1] - 0.13, A[1] - 0.11, F)
        gbox(bm, gx - 0.07, gx + 0.07, FLOOR + 0.12, 1.2, 2.99, 3.01, F)
        # Hardened wear bars on every tread.
        for k in (1, 2, 3):
            strip(bm, gx, 0.07, (A[k] - 0.01, T[k]), (A[k + 1] + 0.005, CN[k]), 0.018, W)
        strip(bm, gx, 0.07, (A[4] - 0.01, T[4]), (SKID_Z + 0.03, SKID_Y), 0.018, W)
        # Riser faces.
        for k in (2, 3, 4):
            gbox(bm, gx - 0.035, gx + 0.035, CN[k - 1], T[k] - 0.005, A[k] - 0.012, A[k] + 0.004, W)
    # Base beams on the floor and the ties through the fixed plates.
    span = (C - 2.55, C + 2.55)
    for z in (A[1] - 0.06, 3.07):
        gbox(bm, span[0], span[1], FLOOR, FLOOR + 0.12, z - 0.12, z + 0.12, F)
    gbox(bm, span[0] + 0.1, span[1] - 0.1, -0.83, -0.67, A[1] - 0.14, A[1] - 0.02, F)
    gbox(bm, span[0] + 0.1, span[1] - 0.1, 0.42, 0.58, 3.0, 3.14, F)
    gbox(bm, span[0] + 0.1, span[1] - 0.1, -0.3, -0.14, 3.0, 3.14, F)
    # Guide posts for the lift tubes, outboard of the plates.
    for s in (-1, 1):
        gx = C + s * GUIDE_X
        for z, y in (TUBE_L, TUBE_H):
            top = y + STEP_LIFT + 0.25
            gbox(bm, gx - 0.07, gx + 0.07, FLOOR, top, z - 0.17, z - 0.15, F)
            gbox(bm, gx - 0.07, gx + 0.07, FLOOR, top, z + 0.15, z + 0.17, F)
            gbox(bm, gx - 0.006, gx + 0.006, FLOOR, top, z - 0.15, z + 0.15, F)
            gbox(bm, gx - 0.2, gx + 0.2, FLOOR, FLOOR + 0.025, z - 0.25, z + 0.25, F)
        # Longitudinal floor beam tying the posts to the base beams.
        gbox(bm, gx - 0.06, gx + 0.06, FLOOR, FLOOR + 0.12, 3.07, A[1] - 0.06, F)
    # Cylinder barrels on floor pads.
    for x in CYL_X:
        gx = C + x
        for z, y in (TUBE_L, TUBE_H):
            bottom = FLOOR + 0.09
            top = y - 0.08 - 0.17 if y < -0.2 else y - 0.08 - 0.20
            gbox(bm, gx - 0.17, gx + 0.17, FLOOR, FLOOR + 0.03, z - 0.17, z + 0.17, F)
            gbox(bm, gx - 0.05, gx + 0.05, FLOOR + 0.03, FLOOR + 0.12, z - 0.06, z + 0.06, D)
            cyl_z(bm, G(gx, (bottom + top) / 2, z), 0.075, top - bottom, mat_index=D)
            cyl_z(bm, G(gx, top - 0.03, z), 0.088, 0.06, mat_index=D)
            cyl_z(bm, G(gx, bottom + 0.05, z), 0.088, 0.08, mat_index=D)
            # Hose fittings.
            cyl_x(bm, G(gx + 0.09, top - 0.08, z), 0.018, 0.06, segs=8, mat_index=W)
            cyl_x(bm, G(gx + 0.09, bottom + 0.1, z), 0.018, 0.06, segs=8, mat_index=W)
    return L.make_object("LD_Feeder", bm, coll, (mats["frame"], mats["wear"], mats["dark"]), parent=parent)


def build_moving(coll, mats):
    root = empty("LD_MovingSteps", coll, None, (0, 0, 0), 0.4)
    M, W, CH, D = 0, 1, 2, 3
    bm = bmesh.new()
    for x in MOVING_X:
        gx = C + x
        plate(bm, gx, PLATE_T, moving_outline(), M)
        out = moving_outline()
        # Wear bars along each tooth top.
        for i in range(0, 8, 2):
            strip(bm, gx, 0.07, out[i], out[i + 1], 0.018, W)
    # Lift tubes carry every moving plate and run out to the guide posts.
    for z, y in (TUBE_L, TUBE_H):
        gbox(bm, C - GUIDE_X - 0.02, C + GUIDE_X + 0.02, y - 0.08, y + 0.08, z - 0.08, z + 0.08, M)
        for s in (-1, 1):
            gx = C + s * GUIDE_X
            # Guide shoe riding between the post flanges.
            gbox(bm, gx - 0.09, gx + 0.09, y - 0.14, y + 0.14, z - 0.145, z + 0.145, D)
            cyl_x(bm, G(gx, y + 0.08, z), 0.05, 0.2, mat_index=D)
            cyl_x(bm, G(gx, y - 0.08, z), 0.05, 0.2, mat_index=D)
        for x in MOVING_X:
            # Gusset where each plate sits on the tube.
            gbox(bm, C + x - 0.06, C + x + 0.06, y + 0.06, y + 0.2, z - 0.12, z + 0.12, M)
    # Cylinder rods and clevises under the tubes.
    for x in CYL_X:
        gx = C + x
        for z, y in (TUBE_L, TUBE_H):
            clevis = y - 0.08
            rod = 0.6 if y < -0.2 else 0.75
            gbox(bm, gx - 0.05, gx + 0.05, clevis - 0.09, clevis, z - 0.07, z + 0.07, D)
            cyl_x(bm, G(gx, clevis - 0.06, z), 0.03, 0.14, mat_index=D)
            cyl_z(bm, G(gx, clevis - 0.09 - rod / 2, z), 0.04, rod, mat_index=CH)
    L.make_object("LD_MovingMesh", bm, coll, (mats["moving"], mats["wear"], mats["chrome"], mats["dark"]),
                  parent=root)
    return root


# --- Service side ------------------------------------------------------------------

def build_drive(coll, mats):
    root = empty("LD_Drive", coll, None, (0, 0, 0), 0.4)
    MO, F, D, G_ = 0, 1, 2, 3
    a = math.radians(-SLOPE_DEG)
    drive_bed = empty("LD_DriveBed", coll, root, G(C, CN[0], A[1]), 0.3)
    drive_bed.rotation_euler = (a, 0, 0)
    bm = bmesh.new()
    xs = BED_HALF_W + 0.55
    # Shaft-mount reducer hanging on the head shaft end, motor on a scoop above it.
    bbox(bm, xs - 0.13, xs + 0.13, SHAFT_Y - 0.28, SHAFT_Y + 0.22, HEAD_Z - 0.25, HEAD_Z + 0.34, MO)
    L.add_cyl(bm, 0.12, 0.30, L.mat(B(xs, SHAFT_Y, HEAD_Z), (0, 90, 0)), segs=24, mat_index=MO)
    L.add_cyl(bm, 0.15, 0.62, L.mat(B(xs - 0.05, SHAFT_Y + 0.40, HEAD_Z + 0.55), (90, 0, 0)), segs=24, mat_index=MO)
    for k in range(10):
        ang = 2 * math.pi * k / 10
        L.add_box(bm, (0.012, 0.45, 0.03), L.mat(B(xs - 0.05 + 0.155 * math.cos(ang), SHAFT_Y + 0.40 + 0.155 * math.sin(ang),
                                                   HEAD_Z + 0.6)), mat_index=MO)
    bbox(bm, xs - 0.12, xs + 0.12, SHAFT_Y + 0.25, SHAFT_Y + 0.27, HEAD_Z + 0.2, HEAD_Z + 0.9, F)
    # Belt guard.
    bbox(bm, xs - 0.2, xs - 0.13, SHAFT_Y - 0.15, SHAFT_Y + 0.6, HEAD_Z + 0.1, HEAD_Z + 0.85, G_)
    # Junction box on the motor.
    bbox(bm, xs + 0.1, xs + 0.2, SHAFT_Y + 0.38, SHAFT_Y + 0.5, HEAD_Z + 0.4, HEAD_Z + 0.55, D)
    # Torque arm down to the edge beam.
    L.add_beam(bm, B(xs, SHAFT_Y - 0.25, HEAD_Z + 0.25), B(BED_HALF_W + 0.1, -0.58, HEAD_Z + 0.7), 0.05, 0.05, mat_index=F)
    L.make_object("LD_DriveMesh", bm, coll, (mats["motor"], mats["frame"], mats["dark"], mats["rail"]), parent=drive_bed)

    # Hydraulic power unit for the feeder, on the floor beside the feeder.
    bm = bmesh.new()
    hx, hz = C + 3.45, 4.35
    gbox(bm, hx - 0.45, hx + 0.45, FLOOR, FLOOR + 0.08, hz - 0.65, hz + 0.65, F)
    gbox(bm, hx - 0.4, hx + 0.4, FLOOR + 0.08, FLOOR + 0.72, hz - 0.6, hz + 0.6, MO)
    cyl_x(bm, G(hx - 0.05, FLOOR + 0.92, hz - 0.15), 0.16, 0.55, mat_index=MO)
    cyl_x(bm, G(hx + 0.32, FLOOR + 0.92, hz - 0.15), 0.08, 0.18, mat_index=D)
    for k in range(8):
        ang = 2 * math.pi * k / 8
        gbox(bm, hx - 0.3, hx + 0.2, FLOOR + 0.92 + 0.165 * math.sin(ang) - 0.012, FLOOR + 0.92 + 0.165 * math.sin(ang) + 0.012,
             hz - 0.15 + 0.165 * math.cos(ang) - 0.012, hz - 0.15 + 0.165 * math.cos(ang) + 0.012, MO)
    cyl_z(bm, G(hx - 0.2, FLOOR + 0.86, hz + 0.35), 0.07, 0.28, mat_index=D)
    gbox(bm, hx - 0.15, hx + 0.25, FLOOR + 0.72, FLOOR + 0.88, hz + 0.18, hz + 0.5, D)
    # Valve stack and gauge.
    gbox(bm, hx + 0.1, hx + 0.3, FLOOR + 0.72, FLOOR + 1.02, hz + 0.25, hz + 0.45, D)
    cyl_x(bm, G(hx + 0.3, FLOOR + 1.08, hz + 0.35), 0.05, 0.02, segs=16, mat_index=G_)
    # Control panel on a stand.
    gbox(bm, hx - 0.04, hx + 0.04, FLOOR, FLOOR + 1.3, hz + 1.0, hz + 1.08, F)
    gbox(bm, hx - 0.25, hx + 0.25, FLOOR + 1.0, FLOOR + 1.75, hz + 1.08, hz + 1.3, D)
    gbox(bm, hx - 0.12, hx - 0.04, FLOOR + 1.55, FLOOR + 1.6, hz + 1.3, hz + 1.32, 4)
    L.make_object("LD_HPU", bm, coll, (mats["motor"], mats["frame"], mats["dark"], mats["chrome"], mats["red"]),
                  parent=root)
    return root


def build_catwalk(coll, mats):
    root = empty("LD_Catwalk", coll, None, (0, 0, 0), 0.4)
    F, GR, R = 0, 1, 2
    bm = bmesh.new()
    x0, x1 = C + WALK_X[0], C + WALK_X[1]
    z0, z1 = WALK_Z
    y = WALK_Y
    # Grating floor on channel stringers.
    gbox(bm, x0, x1, y - 0.03, y, z0, z1, GR)
    for k in range(int((z1 - z0) / 0.1)):
        z = z0 + 0.05 + k * 0.1
        gbox(bm, x0 + 0.01, x1 - 0.01, y, y + 0.004, z - 0.004, z + 0.004, F)
    for x in (x0, x1):
        gbox(bm, x - 0.03, x + 0.03, y - 0.2, y, z0, z1, F)
        gbox(bm, x - 0.003, x + 0.003, y, y + 0.1, z0, z1, R)   # toe board
    n = 7
    for k in range(n):
        z = z0 + 0.05 + (z1 - z0 - 0.1) * k / (n - 1)
        for x in (x0, x1):
            gbox(bm, x - 0.04, x + 0.04, FLOOR, y - 0.2, z - 0.04, z + 0.04, F)
            gbox(bm, x - 0.025, x + 0.025, y, y + 1.07, z - 0.025, z + 0.025, R)
        gbox(bm, x0, x1, y - 0.2, y - 0.03, z - 0.03, z + 0.03, F)
        gbox(bm, x0 - 0.12, x1 + 0.12, FLOOR, FLOOR + 0.02, z - 0.12, z + 0.12, F)
    for x in (x0, x1):
        for h in (0.53, 1.05):
            gbox(bm, x - 0.025, x + 0.025, y + h - 0.025, y + h + 0.025, z0 + 0.02, z1 - 0.02, R)
    # Feeder end rail.
    for h in (0.53, 1.05):
        gbox(bm, x0, x1, y + h - 0.025, y + h + 0.025, z0 + 0.025, z0 + 0.075, R)
    # Stairs down off the far end.
    rise = y - FLOOR
    steps = 7
    run = 0.26
    sz0 = z1
    sz1 = z1 + run * steps
    for x in (x0, x1):
        L.add_beam(bm, G(x, y - 0.05, sz0), G(x, FLOOR + 0.05, sz1), 0.05, 0.22, mat_index=F)
        L.add_beam(bm, G(x, y + 0.95, sz0), G(x, FLOOR + 0.95, sz1), 0.05, 0.05, mat_index=R)
        gbox(bm, x - 0.025, x + 0.025, FLOOR, FLOOR + 1.0, sz1 - 0.05, sz1, R)
    for k in range(steps):
        sy = y - rise * (k + 1) / (steps + 1)
        sz = sz0 + run * (k + 0.5)
        gbox(bm, x0 + 0.03, x1 - 0.03, sy - 0.03, sy, sz - run / 2, sz + run / 2, GR)
    L.make_object("LD_CatwalkMesh", bm, coll, (mats["frame"], mats["grate"], mats["rail"]), parent=root)
    return root


# --- Chain -------------------------------------------------------------------------

CHAIN_PITCH = 0.1524


def build_chain_links(coll, mats):
    """One pitch of welded drag chain along Godot +z, top at y = +0.02, and a dog link."""
    out = []
    for name, dog in (("LD_ChainLink", False), ("LD_ChainDog", True)):
        bm = bmesh.new()
        p = CHAIN_PITCH
        for s in (-1, 1):
            # Offset side bars: welded at the barrel end, open at the other.
            box(bm, Vector((s * 0.034, 0, 0)), (0.012, p + 0.02, 0.04), 0)
        L.add_cyl(bm, 0.022, 0.08, L.mat((0, -p / 2, 0), (0, 90, 0)), segs=12, mat_index=0)
        L.add_cyl(bm, 0.01, 0.1, L.mat((0, -p / 2, 0), (0, 90, 0)), segs=8, mat_index=0)
        if dog:
            # Raised dog that bites the log.
            L.add_prism(bm, [(-0.05, 0.02), (0.05, 0.02), (0.0, 0.055)], -0.03, 0.03,
                        Matrix(((0, 1, 0, 0), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))), 0)
        obj = L.make_object(name, bm, coll, (mats["chain"],), weighted=False)
        obj.location = (2.0 if dog else 1.6, 18.0, 0.0)
        out.append(obj)
    return out


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = build_materials()
    frame = empty("LD_Frame", coll, None, (0, 0, 0), 0.5)
    build_bed(coll, mats, frame)
    build_bed_legs(coll, mats, frame)
    build_feeder(coll, mats, frame)
    build_moving(coll, mats)
    build_drive(coll, mats)
    build_catwalk(coll, mats)
    build_chain_links(coll, mats)
    return {"T": T, "CN": CN, "objects": len(coll.all_objects)}


def pose(lift=0.0):
    bpy.data.objects["LD_MovingSteps"].location = (0, 0, lift)
