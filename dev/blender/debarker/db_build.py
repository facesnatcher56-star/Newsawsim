"""Ring debarker line (run inside Blender).

A sawmill rotary ring debarker sized for the mill's 0.58 m (23 in) logs, in the style of
Nicholson A-series / Valon Kone VK machines:
  - centring V-roll (double cone) infeed conveyor with dump skids from both log decks
  - spiked hourglass feed rolls in and out: bottom rolls fixed, top rolls on hydraulic
    swing arms that ride down onto the log
  - rotor ring with a 0.94 m (37 in) opening and six spring-loaded tool arms on the
    outfeed face; V-belt drive from a motor on top of the housing
  - open frame with grille guards so the rotor and tools stay visible, bark chute below
  - V-roll outfeed with a metal detector arch, cleated bark belt up to a roll-off bin

One frame for every part: X along the feed (ring plane at x = 0), Y left (Godot -Z),
Z up from the floor; the log axis is LINE_Z above the floor. Moving parts hang off empties
at their pins/axes so the game can drive them by name:

  DB_Rotor (spins about X) > DB_Tool1..6 (swing about X)
  DB_InTopArm / DB_OutTopArm (swing about Y) > DB_InTopRoll / DB_OutTopRoll (spin about Y)
  DB_InBottomRoll / DB_OutBottomRoll, IN_Roll_n / OUT_Roll_n (spin about Y)
  DB_InArmCylBarrel / Rod, DB_OutArmCylBarrel / Rod (look_at pairs, +Y to partner, +Z pin)
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

COLL = "RingDebarker"

# Log axis above the floor: level with a log riding the mill's kicker conveyor downstream
# (log centre 0.87 m in the mill, floor at -1.288), so the outfeed hands straight across.
LINE_Z = 2.16
LOG_R = 0.292
# V-roll conveyors: double cones, 30 deg flanks.
VROLL_R0 = 0.10
VROLL_HALF = 0.40
V_TAN = math.tan(math.radians(30.0))
VROLL_Z = LINE_Z - (VROLL_R0 + LOG_R / math.cos(math.radians(30.0)))
# Conveyor extents along X (ring at 0).
IN_X = (-8.915, -1.465)
OUT_X = (1.435, 8.035)
IN_ROLLS = 12
OUT_ROLLS = 11
# Feed rolls.
FEED_IN_X = -1.0
FEED_OUT_X = 1.05
FEED_R0 = 0.16
FEED_HALF = 0.30
FEED_Z = LINE_Z - (FEED_R0 + LOG_R / math.cos(math.radians(30.0)))
TOP_ROLL_Z = LINE_Z + (FEED_R0 + LOG_R / math.cos(math.radians(30.0)))
ARM_PIVOT_IN = Vector((-1.85, 0.0, LINE_Z + 0.95))
ARM_PIVOT_OUT = Vector((1.90, 0.0, LINE_Z + 0.95))
CYL_BASE_IN = Vector((-1.35, 0.0, LINE_Z + 1.32))
CYL_BASE_OUT = Vector((1.40, 0.0, LINE_Z + 1.32))
GANTRY_TOP = LINE_Z + 1.39
ARM_LUG_FRAC = 0.55
# Rotor and tools.
ROTOR_RI = 0.47
ROTOR_RO = 0.78
ROTOR_HALF_X = 0.16
TOOL_PIVOT_R = 0.64
TOOL_LEN = 0.56
TOOL_X = 0.21
# Housing.
HOUSE_X = 0.42
HOUSE_Y = 1.05
HOUSE_Z = (LINE_Z - 1.1, LINE_Z + 1.1)
# Dump skids from the decks (the deck lips sit 0.85 m either side of the line).
SKID_X = (-8.55, -3.35)
# Bark belt (runs along +Y, away from the line) and bin.
BELT_TAIL_Y = -0.8
BELT_BEND_Y = 1.8
BELT_HEAD_Y = 5.3
BELT_LOW_Z = 0.35
BELT_HIGH_Z = 2.05
BELT_W = 0.9
# Near wall 0.1 m short of the belt head, so bark coming off the head drops inside.
BIN_CENTRE = Vector((0.0, 7.30, 0.0))
BIN_SIZE = Vector((2.4, 4.2, 1.6))


def _v(x, y, z):
    return Vector((x, y, z))


def empty(name, coll, parent=None, loc=(0, 0, 0), size=0.15):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = size
    coll.objects.link(obj)
    obj.parent = parent
    obj.location = loc
    return obj


def frame_y(direction, pin_axis):
    y = Vector(direction).normalized()
    z = Vector(pin_axis)
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


def pin_boss(bm, centre, axis, r, length, segs=20, mat_index=0):
    m, _ = L.frame_between(Vector(centre) - Vector(axis) * length / 2, Vector(centre) + Vector(axis) * length / 2)
    L.add_cyl(bm, r, length, m @ L.mat(rot=(0, 90, 0)), segs=segs, mat_index=mat_index)


def build_materials():
    frame = ((0.05, 0.11, 0.16), (0.09, 0.18, 0.25), (0.15, 0.26, 0.33))
    yellow = ((0.42, 0.26, 0.012), (0.62, 0.40, 0.02), (0.78, 0.55, 0.08))
    return {
        "frame": ML.painted_steel("DB_Frame", *frame, chip_amount=0.55, dirt_height=1.2),
        "guard": ML.painted_steel("DB_Guard", *yellow, chip_amount=0.6, dirt_height=1.0),
        "steel": ML.simple("DB_Steel", (0.20, 0.20, 0.20), 0.45, 0.9, 50, 0.05),
        "dark": ML.painted_steel("DB_Dark", (0.02, 0.02, 0.02), (0.04, 0.04, 0.04), (0.07, 0.07, 0.065),
                                 chip_amount=0.8, dirt_height=1.5),
        "chrome": ML.simple("DB_Chrome", (0.75, 0.75, 0.74), 0.08, 1.0),
        "rubber": ML.rubber("DB_Rubber"),
        "motor": ML.painted_steel("DB_Motor", (0.03, 0.06, 0.12), (0.05, 0.10, 0.20), (0.09, 0.15, 0.27),
                                  chip_amount=0.4, dirt_height=0.5),
        "red": ML.simple("DB_Red", (0.5, 0.03, 0.02), 0.5, 0.0),
        "bin": ML.painted_steel("DB_Bin", (0.12, 0.05, 0.02), (0.20, 0.09, 0.03), (0.28, 0.14, 0.06),
                                chip_amount=0.9, dirt_height=1.5),
        "bark": ML.simple("DB_Bark", (0.16, 0.08, 0.035), 0.95, 0.0, 30, 0.6),
    }


VIEWPORT = {
    "DB_Frame": ((0.09, 0.18, 0.25), 0.3, 0.55),
    "DB_Guard": ((0.62, 0.40, 0.02), 0.2, 0.55),
    "DB_Steel": ((0.30, 0.295, 0.285), 0.45, 0.45),
    "DB_Dark": ((0.04, 0.04, 0.04), 0.5, 0.5),
    "DB_Chrome": ((0.78, 0.78, 0.77), 1.0, 0.08),
    "DB_Rubber": ((0.02, 0.02, 0.02), 0.0, 0.85),
    "DB_Motor": ((0.05, 0.10, 0.20), 0.4, 0.5),
    "DB_Red": ((0.5, 0.03, 0.02), 0.0, 0.5),
    "DB_Bin": ((0.20, 0.09, 0.03), 0.3, 0.7),
    "DB_Bark": ((0.16, 0.08, 0.035), 0.0, 0.95),
}


# --- Rolls ------------------------------------------------------------------------

def vroll_profile(r0, half, steps=8):
    """(radius, axial) points for a double cone along Y, closed at both ends."""
    prof = [(0.0, -half - 0.02), (r0 + half * V_TAN, -half - 0.02)]
    for k in range(steps + 1):
        y = -half + 2 * half * k / steps
        prof.append((r0 + abs(y) * V_TAN, y))
    prof += [(r0 + half * V_TAN, half + 0.02), (0.0, half + 0.02)]
    return prof


def build_vroll(name, coll, mats, parent, loc, with_sprocket=True):
    roll = empty(name, coll, parent, loc, 0.1)
    bm = bmesh.new()
    L.add_lathe(bm, vroll_profile(VROLL_R0, VROLL_HALF), segs=40, mats=[0])
    # Dark wear bands so the spin reads against the worn steel.
    for y in (-0.25, 0.25):
        L.add_lathe(bm, [(VROLL_R0 + abs(y) * V_TAN + 0.004, y - 0.02), (VROLL_R0 + abs(y) * V_TAN + 0.004, y + 0.02)],
                    segs=40, closed=False, mats=[1])
    pin_boss(bm, (0, 0, 0), (0, 1, 0), 0.035, 1.08, mat_index=0)
    if with_sprocket:
        L.add_cyl(bm, 0.11, 0.025, L.mat((0, 0.57, 0), (90, 0, 0)), segs=18, mat_index=1)
    L.make_object(name + "Mesh", bm, coll, (mats["steel"], mats["dark"]), parent=roll)
    return roll


def spiked_roll(bm, r0, half, mat_spike=1):
    L.add_lathe(bm, vroll_profile(r0, half, 10), segs=48, mats=[0])
    # Rings of pyramid spikes that bite the bark.
    for k in range(7):
        y = -half + 2 * half * (k + 0.5) / 7
        r = r0 + abs(y) * V_TAN
        for j in range(10):
            a = 2 * math.pi * (j + 0.5 * (k % 2)) / 10
            n = Vector((math.cos(a), 0, math.sin(a)))
            base = n * r + Vector((0, y, 0))
            m = Matrix.Translation(base + n * 0.02) @ frame_y(n, (0, 1, 0)).to_4x4()
            L.add_cyl(bm, 0.018, 0.045, m @ L.mat(rot=(-90, 0, 0)), segs=4, r2=0.002, mat_index=mat_spike)
    pin_boss(bm, (0, 0, 0), (0, 1, 0), 0.05, 2 * half + 0.35, mat_index=mat_spike)


# --- Conveyors ---------------------------------------------------------------------

def build_vroll_conveyor(prefix, coll, mats, x0, x1, n_rolls, drive_end):
    root = empty(prefix, coll, None, (0, 0, 0), 0.4)
    pitch = (x1 - x0 - 0.3) / (n_rolls - 1)
    bm = bmesh.new()
    rail_z = VROLL_Z - 0.06
    for y in (-0.52, 0.52):
        # Channel side rails (web plus flanges).
        L.add_box(bm, (x1 - x0, 0.01, 0.20), L.mat(((x0 + x1) / 2, y, rail_z)))
        for dz in (-0.095, 0.095):
            L.add_box(bm, (x1 - x0, 0.07, 0.012), L.mat(((x0 + x1) / 2, y - math.copysign(0.03, y), rail_z + dz)))
    # Legs with knee braces and feet.
    nlegs = max(2, int((x1 - x0) / 2.2) + 1)
    for i in range(nlegs):
        x = x0 + 0.2 + (x1 - x0 - 0.4) * i / (nlegs - 1)
        for y in (-0.52, 0.52):
            L.add_box(bm, (0.12, 0.12, rail_z - 0.1), L.mat((x, y, (rail_z - 0.1) / 2)))
            L.add_box(bm, (0.30, 0.30, 0.02), L.mat((x, y, 0.01)))
        L.add_beam(bm, (x, -0.52, 0.45), (x, 0.52, 0.45), 0.08, 0.08)
    # Pillow blocks.
    for i in range(n_rolls):
        x = x0 + 0.15 + pitch * i
        for y in (-0.49, 0.49):
            L.add_box(bm, (0.12, 0.06, 0.09), L.mat((x, y, VROLL_Z - 0.03)), mat_index=1)
    # Chain guard over the drive sprockets and the gearmotor at the drive end.
    L.add_box(bm, (x1 - x0, 0.06, 0.30), L.mat(((x0 + x1) / 2, 0.60, VROLL_Z)), mat_index=2)
    L.add_box(bm, (x1 - x0, 0.10, 0.02), L.mat(((x0 + x1) / 2, 0.58, VROLL_Z + 0.15)), mat_index=2)
    gx = drive_end
    L.add_box(bm, (0.5, 0.35, 0.3), L.mat((gx, 0.85, VROLL_Z - 0.3)), mat_index=3)
    L.add_cyl(bm, 0.14, 0.45, L.mat((gx, 0.85, VROLL_Z + 0.05), (0, 0, 0)), segs=20, mat_index=4)
    L.make_object(prefix + "Frame", bm, coll, (mats["frame"], mats["steel"], mats["guard"], mats["dark"], mats["motor"]),
                  bevel=0.004, parent=root)
    rolls = []
    for i in range(n_rolls):
        x = x0 + 0.15 + pitch * i
        rolls.append(build_vroll(f"{prefix}_Roll{i}", coll, mats, root, (x, 0, VROLL_Z)))
    return root


def build_dump_skids(coll, mats, parent):
    """Sloped skid plates either side of the infeed that take logs off the deck lips."""
    bm = bmesh.new()
    x0, x1 = SKID_X
    for s in (-1, 1):
        lo = _v(0, s * 0.44, LINE_Z - 0.08)
        hi = _v(0, s * 0.86, LINE_Z + 0.60)      # level with the deck lips
        n_ribs = 6
        for k in range(n_ribs):
            x = x0 + (x1 - x0) * k / (n_ribs - 1)
            L.add_beam(bm, (x, lo.y, lo.z), (x, hi.y, hi.z), 0.10, 0.03)
            L.add_beam(bm, (x, hi.y + s * 0.02, hi.z), (x, hi.y + s * 0.02, VROLL_Z - 0.16), 0.08, 0.08)
        m, length = L.frame_between((x0, lo.y, lo.z), (x0, hi.y, hi.z), up=(1, 0, 0))
        mid = (lo + hi) / 2
        along = (hi - lo).normalized()
        nrm = Vector((1, 0, 0)).cross(along).normalized() * -s
        plate = Matrix.Translation(_v((x0 + x1) / 2, mid.y, mid.z) + nrm * 0.03)
        rot = Matrix((Vector((1, 0, 0)), along, Vector((1, 0, 0)).cross(along))).transposed().to_4x4()
        L.add_box(bm, ((x1 - x0) + 0.2, length, 0.012), plate @ rot, mat_index=1)
    L.make_object("IN_DumpSkids", bm, coll, (mats["frame"], mats["steel"]), bevel=0.004, parent=parent)


# --- Machine -----------------------------------------------------------------------

def build_machine(coll, mats):
    root = empty("DB_Machine", coll, None, (0, 0, 0), 0.5)
    F, S, G, D = 0, 1, 2, 3
    mm = (mats["frame"], mats["steel"], mats["guard"], mats["dark"], mats["motor"], mats["red"])
    bm = bmesh.new()
    # Base skid.
    for y in (-0.95, 0.95):
        L.add_box(bm, (3.9, 0.22, 0.30), L.mat((0.05, y, 0.15)), mat_index=F)
    for x in (-1.75, -1.0, -0.42, 0.42, 1.05, 1.85):
        L.add_box(bm, (0.18, 1.9, 0.22), L.mat((x, 0, 0.12)), mat_index=F)
    # Housing end plates with the log bore, and the entry bell mouth.
    for x in (-HOUSE_X, HOUSE_X):
        ring_pts = 48
        outer = [(-HOUSE_Y, HOUSE_Z[0]), (HOUSE_Y, HOUSE_Z[0]), (HOUSE_Y, HOUSE_Z[1]), (-HOUSE_Y, HOUSE_Z[1])]
        _plate_with_hole(bm, x, outer, 0.50, ring_pts, 0.04, F)
    L.add_lathe(bm, [(0.62, -HOUSE_X - 0.25), (0.50, -HOUSE_X - 0.02), (0.48, -HOUSE_X - 0.02), (0.60, -HOUSE_X - 0.25)],
                segs=48, m=L.mat((0, 0, LINE_Z), (0, 0, -90)), closed=True, mats=[S])
    # Top cover, and grille side guards so the rotor stays in view.
    L.add_box(bm, (2 * HOUSE_X, 2 * HOUSE_Y, 0.04), L.mat((0, 0, HOUSE_Z[1])), mat_index=F)
    for s in (-1, 1):
        y = s * HOUSE_Y
        for z in (HOUSE_Z[0] + 0.05, HOUSE_Z[1] - 0.05):
            L.add_box(bm, (2 * HOUSE_X, 0.05, 0.10), L.mat((0, y, z)), mat_index=G)
        for k in range(9):
            z = HOUSE_Z[0] + 0.25 + k * 0.22
            L.add_box(bm, (2 * HOUSE_X, 0.02, 0.02), L.mat((0, y, z)), mat_index=G)
        for x in (-0.3, 0.0, 0.3):
            L.add_box(bm, (0.03, 0.03, HOUSE_Z[1] - HOUSE_Z[0]), L.mat((x, y, (HOUSE_Z[0] + HOUSE_Z[1]) / 2)), mat_index=G)
        # Inspection door handle and hinges on the grille.
        L.add_box(bm, (0.04, 0.06, 0.18), L.mat((0.36, y + s * 0.03, 2.0)), mat_index=D)
    # Corner columns down to the skid.
    for x in (-HOUSE_X, HOUSE_X):
        for y in (-HOUSE_Y + 0.08, HOUSE_Y - 0.08):
            L.add_box(bm, (0.16, 0.16, HOUSE_Z[0] - 0.3), L.mat((x, y, 0.3 + (HOUSE_Z[0] - 0.3) / 2)), mat_index=F)
    # Bark chute: funnel from the housing floor down to the bark belt.
    L.add_loft(bm, [
        [_v(-HOUSE_X, -HOUSE_Y + 0.1, HOUSE_Z[0]), _v(HOUSE_X, -HOUSE_Y + 0.1, HOUSE_Z[0]),
         _v(HOUSE_X, HOUSE_Y - 0.1, HOUSE_Z[0]), _v(-HOUSE_X, HOUSE_Y - 0.1, HOUSE_Z[0])],
        [_v(-0.36, -0.40, BELT_LOW_Z + 0.25), _v(0.36, -0.40, BELT_LOW_Z + 0.25),
         _v(0.36, 0.40, BELT_LOW_Z + 0.25), _v(-0.36, 0.40, BELT_LOW_Z + 0.25)],
    ], cap_bottom=False, cap_top=False, mat_index=F)
    # Feed roll bearing pedestals and the hydraulic drive motors on the bottom rolls.
    for x in (FEED_IN_X, FEED_OUT_X):
        for y in (-0.55, 0.55):
            L.add_box(bm, (0.30, 0.16, FEED_Z - 0.22), L.mat((x, y, 0.22 + (FEED_Z - 0.22) / 2)), mat_index=F)
            L.add_box(bm, (0.22, 0.14, 0.14), L.mat((x, y, FEED_Z)), mat_index=S)
        L.add_cyl(bm, 0.09, 0.22, L.mat((x, -0.72, FEED_Z), (90, 0, 0)), segs=16, mat_index=D)
    # Top roll gantries: posts, crossbeam, and beams back to the housing that carry the
    # arm cylinders.
    for px, cyl, hx in ((ARM_PIVOT_IN.x, CYL_BASE_IN, -HOUSE_X), (ARM_PIVOT_OUT.x, CYL_BASE_OUT, HOUSE_X)):
        for y in (-0.62, 0.62):
            post_h = GANTRY_TOP - 0.09 - 0.3
            L.add_box(bm, (0.16, 0.16, post_h), L.mat((px, y, 0.3 + post_h / 2)), mat_index=F)
            pin_boss(bm, (px, y * 0.85, ARM_PIVOT_IN.z), (0, 1, 0), 0.07, 0.08, mat_index=S)
        L.add_box(bm, (0.18, 1.40, 0.18), L.mat((px, 0, GANTRY_TOP)), mat_index=F)
        for y in (-0.12, 0.12):
            L.add_beam(bm, (px, y, GANTRY_TOP), (hx, y, HOUSE_Z[1] + 0.09), 0.10, 0.14, mat_index=F)
            L.add_box(bm, (0.16, 0.03, 0.16), L.mat((cyl.x, y * 0.6, cyl.z - 0.02)), mat_index=F)
        pin_boss(bm, cyl, (0, 1, 0), 0.03, 0.20, mat_index=S)
        pin_boss(bm, (px, 0, ARM_PIVOT_IN.z), (0, 1, 0), 0.04, 1.30, mat_index=S)
    # Drive motor on a base behind the rotor plane; its shaft points +X so the pulley sits
    # right over the rotor sheave, and the V-belts run down through the housing top inside
    # a guard that spans pulley to rotor.
    mx, my, mz = -0.75, -0.50, HOUSE_Z[1] + 0.42
    L.add_box(bm, (0.95, 0.70, 0.08), L.mat((mx, my, HOUSE_Z[1] + 0.06)), mat_index=F)
    L.add_cyl(bm, 0.28, 0.80, L.mat((mx, my, mz), (0, 90, 0)), segs=28, mat_index=4)
    for k in range(10):
        a = 2 * math.pi * k / 10
        L.add_box(bm, (0.72, 0.025, 0.05), L.mat((mx, my + 0.29 * math.cos(a), mz + 0.29 * math.sin(a)),
                                                 (math.degrees(a), 0, 0)), mat_index=4)
    L.add_box(bm, (0.28, 0.28, 0.22), L.mat((mx - 0.1, my, mz + 0.36)), mat_index=4)
    L.add_cyl(bm, 0.05, 0.42, L.mat((mx + 0.55, my, mz), (0, 90, 0)), segs=12, mat_index=S)
    L.add_box(bm, (0.32, abs(my) + 0.45, mz - HOUSE_Z[1] + 0.40),
              L.mat((0.0, my / 2, HOUSE_Z[1] + (mz - HOUSE_Z[1] + 0.40) / 2)), mat_index=G)
    # Control station with light tower on the operator side.
    L.add_box(bm, (0.6, 0.3, 1.6), L.mat((1.5, -1.45, 0.8)), mat_index=G)
    L.add_box(bm, (0.5, 0.05, 0.6), L.mat((1.5, -1.62, 1.3)), mat_index=D)
    L.add_cyl(bm, 0.03, 0.6, L.mat((1.5, -1.45, 1.9)), segs=8, mat_index=S)
    for i, z in enumerate((2.25, 2.35, 2.45)):
        L.add_cyl(bm, 0.06, 0.09, L.mat((1.5, -1.45, z)), segs=12, mat_index=5 if i == 0 else 2)
    L.make_object("DB_MachineBody", bm, coll, mm, bevel=0.006, parent=root)

    build_rotor(coll, mats, root)
    for side, x, pivot, cyl in (("In", FEED_IN_X, ARM_PIVOT_IN, CYL_BASE_IN),
                                ("Out", FEED_OUT_X, ARM_PIVOT_OUT, CYL_BASE_OUT)):
        bottom = empty(f"DB_{side}BottomRoll", coll, root, (x, 0, FEED_Z), 0.1)
        bm = bmesh.new()
        spiked_roll(bm, FEED_R0, FEED_HALF)
        L.make_object(f"DB_{side}BottomRollMesh", bm, coll, (mats["steel"], mats["dark"]), parent=bottom)
        build_top_arm(coll, mats, root, side, x, pivot, cyl)
    return root


def _plate_with_hole(bm, x, outer, r, segs, t, mat_index):
    """Vertical plate in the YZ plane at x with a round hole on the line axis."""
    # Build as a ring of quads between the outer rectangle (sampled) and the hole.
    pts_out = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        c, s = math.cos(a), math.sin(a)
        # Ray from the centre to the rectangle edge.
        tmax = min(abs(HOUSE_Y / c) if abs(c) > 1e-6 else 1e9,
                   abs(((HOUSE_Z[1] if s > 0 else HOUSE_Z[0]) - LINE_Z) / s) if abs(s) > 1e-6 else 1e9)
        pts_out.append((c * tmax, LINE_Z + s * tmax))
    pts_in = [(math.cos(2 * math.pi * k / segs) * r, LINE_Z + math.sin(2 * math.pi * k / segs) * r) for k in range(segs)]
    rings = []
    for dx in (-t / 2, t / 2):
        rings.append(([bm.verts.new((x + dx, y, z)) for y, z in pts_out], [bm.verts.new((x + dx, y, z)) for y, z in pts_in]))
    faces = []
    for (o, i) in rings:
        for k in range(segs):
            j = (k + 1) % segs
            faces.append(bm.faces.new((o[k], o[j], i[j], i[k])))
    (o0, i0), (o1, i1) = rings
    for k in range(segs):
        j = (k + 1) % segs
        faces.append(bm.faces.new((o0[k], o1[k], o1[j], o0[j])))
        faces.append(bm.faces.new((i0[k], i0[j], i1[j], i1[k])))
    for f in faces:
        f.material_index = mat_index
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def build_rotor(coll, mats, parent):
    rotor = empty("DB_Rotor", coll, parent, (0, 0, LINE_Z), 0.3)
    bm = bmesh.new()
    m = L.mat(rot=(0, 0, -90))      # lathe axis Y -> X
    prof = [(ROTOR_RI, -ROTOR_HALF_X), (ROTOR_RO - 0.05, -ROTOR_HALF_X), (ROTOR_RO - 0.05, -ROTOR_HALF_X + 0.03)]
    # V-belt sheave grooves on the rim.
    n_grooves = 6
    for g in range(n_grooves):
        x0 = -ROTOR_HALF_X + 0.03 + g * (2 * ROTOR_HALF_X - 0.06) / n_grooves
        w = (2 * ROTOR_HALF_X - 0.06) / n_grooves
        prof += [(ROTOR_RO, x0 + 0.01), (ROTOR_RO - 0.03, x0 + w / 2), (ROTOR_RO, x0 + w - 0.01)]
    prof += [(ROTOR_RO - 0.05, ROTOR_HALF_X - 0.03), (ROTOR_RO - 0.05, ROTOR_HALF_X), (ROTOR_RI, ROTOR_HALF_X)]
    L.add_lathe(bm, prof, segs=64, m=m, closed=True, mats=[0])
    # Spokes/stiffeners on the outfeed face, and balance weights so the spin reads.
    for k in range(12):
        a = 2 * math.pi * (k + 0.5) / 12
        L.add_box(bm, (0.04, 0.28, 0.05), Matrix.Rotation(a, 4, 'X') @ L.mat((ROTOR_HALF_X + 0.02, 0, ROTOR_RI + 0.15)),
                  mat_index=0)
    L.add_box(bm, (0.08, 0.16, 0.10), Matrix.Rotation(0.4, 4, 'X') @ L.mat((-ROTOR_HALF_X - 0.04, 0, ROTOR_RO - 0.16)),
              mat_index=2)
    L.make_object("DB_RotorMesh", bm, coll, (mats["steel"], mats["dark"], mats["red"]), bevel=0.004, parent=rotor)
    # Tool arms: pivot pins on the outfeed face, arms pointing in to the axis at rest.
    for k in range(6):
        a = 2 * math.pi * k / 6
        piv = _v(TOOL_X, TOOL_PIVOT_R * math.cos(a), TOOL_PIVOT_R * math.sin(a))
        tool = empty(f"DB_Tool{k + 1}", coll, rotor, tuple(piv), 0.08)
        inward = -_v(0, math.cos(a), math.sin(a))
        side = _v(1, 0, 0).cross(inward)
        bm = bmesh.new()
        # Pivot hub with its air-spring housing, the curved arm, and the cutting tip.
        pin_boss(bm, (0, 0, 0), (1, 0, 0), 0.06, 0.10, mat_index=1)
        L.add_cyl(bm, 0.05, 0.12, Matrix.Translation(side * 0.10 + _v(-0.02, 0, 0)) @ L.mat(rot=(0, 90, 0)),
                  segs=12, mat_index=2)
        pts = [Vector((0, 0, 0)), inward * TOOL_LEN * 0.45 + side * 0.05, inward * (TOOL_LEN - 0.05) + side * 0.03]
        for p0, p1 in zip(pts, pts[1:]):
            L.add_beam(bm, p0, p1, 0.06, 0.04, up=(1, 0, 0))
        tip = inward * TOOL_LEN
        L.add_beam(bm, inward * (TOOL_LEN - 0.08), tip + side * -0.02, 0.08, 0.05, up=(1, 0, 0), mat_index=3)
        L.make_object(f"DB_Tool{k + 1}Mesh", bm, coll, (mats["dark"], mats["steel"], mats["rubber"], mats["chrome"]),
                      bevel=0.004, parent=tool)


def build_top_arm(coll, mats, parent, side, roll_x, pivot, cyl_base):
    arm = empty(f"DB_{side}TopArm", coll, parent, tuple(pivot), 0.12)
    roll_rel = _v(roll_x, 0, TOP_ROLL_Z) - pivot
    bm = bmesh.new()
    # Heavy box-section side arms, a cross tube tying them together at the pivot, and a
    # guard hood over the roll: the roll reads as hung from the machine, not floating.
    for y in (-0.40, 0.40):
        L.add_beam(bm, (0, y, 0), (roll_rel.x, y, roll_rel.z), 0.24, 0.08, up=(0, 1, 0))
        pin_boss(bm, (0, y, 0), (0, 1, 0), 0.13, 0.10)
        pin_boss(bm, (roll_rel.x, y, roll_rel.z), (0, 1, 0), 0.12, 0.10)
    pin_boss(bm, (0, 0, 0), (0, 1, 0), 0.08, 0.80)
    lug = roll_rel * ARM_LUG_FRAC
    L.add_beam(bm, (lug.x, -0.40, lug.z + 0.05), (lug.x, 0.40, lug.z + 0.05), 0.14, 0.14)
    for y in (-0.07, 0.07):
        L.add_box(bm, (0.14, 0.03, 0.18), L.mat((lug.x, y, lug.z + 0.15)))
    hood = [(0.42 * math.cos(math.radians(a)), 0.42 * math.sin(math.radians(a))) for a in range(0, 181, 15)]
    hood_in = [(0.38 * math.cos(math.radians(a)), 0.38 * math.sin(math.radians(a))) for a in range(180, -1, -15)]
    L.add_prism(bm, [(roll_rel.x + x, roll_rel.z + z) for x, z in hood + hood_in], -0.36, 0.36)
    # Hydraulic drive motor on the top roll.
    L.add_cyl(bm, 0.10, 0.22, L.mat((roll_rel.x, -0.58, roll_rel.z), (90, 0, 0)), segs=20, mat_index=1)
    L.make_object(f"DB_{side}TopArmMesh", bm, coll, (mats["guard"], mats["dark"]), bevel=0.008, parent=arm)
    roll = empty(f"DB_{side}TopRoll", coll, arm, tuple(roll_rel), 0.1)
    bm = bmesh.new()
    spiked_roll(bm, FEED_R0, FEED_HALF)
    L.make_object(f"DB_{side}TopRollMesh", bm, coll, (mats["steel"], mats["dark"]), parent=roll)
    # Arm cylinder: barrel on the gantry beam, rod to the lug.
    bpy.context.view_layer.update()
    lug_world = arm.matrix_world @ (lug + _v(0, 0, 0.15))
    # Pin-to-pin runs 0.39 m (arm 10 deg up over a log) to 0.62 m (resting 18 deg down).
    make_cylinder_pair(coll, mats, f"{side}ArmCyl", parent, arm, cyl_base, lug_world, 0.07, 0.035, 0.36, 0.34)


def make_cylinder_pair(coll, mats, name, parent_a, parent_b, pin_a, pin_b, bore_r, rod_r, barrel_len, rod_len):
    a = empty(f"DB_{name}Barrel", coll, parent_a)
    b = empty(f"DB_{name}Rod", coll, parent_b)
    a.matrix_world = Matrix.Translation(pin_a)
    b.matrix_world = Matrix.Translation(pin_b)
    bm = bmesh.new()
    pin_boss(bm, (0, 0, 0), (0, 0, 1), bore_r * 0.85, 0.09)
    L.add_rod(bm, (0, bore_r * 0.9, 0), (0, barrel_len, 0), bore_r, segs=20)
    L.add_rod(bm, (0, barrel_len - 0.05, 0), (0, barrel_len, 0), bore_r * 1.12, segs=20)
    L.make_object(f"DB_{name}BarrelMesh", bm, coll, (mats["frame"],), bevel=0.004, parent=a)
    bm = bmesh.new()
    pin_boss(bm, (0, 0, 0), (0, 0, 1), rod_r * 1.5, 0.07, mat_index=1)
    L.add_rod(bm, (0, rod_r, 0), (0, rod_len, 0), rod_r, segs=16)
    L.make_object(f"DB_{name}RodMesh", bm, coll, (mats["chrome"], mats["steel"]), parent=b)
    return a, b


def aim_cylinders():
    bpy.context.view_layer.update()
    for side in ("In", "Out"):
        a = bpy.data.objects[f"DB_{side}ArmCylBarrel"]
        b = bpy.data.objects[f"DB_{side}ArmCylRod"]
        pa, pb = a.matrix_world.translation.copy(), b.matrix_world.translation.copy()
        a.matrix_world = Matrix.Translation(pa) @ frame_y(pb - pa, (0, 1, 0)).to_4x4()
        b.matrix_world = Matrix.Translation(pb) @ frame_y(pa - pb, (0, 1, 0)).to_4x4()
        bpy.context.view_layer.update()


# --- Outfeed extras, bark belt and bin --------------------------------------------

def build_metal_detector(coll, mats, parent, x):
    bm = bmesh.new()
    for y in (-0.75, 0.75):
        L.add_box(bm, (0.25, 0.12, LINE_Z + 0.6), L.mat((x, y, (LINE_Z + 0.6) / 2)), mat_index=0)
    L.add_box(bm, (0.25, 1.62, 0.22), L.mat((x, 0, LINE_Z + 0.65)), mat_index=0)
    L.add_box(bm, (0.30, 1.30, 0.06), L.mat((x, 0, LINE_Z + 0.42)), mat_index=1)
    L.add_cyl(bm, 0.05, 0.08, L.mat((x, 0.6, LINE_Z + 0.80)), segs=12, mat_index=2)
    L.make_object("OUT_MetalDetector", bm, coll, (mats["guard"], mats["dark"], mats["red"]), bevel=0.01, parent=parent)


def build_bark_belt(coll, mats):
    root = empty("BB_BarkBelt", coll, None, (0, 0, 0), 0.4)
    bm = bmesh.new()
    pts = [(BELT_TAIL_Y, BELT_LOW_Z), (BELT_BEND_Y, BELT_LOW_Z), (BELT_HEAD_Y, BELT_HIGH_Z)]
    hw = BELT_W / 2
    # Belt surface with cleats.
    for (y0, z0), (y1, z1) in zip(pts, pts[1:]):
        L.add_beam(bm, (0, y0, z0 - 0.01), (0, y1, z1 - 0.01), BELT_W, 0.02, up=(0, 0, 1) if z0 == z1 else (0, 0, 1),
                   mat_index=2)
        seg = Vector((0, y1 - y0, z1 - z0))
        n = int(seg.length / 0.4)
        for k in range(1, n):
            p = Vector((0, y0, z0)) + seg * (k / n)
            L.add_beam(bm, p + _v(-hw + 0.04, 0, 0.03), p + _v(hw - 0.04, 0, 0.03), 0.02, 0.05, mat_index=2)
        # Side frame and skirt boards.
        for x in (-hw - 0.08, hw + 0.08):
            L.add_beam(bm, (x, y0, z0 - 0.12), (x, y1, z1 - 0.12), 0.06, 0.18)
            L.add_beam(bm, (x * 0.96, y0, z0 + 0.12), (x * 0.96, y1, z1 + 0.12), 0.02, 0.22, mat_index=1)
    # Head and tail pulleys, return idlers and legs.
    for y, z in (pts[0], pts[-1]):
        pin_boss(bm, (0, y, z - 0.12), (1, 0, 0), 0.12, BELT_W + 0.05, mat_index=3)
    for k in range(9):
        t = k / 8
        y = BELT_TAIL_Y + (BELT_HEAD_Y - BELT_TAIL_Y) * t
        z = BELT_LOW_Z if y <= BELT_BEND_Y else BELT_LOW_Z + (y - BELT_BEND_Y) / (BELT_HEAD_Y - BELT_BEND_Y) * (BELT_HIGH_Z - BELT_LOW_Z)
        for x in (-hw - 0.08, hw + 0.08):
            L.add_box(bm, (0.08, 0.08, z - 0.2), L.mat((x, y, (z - 0.2) / 2)))
    # Head drive motor and discharge hood.
    L.add_cyl(bm, 0.13, 0.4, L.mat((hw + 0.35, BELT_HEAD_Y, BELT_HIGH_Z - 0.12), (0, 90, 0)), segs=16, mat_index=4)
    L.add_box(bm, (BELT_W + 0.2, 0.5, 0.04), L.mat((0, BELT_HEAD_Y + 0.15, BELT_HIGH_Z + 0.35), (-20, 0, 0)), mat_index=1)
    L.make_object("BB_BeltFrame", bm, coll, (mats["frame"], mats["guard"], mats["rubber"], mats["steel"], mats["motor"]),
                  bevel=0.004, parent=root)


def build_bark_bin(coll, mats):
    root = empty("BIN_Root", coll, None, tuple(BIN_CENTRE), 0.4)
    sx, sy, sz = BIN_SIZE
    bm = bmesh.new()
    t = 0.05
    L.add_box(bm, (sx, sy, 0.12), L.mat((0, 0, 0.18)))
    for x in (-sx / 2, sx / 2):
        L.add_box(bm, (t, sy, sz), L.mat((x, 0, 0.12 + sz / 2)))
        for k in range(6):
            L.add_box(bm, (0.08, 0.06, sz), L.mat((x * 1.02, -sy / 2 + 0.3 + k * (sy - 0.6) / 5, 0.12 + sz / 2)))
    for y in (-sy / 2, sy / 2):
        L.add_box(bm, (sx, t, sz), L.mat((0, y, 0.12 + sz / 2)))
    # Roll-off rails and rollers.
    for x in (-0.6, 0.6):
        L.add_box(bm, (0.12, sy + 0.3, 0.12), L.mat((x, 0, 0.06)), mat_index=1)
    for y in (-sy / 2 - 0.05, sy / 2 + 0.05):
        for x in (-0.6, 0.6):
            pin_boss(bm, (x, y, 0.1), (1, 0, 0), 0.09, 0.15, mat_index=1)
    L.make_object("BIN_Body", bm, coll, (mats["bin"], mats["dark"]), bevel=0.01, parent=root)
    # Bark heap inside: a mound the game scales up as the bin fills.
    heap = empty("BIN_Heap", coll, root, (0, 0, 0.24), 0.2)
    bm = bmesh.new()
    rings = []
    for k, (f, z) in enumerate(((1.0, 0.0), (0.9, 0.35), (0.6, 0.7), (0.25, 0.95))):
        rings.append([_v(f * (sx / 2 - 0.08) * math.cos(a), f * (sy / 2 - 0.08) * math.sin(a), z)
                      for a in [2 * math.pi * j / 24 for j in range(24)]])
    L.add_loft(bm, rings, cap_bottom=True, cap_top=True)
    L.make_object("BIN_HeapMesh", bm, coll, (mats["bark"],), weighted=False, parent=heap)


# --- Build and pose -----------------------------------------------------------------

def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = build_materials()
    machine = build_machine(coll, mats)
    infeed = build_vroll_conveyor("IN", coll, mats, IN_X[0], IN_X[1], IN_ROLLS, IN_X[0] + 0.3)
    build_dump_skids(coll, mats, infeed)
    outfeed = build_vroll_conveyor("OUT", coll, mats, OUT_X[0], OUT_X[1], OUT_ROLLS, OUT_X[1] - 0.3)
    build_metal_detector(coll, mats, outfeed, OUT_X[0] + 3.2)
    build_bark_belt(coll, mats)
    build_bark_bin(coll, mats)
    aim_cylinders()
    _ = (machine,)
    return {"objects": len(coll.objects)}


def tool_angle(r):
    """Arm swing that puts the tool tip at radius r from the rotor axis."""
    c = (TOOL_PIVOT_R ** 2 + TOOL_LEN ** 2 - r * r) / (2 * TOOL_PIVOT_R * TOOL_LEN)
    return math.acos(max(-1.0, min(1.0, c)))


def pose(tool_r=0.08, top_in_open=0.0, top_out_open=0.0, rotor_deg=0.0):
    """tool_r: tip radius. top_*_open: degrees the top roll arms are raised off the log line."""
    O = bpy.data.objects
    O["DB_Rotor"].rotation_euler = (math.radians(rotor_deg), 0, 0)
    for k in range(6):
        O[f"DB_Tool{k + 1}"].rotation_euler = (tool_angle(tool_r), 0, 0)
    # Raising swings the roll end up: the infeed arm reaches +X from its pivot, the
    # outfeed arm -X, so they turn opposite ways about Y.
    O["DB_InTopArm"].rotation_euler = (0, -math.radians(top_in_open), 0)
    O["DB_OutTopArm"].rotation_euler = (0, math.radians(top_out_open), 0)
    aim_cylinders()


def cylinder_range():
    out = {}
    # Arm travel: down on a log (0) to parked 15 deg up with no log.
    for ang in (0.0, 15.0):
        pose(top_in_open=ang, top_out_open=ang)
        bpy.context.view_layer.update()
        for side in ("In", "Out"):
            a = bpy.data.objects[f"DB_{side}ArmCylBarrel"].matrix_world.translation
            b = bpy.data.objects[f"DB_{side}ArmCylRod"].matrix_world.translation
            out.setdefault(side, []).append(round((a - b).length, 3))
    pose()
    return out
