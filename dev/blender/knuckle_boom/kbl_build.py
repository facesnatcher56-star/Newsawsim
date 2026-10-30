"""Stationary electric knuckleboom log loader (run inside Blender).

Modelled on the Weiler K261 / Cat 519 SM class of mill-yard loaders:
  - bolted to a steel pedestal on a concrete pad, 43 in (1092 mm) slew bearing
    with an external ring gear and a radial-piston swing motor pinion
  - on-board electric power unit (75 hp motor, gear pumps, 42 gal tank) on the
    rotating turret, counterweight at the rear, enclosed cab on the right side
  - 25 ft (7.6 m) boom and stick: twin lift cylinders under the main boom, one
    stick cylinder on top driving the stick butt like a bellcrank
  - extended V heel on the stick tip, free-swinging dangle link, hydraulic
    rotator and a bypass log grapple (single tong against a double tong)

Axes: X forward (boom direction at slew 0), Y left, Z up, metres. The root sits
on the floor at the pedestal centre. Every moving part hangs off an empty whose
origin is its pin, and the export keeps that hierarchy so the game drives the
joints by name:

  KBL_Base > KBL_Turret (slew, about Z) > KBL_Boom (about Y) > KBL_Stick (about Y)
  > KBL_Dangle (free swing) > KBL_Rotator (about Z) > KBL_TongA / KBL_TongB (about X)

Hydraulic cylinders are barrel/rod pairs of empties. Each points its local +Y at
its partner's pin with local +Z along the pin axis; in Godot (Y-up) that is
local -Z at the partner and local +Y on the pin, i.e. Node3D.look_at().
Rest pose (all joint angles 0): boom and stick straight out level, tongs closed.
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

COLL = "KnuckleBoomLoader"

# --- Geometry (metres, turret-local unless noted) ---------------------------
TURRET_Z = 1.87                 # slew bearing top above the floor
BEARING_R = 0.546               # 43 in OD / 2
BOOM_PIN = Vector((0.55, 0.0, 1.05))
L1 = 3.90                       # main boom pin to knuckle pin
L2 = 3.60                       # knuckle pin to stick tip pin
LIFT_BASE = (0.70, 0.36)        # turret (x, z); cylinders at y = +-LIFT_Y
LIFT_Y = 0.34
LIFT_LUG = (1.75, -0.45)        # boom-local (x, z)
STICK_BASE = (0.65, 0.62)       # boom-local (x, z) on the boom top bracket
STICK_BUTT = (-0.70, 0.0)       # stick-local (x, z): lever behind the knuckle pin
DANGLE_LEN = 0.33               # stick tip pin to rotator top
ROTATOR_H = 0.26
HEAD_TOP = -(DANGLE_LEN + ROTATOR_H)
TONG_PIVOT_Z = HEAD_TOP - 0.21  # rotator-local
TONG_PIVOT_Y = 0.16

# Joint limits (degrees), mirrored by the game script.
BOOM_RANGE = (-8.0, 65.0)
STICK_RANGE = (-140.0, -30.0)
TONG_OPEN = 60.0


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
    """Rotation matrix with local +Y along direction and local +Z along pin_axis."""
    y = Vector(direction).normalized()
    z = Vector(pin_axis)
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


# --- Materials ---------------------------------------------------------------
def build_materials():
    yellow = ((0.42, 0.26, 0.012), (0.62, 0.40, 0.02), (0.78, 0.55, 0.08))
    dark = ((0.018, 0.018, 0.018), (0.035, 0.035, 0.034), (0.06, 0.058, 0.055))
    grey = ((0.10, 0.10, 0.10), (0.16, 0.16, 0.155), (0.24, 0.24, 0.23))
    return {
        "yellow": ML.painted_steel("KBL_Yellow", *yellow, chip_amount=0.5, dirt_height=1.0),
        "dark": ML.painted_steel("KBL_Black", *dark, chip_amount=0.7, dirt_height=1.0),
        "grey": ML.painted_steel("KBL_Grey", *grey, chip_amount=0.4, dirt_height=0.8),
        "chrome": ML.simple("KBL_Chrome", (0.75, 0.75, 0.74), 0.08, 1.0),
        "glass": ML.simple("KBL_Glass", (0.02, 0.03, 0.035), 0.04, 0.2),
        "hose": ML.rubber("KBL_Hose"),
        "concrete": ML.simple("KBL_Concrete", (0.32, 0.31, 0.29), 0.9, 0.0, 18, 0.25),
        "steel": ML.simple("KBL_Steel", (0.20, 0.20, 0.20), 0.45, 0.9, 50, 0.05),
    }


# Colours written into the glTF (export_materials='VIEWPORT').
VIEWPORT = {
    "KBL_Yellow": ((0.62, 0.40, 0.02), 0.2, 0.55),
    "KBL_Black": ((0.03, 0.03, 0.03), 0.4, 0.55),
    "KBL_Grey": ((0.15, 0.15, 0.15), 0.4, 0.6),
    "KBL_Chrome": ((0.78, 0.78, 0.77), 1.0, 0.08),
    "KBL_Glass": ((0.03, 0.045, 0.05), 0.0, 0.05),
    "KBL_Hose": ((0.015, 0.015, 0.015), 0.0, 0.85),
    "KBL_Concrete": ((0.33, 0.32, 0.30), 0.0, 0.9),
    "KBL_Steel": ((0.22, 0.22, 0.22), 0.9, 0.45),
}


# --- Generic parts -----------------------------------------------------------
def pin_boss(bm, centre, axis, r, length, segs=20, mat_index=0):
    m, _ = L.frame_between(Vector(centre) - Vector(axis) * length / 2, Vector(centre) + Vector(axis) * length / 2)
    L.add_cyl(bm, r, length, m @ L.mat(rot=(0, 90, 0)), segs=segs, mat_index=mat_index)


def box_section(bm, stations, x0=0.0, mat_index=0):
    """Loft a closed rectangular tube through (x, z_centre, height, width) stations."""
    rings = []
    for x, zc, h, w in stations:
        rings.append([_v(x + x0, -w / 2, zc - h / 2), _v(x + x0, w / 2, zc - h / 2),
                      _v(x + x0, w / 2, zc + h / 2), _v(x + x0, -w / 2, zc + h / 2)])
    return L.add_loft(bm, rings, mat_index=mat_index)


def side_plate(bm, pts_xz, y0, y1, mat_index=0):
    return L.add_prism(bm, pts_xz, y0, y1, mat_index=mat_index)


def rounded_plate(pts, centre_xz, r, segs=10, start_deg=0.0, end_deg=180.0):
    """Append an arc of radius r around centre to a polygon point list."""
    out = list(pts)
    for k in range(segs + 1):
        a = math.radians(start_deg + (end_deg - start_deg) * k / segs)
        out.append((centre_xz[0] + r * math.cos(a), centre_xz[1] + r * math.sin(a)))
    return out


def make_cylinder_pair(coll, mats, name, parent_a, parent_b, pin_a, pin_b, pin_axis, bore_r, rod_r,
                       barrel_len, rod_len, eye_w, paint="yellow"):
    """Barrel and rod empties at their pins, each with its mesh child along local +Y."""
    a = empty(f"KBL_{name}Barrel", coll, parent_a)
    b = empty(f"KBL_{name}Rod", coll, parent_b)
    a.matrix_world = Matrix.Translation(pin_a)
    b.matrix_world = Matrix.Translation(pin_b)
    # Barrel: base eye, tube with end gland and port blocks.
    bm = bmesh.new()
    pin_boss(bm, (0, 0, 0), (0, 0, 1), bore_r * 0.85, eye_w, mat_index=0)
    L.add_rod(bm, (0, 0, 0), (0, bore_r * 1.2, 0), bore_r * 0.6, segs=16, mat_index=0)
    L.add_rod(bm, (0, bore_r * 1.0, 0), (0, barrel_len - 0.04, 0), bore_r, segs=24, mat_index=0)
    L.add_rod(bm, (0, barrel_len - 0.07, 0), (0, barrel_len, 0), bore_r * 1.12, segs=24, mat_index=0)
    L.add_rod(bm, (0, bore_r * 1.3, 0), (0, bore_r * 1.3 + 0.07, 0), bore_r * 1.1, segs=24, mat_index=0)
    for y in (bore_r * 1.6, barrel_len - 0.14):
        L.add_box(bm, (0.05, 0.06, 0.05), L.mat((bore_r + 0.02, y, 0)), mat_index=1)
    L.make_object(f"KBL_{name}BarrelMesh", bm, coll, (mats[paint], mats["steel"]), bevel=0.006,
                  parent=a)
    # Rod: chrome rod with a rod eye.
    bm = bmesh.new()
    pin_boss(bm, (0, 0, 0), (0, 0, 1), rod_r * 1.5, eye_w * 0.85, mat_index=1)
    L.add_rod(bm, (0, rod_r * 1.2, 0), (0, rod_len, 0), rod_r, segs=20, mat_index=0)
    L.add_rod(bm, (0, rod_r * 0.8, 0), (0, rod_r * 2.6, 0), rod_r * 1.25, segs=20, mat_index=1)
    L.make_object(f"KBL_{name}RodMesh", bm, coll, (mats["chrome"], mats["steel"]), bevel=0.003, parent=b)
    return a, b


def aim_cylinders(pairs):
    """Point every barrel at its rod pin and back (matrix_world, Blender side)."""
    bpy.context.view_layer.update()
    for barrel, rod, axis_obj, axis in pairs:
        pa = barrel.matrix_world.translation.copy()
        pb = rod.matrix_world.translation.copy()
        ax = (axis_obj.matrix_world.to_3x3() @ Vector(axis)).normalized()
        barrel.matrix_world = Matrix.Translation(pa) @ frame_y(pb - pa, ax).to_4x4()
        rod.matrix_world = Matrix.Translation(pb) @ frame_y(pa - pb, ax).to_4x4()
        bpy.context.view_layer.update()


# --- Static base -------------------------------------------------------------
def build_base(coll, mats, root):
    bm = bmesh.new()
    L.add_box(bm, (2.8, 2.8, 0.18), L.mat((0, 0, 0.09)), mat_index=0)
    L.add_box(bm, (2.9, 2.9, 0.02), L.mat((0, 0, 0.005)), mat_index=0)
    L.make_object("KBL_Pad", bm, coll, (mats["concrete"],), bevel=0.02, parent=root)

    bm = bmesh.new()
    # Base flange with gussets and anchor nuts, pedestal tube, top flange.
    L.add_cyl(bm, 0.82, 0.05, L.mat((0, 0, 0.205)), segs=48)
    L.add_cyl(bm, 0.50, TURRET_Z - 0.12 - 0.23, L.mat((0, 0, (0.23 + TURRET_Z - 0.12) / 2)), segs=48)
    L.add_cyl(bm, 0.62, 0.05, L.mat((0, 0, TURRET_Z - 0.145)), segs=48)
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        c, s = math.cos(a), math.sin(a)
        pts = [(0.49, 0.23), (0.80, 0.23), (0.80, 0.30), (0.49, 0.75)]
        m = Matrix.Rotation(a, 4, 'Z')
        bmesh_pts = [(x, z) for x, z in pts]
        L.add_prism(bm, bmesh_pts, -0.012, 0.012, m=m)
        for off in (-0.16, 0.16):
            p = Matrix.Rotation(a + off, 4, 'Z') @ Vector((0.70, 0, 0))
            L.add_cyl(bm, 0.022, 0.09, L.mat((p.x, p.y, 0.255)), segs=6)
        _ = (c, s)
    # Access door plate and conduit box for the collector ring feed.
    L.add_box(bm, (0.04, 0.36, 0.5), L.mat((0.505, 0, 0.75)), mat_index=0)
    L.add_box(bm, (0.12, 0.22, 0.28), L.mat((-0.53, 0.0, 0.5)), mat_index=0)
    L.make_object("KBL_Pedestal", bm, coll, (mats["grey"],), bevel=0.006, parent=root)

    # Slew bearing outer ring (fixed) with the external ring gear.
    bm = bmesh.new()
    z0 = TURRET_Z - 0.12
    L.add_lathe(bm, [(0.40, z0), (BEARING_R - 0.04, z0), (BEARING_R - 0.04, z0 + 0.10), (0.40, z0 + 0.10)],
                segs=64, m=L.mat(rot=(90, 0, 0)) @ Matrix.Diagonal((1, 1, 1, 1)), closed=True)
    teeth = 72
    for k in range(teeth):
        a = 2 * math.pi * k / teeth
        m = Matrix.Rotation(a, 4, 'Z') @ L.mat((BEARING_R - 0.015, 0, z0 + 0.05))
        L.add_box(bm, (0.04, 0.026, 0.09), m, mat_index=0)
    for k in range(24):
        a = 2 * math.pi * (k + 0.5) / 24
        L.add_cyl(bm, 0.014, 0.03, L.mat((0.46 * math.cos(a), 0.46 * math.sin(a), z0 + 0.115)), segs=6)
    L.make_object("KBL_SlewRing", bm, coll, (mats["steel"],), parent=root)


# --- Turret ------------------------------------------------------------------
def build_turret(coll, mats, turret):
    Y, D, G, ST = 0, 1, 2, 3
    tmats = (mats["yellow"], mats["dark"], mats["glass"], mats["steel"])
    bm = bmesh.new()
    # Main frame: rolled side plates on a deck, nose under the boom foot.
    frame = [(-1.50, 0.0), (0.95, 0.0), (1.05, 0.10), (1.05, 0.26), (-1.50, 0.26)]
    L.add_prism(bm, frame, -0.82, 0.82, mat_index=Y)
    # Inner slew ring (turns with the turret) and the hub.
    L.add_cyl(bm, 0.42, 0.10, L.mat((0, 0, -0.06)), segs=48, mat_index=ST)
    for k in range(24):
        a = 2 * math.pi * k / 24
        L.add_cyl(bm, 0.014, 0.03, L.mat((0.36 * math.cos(a), 0.36 * math.sin(a), 0.275)), segs=6, mat_index=ST)
    # Boom foot tower: twin clevis plates with doubler and pin bosses.
    for y0, y1 in ((0.155, 0.215), (-0.215, -0.155)):
        pts = rounded_plate([(0.05, 0.26), (1.00, 0.26)], (BOOM_PIN.x, BOOM_PIN.z), 0.26, 12, -10, 190)
        pts[2:] = [(x, z) for x, z in pts[2:]]
        tower = [(0.05, 0.26), (1.00, 0.26), (0.80, BOOM_PIN.z - 0.15)] + \
            [(BOOM_PIN.x + 0.24 * math.cos(math.radians(a)), BOOM_PIN.z + 0.24 * math.sin(math.radians(a)))
             for a in range(-40, 200, 20)] + [(0.20, 0.60)]
        L.add_prism(bm, tower, y0, y1, mat_index=Y)
        pin_boss(bm, (BOOM_PIN.x, (y0 + y1) / 2, BOOM_PIN.z), (0, 1, 0), 0.13, 0.10, mat_index=Y)
    pin_boss(bm, (BOOM_PIN.x, 0, BOOM_PIN.z), (0, 1, 0), 0.06, 0.56, mat_index=ST)
    for s in (-1, 1):
        L.add_box(bm, (0.12, 0.012, 0.012), L.mat((BOOM_PIN.x, s * 0.29, BOOM_PIN.z + 0.07)), mat_index=ST)
    # Lift cylinder base lugs.
    for s in (-1, 1):
        for dy in (-0.075, 0.075):
            y = s * LIFT_Y + dy
            lug = [(LIFT_BASE[0] - 0.16, 0.26), (LIFT_BASE[0] + 0.16, 0.26)] + \
                [(LIFT_BASE[0] + 0.11 * math.cos(math.radians(a)), LIFT_BASE[1] + 0.11 * math.sin(math.radians(a)))
                 for a in range(0, 181, 30)]
            L.add_prism(bm, lug, y - 0.015, y + 0.015, mat_index=Y)
        pin_boss(bm, (LIFT_BASE[0], s * LIFT_Y, LIFT_BASE[1]), (0, 1, 0), 0.045, 0.21, mat_index=ST)
    L.make_object("KBL_TurretFrame", bm, coll, tmats, bevel=0.008, parent=turret)

    # Power unit enclosure (electric motor, pumps, valve bank) with louvres.
    bm = bmesh.new()
    L.add_box(bm, (1.22, 1.50, 1.05), L.mat((-0.86, 0.0, 0.26 + 0.525)), mat_index=Y)
    L.add_box(bm, (1.28, 1.56, 0.05), L.mat((-0.86, 0.0, 1.335)), mat_index=Y)
    for side in (-1, 1):
        for k in range(9):
            L.add_box(bm, (0.05, 0.02, 0.012), L.mat((-1.32 + k * 0.06, side * 0.755, 0.95), (-35 * side, 0, 0)),
                      mat_index=D)
            L.add_box(bm, (0.05, 0.02, 0.012), L.mat((-0.62 + k * 0.06, side * 0.755, 0.95), (-35 * side, 0, 0)),
                      mat_index=D)
        # Door hinges and latches on the service doors.
        for x in (-1.40, -0.70):
            for z in (0.45, 1.05):
                L.add_cyl(bm, 0.018, 0.08, L.mat((x, side * 0.755, z)), segs=8, mat_index=ST)
        L.add_box(bm, (0.06, 0.02, 0.10), L.mat((-0.88, side * 0.76, 0.75)), mat_index=D)
    # Electrical disconnect / starter panel on the rear face (NEMA 12 box).
    L.add_box(bm, (0.5, 0.12, 0.6), L.mat((-1.05, 0.81, 0.80)), mat_index=D)
    L.add_cyl(bm, 0.03, 0.06, L.mat((-0.92, 0.88, 0.85), (90, 0, 0)), segs=10, mat_index=ST)
    L.make_object("KBL_PowerUnit", bm, coll, tmats, bevel=0.012, parent=turret)

    # Hydraulic tank on the left front with filler, breather and sight gauge.
    bm = bmesh.new()
    L.add_box(bm, (0.70, 0.46, 0.62), L.mat((0.05, 0.55, 0.26 + 0.31)), mat_index=Y)
    L.add_cyl(bm, 0.06, 0.06, L.mat((-0.10, 0.55, 0.91)), segs=16, mat_index=D)
    L.add_cyl(bm, 0.035, 0.10, L.mat((0.20, 0.62, 0.93)), segs=12, mat_index=D)
    L.add_box(bm, (0.03, 0.02, 0.22), L.mat((0.25, 0.785, 0.60)), mat_index=G)
    L.add_box(bm, (0.05, 0.015, 0.26), L.mat((0.25, 0.78, 0.60)), mat_index=D)
    # Return filter canister and valve bank between tank and tower.
    L.add_cyl(bm, 0.07, 0.30, L.mat((0.46, 0.60, 0.43)), segs=16, mat_index=D)
    L.add_box(bm, (0.36, 0.20, 0.18), L.mat((-0.05, 0.22, 0.40)), mat_index=ST)
    L.make_object("KBL_HydTank", bm, coll, tmats, bevel=0.01, parent=turret)

    # Counterweight: heavy curved casting at the tail.
    bm = bmesh.new()
    rings = []
    for z in (0.05, 0.95):
        ring = []
        for k in range(17):
            a = math.radians(110 + 140 * k / 16)
            ring.append(_v(-1.20 + 0.62 * math.cos(a) * 0.9, 0.80 * math.sin(a) * 1.0, z))
        ring.append(_v(-1.48, -0.80 * 0.2, z))
        rings.append(ring[:-1])
    L.add_loft(bm, rings, mat_index=Y)
    L.make_object("KBL_Counterweight", bm, coll, tmats, bevel=0.03, parent=turret)

    # Swing drive: radial-piston motor on a gearbox with its pinion in the ring gear.
    bm = bmesh.new()
    sx, sy = 0.30, 0.56
    L.add_cyl(bm, 0.11, 0.30, L.mat((sx, sy, 0.10)), segs=24, mat_index=D)
    L.add_cyl(bm, 0.15, 0.06, L.mat((sx, sy, 0.28)), segs=24, mat_index=D)
    L.add_cyl(bm, 0.09, 0.08, L.mat((sx, sy, -0.03)), segs=18, mat_index=D)
    L.add_cyl(bm, 0.075, 0.08, L.mat((sx, sy, -0.075)), segs=18, mat_index=ST)
    L.make_object("KBL_SwingDrive", bm, coll, tmats, bevel=0.006, parent=turret)

    # Cab, right side: square tube frame, reverse-slope windshield, skylight, door.
    bm = bmesh.new()
    cx0, cx1, cy0, cy1, cz0, cz1 = -0.30, 0.95, -1.80, -0.86, 0.32, 2.05
    # Floor pan and mounting bracket to the deck.
    L.add_box(bm, (cx1 - cx0, cy1 - cy0, 0.10), L.mat(((cx0 + cx1) / 2, (cy0 + cy1) / 2, cz0)), mat_index=Y)
    L.add_beam(bm, (cx0 + 0.1, -0.84, 0.14), (cx0 + 0.1, cy0 + 0.1, cz0 - 0.03), 0.12, 0.12, mat_index=Y)
    L.add_beam(bm, (cx1 - 0.15, -0.84, 0.14), (cx1 - 0.15, cy0 + 0.1, cz0 - 0.03), 0.12, 0.12, mat_index=Y)
    # Reverse-slope front: the windshield top leans forward.
    lean = 0.18
    posts = [((cx1, cy0), (cx1 + lean, cy0)), ((cx1, cy1), (cx1 + lean, cy1)),
             ((cx0, cy0), (cx0, cy0)), ((cx0, cy1), (cx0, cy1)),
             ((0.35, cy0), (0.35, cy0))]
    for (xb, yb), (xt, yt) in posts:
        L.add_beam(bm, (xb, yb, cz0), (xt, yt, cz1), 0.06, 0.06, mat_index=Y)
    # Roof with rain gutter and sunshade.
    L.add_box(bm, (cx1 + lean - cx0 + 0.08, cy1 - cy0 + 0.08, 0.08),
              L.mat(((cx0 + cx1 + lean) / 2, (cy0 + cy1) / 2, cz1 + 0.04)), mat_index=Y)
    L.add_box(bm, (0.22, cy1 - cy0 + 0.04, 0.02), L.mat((cx1 + lean + 0.14, (cy0 + cy1) / 2, cz1 - 0.02), (0, -8, 0)),
              mat_index=D)
    # Belt rails at window sill height.
    for (p0, p1) in (((cx0, cy0, 1.05), (cx1 + lean * 0.42, cy0, 1.05)),
                     ((cx0, cy1, 1.05), (cx1 + lean * 0.42, cy1, 1.05)),
                     ((cx0, cy0, 1.05), (cx0, cy1, 1.05))):
        L.add_beam(bm, p0, p1, 0.05, 0.05, mat_index=Y)
    # Lower panels (solid below the sill) on back and inner side.
    L.add_box(bm, (0.03, cy1 - cy0, 1.05 - cz0), L.mat((cx0, (cy0 + cy1) / 2, (cz0 + 1.05) / 2)), mat_index=Y)
    L.add_box(bm, (cx1 - cx0, 0.03, 1.05 - cz0), L.mat(((cx0 + cx1) / 2, cy1, (cz0 + 1.05) / 2)), mat_index=Y)
    # Door handle, mirror, wiper, beacon and work lights.
    L.add_box(bm, (0.12, 0.03, 0.03), L.mat((0.05, cy0 - 0.03, 1.15)), mat_index=ST)
    L.add_cyl(bm, 0.07, 0.10, L.mat((-0.10, (cy0 + cy1) / 2, cz1 + 0.13)), segs=16, mat_index=Y)
    for y in (cy0 + 0.15, cy1 - 0.15):
        L.add_box(bm, (0.08, 0.16, 0.10), L.mat((cx1 + lean - 0.02, y, cz1 + 0.13)), mat_index=D)
    L.add_beam(bm, (cx1 + lean * 0.5 + 0.03, (cy0 + cy1) / 2, 1.20), (cx1 + lean * 0.8 + 0.03, (cy0 + cy1) / 2, 1.72),
               0.015, 0.01, mat_index=D)
    # Seat and joystick consoles seen through the glass.
    L.add_box(bm, (0.45, 0.45, 0.10), L.mat((0.20, (cy0 + cy1) / 2, 0.75)), mat_index=D)
    L.add_box(bm, (0.10, 0.45, 0.55), L.mat((-0.02, (cy0 + cy1) / 2, 1.05), (0, -12, 0)), mat_index=D)
    for y in (cy0 + 0.12, cy1 - 0.12):
        L.add_box(bm, (0.40, 0.10, 0.30), L.mat((0.25, y, 0.62)), mat_index=D)
        L.add_cyl(bm, 0.018, 0.15, L.mat((0.40, y, 0.84)), segs=8, mat_index=D)
    L.make_object("KBL_Cab", bm, coll, tmats, bevel=0.01, parent=turret)

    # Glazing: windshield, side windows (full height on the door side), rear, skylight.
    bm = bmesh.new()
    t = 0.012
    ws = [_v(cx1, cy0 + 0.03, cz0 + 0.06), _v(cx1, cy1 - 0.03, cz0 + 0.06),
          _v(cx1 + lean, cy1 - 0.03, cz1 - 0.04), _v(cx1 + lean, cy0 + 0.03, cz1 - 0.04)]
    _glass_quad(bm, ws, t)
    for y in (cy0, cy1):
        z0 = cz0 + 0.06 if y == cy0 else 1.08
        _glass_quad(bm, [_v(cx0 + 0.03, y, z0), _v(cx1 - 0.03 + lean * (z0 - cz0) / (cz1 - cz0), y, z0),
                         _v(cx1 + lean - 0.03, y, cz1 - 0.04), _v(cx0 + 0.03, y, cz1 - 0.04)], t)
    _glass_quad(bm, [_v(cx0, cy0 + 0.03, 1.08), _v(cx0, cy1 - 0.03, 1.08), _v(cx0, cy1 - 0.03, cz1 - 0.04),
                     _v(cx0, cy0 + 0.03, cz1 - 0.04)], t)
    _glass_quad(bm, [_v(cx0 + 0.25, cy0 + 0.15, cz1 + 0.085), _v(cx1 - 0.05, cy0 + 0.15, cz1 + 0.085),
                     _v(cx1 - 0.05, cy1 - 0.15, cz1 + 0.085), _v(cx0 + 0.25, cy1 - 0.15, cz1 + 0.085)], t)
    L.make_object("KBL_CabGlass", bm, coll, (mats["glass"],), weighted=False, parent=turret)

    # Handrails round the rear deck walkway.
    bm = bmesh.new()
    for y in (-0.80, 0.80):
        L.add_rod(bm, (-1.45, y, 1.38), (-0.30, y, 1.38), 0.02, segs=8)
    for y in (-0.80, 0.80):
        for x in (-1.45, -0.30):
            L.add_rod(bm, (x, y, 1.34), (x, y, 1.75), 0.02, segs=8)
        L.add_rod(bm, (-1.45, y, 1.75), (-0.30, y, 1.75), 0.022, segs=8)
    L.add_rod(bm, (-1.45, -0.80, 1.75), (-1.45, 0.80, 1.75), 0.022, segs=8)
    L.make_object("KBL_Handrails", bm, coll, (mats["yellow"],), parent=turret)


def _glass_quad(bm, quad, t):
    n = (quad[1] - quad[0]).cross(quad[3] - quad[0]).normalized()
    a = [bm.verts.new(p - n * t / 2) for p in quad]
    b = [bm.verts.new(p + n * t / 2) for p in quad]
    faces = [bm.faces.new(a[::-1]), bm.faces.new(b)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    bmesh.ops.recalc_face_normals(bm, faces=faces)


# --- Booms -------------------------------------------------------------------
def build_boom(coll, mats, boom):
    bm = bmesh.new()
    # Fabricated box boom: deep at the lift lug, tapering to the knuckle.
    box_section(bm, [(-0.10, 0.0, 0.34, 0.30), (0.35, 0.0, 0.44, 0.30), (1.75, 0.02, 0.54, 0.30),
                     (3.10, 0.0, 0.40, 0.28), (3.62, 0.0, 0.34, 0.27)])
    # Foot: rounded butt around the pin.
    pin_boss(bm, (0, 0, 0), (0, 1, 0), 0.17, 0.30)
    # Knuckle clevis cheeks that take the stick head between them.
    for y0, y1 in ((0.13, 0.17), (-0.17, -0.13)):
        cheek = [(3.40, -0.17), (3.62, -0.17)] + \
            [(L1 + 0.20 * math.cos(math.radians(a)), 0.20 * math.sin(math.radians(a))) for a in range(-60, 181, 20)] + \
            [(3.40, 0.17)]
        L.add_prism(bm, cheek, y0, y1)
        pin_boss(bm, (L1, (y0 + y1) / 2 + (0.03 if y0 > 0 else -0.03), 0), (0, 1, 0), 0.11, 0.06)
    pin_boss(bm, (L1, 0, 0), (0, 1, 0), 0.055, 0.44, mat_index=1)
    # Lift cylinder lugs on the underside, out to the cylinder line at +-LIFT_Y.
    for s in (-1, 1):
        lug = [(LIFT_LUG[0] - 0.35, -0.24), (LIFT_LUG[0] + 0.30, -0.25)] + \
            [(LIFT_LUG[0] + 0.10 * math.cos(math.radians(a)), LIFT_LUG[1] + 0.10 * math.sin(math.radians(a)))
             for a in range(0, -181, -30)]
        for dy in (-0.07, 0.07):
            y = s * LIFT_Y + dy
            L.add_prism(bm, lug, y - 0.014, y + 0.014)
        L.add_box(bm, (0.55, abs(LIFT_Y) - 0.10, 0.03), L.mat((LIFT_LUG[0] - 0.05, s * (0.15 + (LIFT_Y - 0.10) / 2), -0.25)))
        pin_boss(bm, (LIFT_LUG[0], s * LIFT_Y, LIFT_LUG[1]), (0, 1, 0), 0.04, 0.20, mat_index=1)
    # Stick cylinder base bracket on top of the boom.
    for y in (-0.075, 0.075):
        brk = [(STICK_BASE[0] - 0.40, 0.21), (STICK_BASE[0] + 0.35, 0.23)] + \
            [(STICK_BASE[0] + 0.10 * math.cos(math.radians(a)), STICK_BASE[1] + 0.10 * math.sin(math.radians(a)))
             for a in range(0, 181, 30)]
        L.add_prism(bm, brk, y - 0.015, y + 0.015)
    pin_boss(bm, (STICK_BASE[0], 0, STICK_BASE[1]), (0, 1, 0), 0.04, 0.20, mat_index=1)
    # Top and bottom flange stiffeners and grease lines.
    for z in (-1, 1):
        L.add_beam(bm, (0.40, 0.0, z * 0.24), (3.0, 0.0, z * 0.205), 0.32, 0.012)
    # Boom work light.
    L.add_box(bm, (0.10, 0.16, 0.10), L.mat((2.4, 0.0, 0.29)), mat_index=1)
    L.make_object("KBL_BoomMesh", bm, coll, (mats["yellow"], mats["steel"]), bevel=0.01, parent=boom)

    # Hoses: lift/stick/grapple lines in clamps along the boom top.
    bm = bmesh.new()
    for y in (-0.11, -0.07, 0.07, 0.11):
        L.add_rod(bm, (STICK_BASE[0] + 0.3, y, 0.27), (3.45, y, 0.215), 0.016, segs=8)
    for x in (1.2, 2.0, 2.8):
        L.add_box(bm, (0.04, 0.30, 0.04), L.mat((x, 0, 0.26 - (x - 1.2) * 0.02)), mat_index=1)
    L.make_object("KBL_BoomHoses", bm, coll, (mats["hose"], mats["dark"]), parent=boom)


def build_stick(coll, mats, stick):
    bm = bmesh.new()
    bx, bz = STICK_BUTT
    # Stick butt (bellcrank lever) behind the pin, then a tapering box to the tip.
    box_section(bm, [(bx + 0.09, 0.0, 0.22, 0.24), (-0.20, 0.0, 0.40, 0.24), (0.40, -0.02, 0.38, 0.24),
                     (2.6, 0.0, 0.30, 0.22), (L2 - 0.12, 0.0, 0.24, 0.22)])
    pin_boss(bm, (0, 0, 0), (0, 1, 0), 0.15, 0.26)
    # Butt clevis: two cheeks carrying the stick cylinder rod eye between them.
    for y0, y1 in ((0.12, 0.16), (-0.16, -0.12)):
        cheek = [(bx + 0.30, -0.13), (bx + 0.30, 0.13)] + \
            [(bx + 0.11 * math.cos(math.radians(a)), bz + 0.11 * math.sin(math.radians(a))) for a in range(90, 271, 20)]
        L.add_prism(bm, cheek, y0, y1)
        pin_boss(bm, (bx, (y0 + y1) / 2 + (0.03 if y0 > 0 else -0.03), bz), (0, 1, 0), 0.07, 0.04)
    pin_boss(bm, (bx, 0, bz), (0, 1, 0), 0.04, 0.42, mat_index=1)
    for s in (-1, 1):  # spacer bushings either side of the rod eye
        pin_boss(bm, (bx, s * 0.085, bz), (0, 1, 0), 0.055, 0.07, mat_index=1)
    # Tip clevis that carries the dangle link pin.
    for y0, y1 in ((0.07, 0.11), (-0.11, -0.07)):
        tip = [(L2 - 0.35, 0.12), (L2 - 0.35, -0.12)] + \
            [(L2 + 0.11 * math.cos(math.radians(a)), 0.11 * math.sin(math.radians(a))) for a in range(-120, 121, 20)]
        L.add_prism(bm, tip, y0, y1)
    pin_boss(bm, (L2, 0, 0), (0, 1, 0), 0.04, 0.30, mat_index=1)
    # Extended V heel: welded plates under the tip with a V notch for butting logs.
    for y in (-0.30, 0.30):
        heel = [(L2 - 0.85, -0.10), (L2 - 0.30, -0.10), (L2 - 0.20, -0.62), (L2 - 0.42, -0.70), (L2 - 0.62, -0.50)]
        L.add_prism(bm, heel, y - 0.015, y + 0.015)
    L.add_box(bm, (0.50, 0.62, 0.02), L.mat((L2 - 0.56, 0, -0.11)))
    for y0, y1 in ((-0.30, -0.12), (0.12, 0.30)):
        L.add_prism(bm, [(L2 - 0.48, -0.10), (L2 - 0.30, -0.10), (L2 - 0.36, -0.40)], y0, y1)
    # Hose clamps.
    for x in (0.8, 1.8, 2.7):
        L.add_box(bm, (0.04, 0.27, 0.04), L.mat((x, 0, 0.20 - x * 0.012)), mat_index=1)
    L.make_object("KBL_StickMesh", bm, coll, (mats["yellow"], mats["steel"]), bevel=0.008, parent=stick)

    bm = bmesh.new()
    for y in (-0.07, 0.07):
        L.add_rod(bm, (0.25, y, 0.22), (L2 - 0.38, y, 0.15), 0.014, segs=8)
    L.make_object("KBL_StickHoses", bm, coll, (mats["hose"],), parent=stick)


def build_grapple(coll, mats, dangle, rotator):
    gm = (mats["dark"], mats["steel"], mats["yellow"])
    # Dangle link: clevis on the stick pin, cross pin at the bottom (free in both axes).
    bm = bmesh.new()
    for y in (-0.055, 0.055):
        L.add_prism(bm, [(-0.07, 0.0), (0.07, 0.0), (0.06, -DANGLE_LEN + 0.06), (-0.06, -DANGLE_LEN + 0.06)],
                    y - 0.015, y + 0.015)
        pin_boss(bm, (0, y, 0), (0, 1, 0), 0.07, 0.03)
    L.add_box(bm, (0.14, 0.14, 0.10), L.mat((0, 0, -DANGLE_LEN + 0.07)))
    pin_boss(bm, (0, 0, -DANGLE_LEN + 0.05), (1, 0, 0), 0.035, 0.22, mat_index=1)
    L.make_object("KBL_DangleMesh", bm, coll, gm, bevel=0.006, parent=dangle)

    # Rotator: hydraulic vane motor housing with its swivel and hose ports.
    bm = bmesh.new()
    L.add_cyl(bm, 0.15, ROTATOR_H, L.mat((0, 0, -DANGLE_LEN - ROTATOR_H / 2)), segs=32)
    L.add_cyl(bm, 0.17, 0.035, L.mat((0, 0, -DANGLE_LEN - ROTATOR_H + 0.02)), segs=32)
    for k in range(12):
        a = 2 * math.pi * k / 12
        L.add_cyl(bm, 0.012, 0.03, L.mat((0.155 * math.cos(a), 0.155 * math.sin(a), -DANGLE_LEN - ROTATOR_H + 0.045)),
                  segs=6, mat_index=1)
    for y in (-0.08, 0.08):
        L.add_box(bm, (0.06, 0.05, 0.05), L.mat((0.12, y, -DANGLE_LEN - 0.05)), mat_index=1)
    # Top yoke: two ears round the dangle link's cross pin.
    for x in (-0.095, 0.095):
        ear = [(-0.07, -DANGLE_LEN - 0.01), (0.07, -DANGLE_LEN - 0.01), (0.06, -DANGLE_LEN + 0.05),
               (0.0, -DANGLE_LEN + 0.10), (-0.06, -DANGLE_LEN + 0.05)]
        L.add_prism(bm, ear, -0.015, 0.015, m=L.mat((x, 0, 0), (0, 0, 90)))
    L.add_cyl(bm, 0.12, 0.03, L.mat((0, 0, -DANGLE_LEN - 0.005)), segs=24)
    L.make_object("KBL_RotatorMesh", bm, coll, gm, bevel=0.005, parent=rotator)

    # Grapple head: side plates (log axis along X) carrying the tong pins and cylinders.
    bm = bmesh.new()
    zt, zp = HEAD_TOP, TONG_PIVOT_Z
    for x in (-0.29, 0.29):
        plate = [(-0.27, zt), (0.27, zt), (0.27, zp - 0.04), (0.18, zp - 0.12), (-0.18, zp - 0.12), (-0.27, zp - 0.04)]
        L.add_prism(bm, [(y, z) for y, z in plate], -0.015, 0.015, m=L.mat((x, 0, 0), (0, 0, 90)))
    L.add_box(bm, (0.58, 0.54, 0.03), L.mat((0, 0, zt - 0.015)))
    for s in (-1, 1):
        L.add_box(bm, (0.58, 0.03, 0.10), L.mat((0, s * 0.26, zt - 0.07)))
        pin_boss(bm, (0, s * TONG_PIVOT_Y, zp), (1, 0, 0), 0.04, 0.64, mat_index=1)
        pin_boss(bm, (0, -s * 0.18, zt - 0.07), (1, 0, 0), 0.03, 0.64, mat_index=1)
    L.make_object("KBL_HeadMesh", bm, coll, gm, bevel=0.006, parent=rotator)


def tong_curve():
    """Closed-pose tong centreline in (u inward, v down) from the pivot, plus depth per point."""
    # Sized for bundles of the mill's 0.58 m logs: tips close 1.25 m below the tong pins.
    s = 1.35
    pts = [(0.0, 0.0), (-0.10, -0.16), (-0.16, -0.38), (-0.12, -0.60), (0.02, -0.80), (0.24, -0.92), (0.44, -0.93)]
    depth = [0.17, 0.16, 0.15, 0.14, 0.12, 0.10, 0.06]
    return [(u * s, v * s) for u, v in pts], depth


def build_tong(coll, mats, tong, side, xs, width):
    """side=+1: pivot at +y, closes toward -y. xs: tine centres along X."""
    pts, depth = tong_curve()
    bm = bmesh.new()
    for xc in xs:
        rings = []
        for i, ((u, v), d) in enumerate(zip(pts, depth)):
            if i == 0:
                t = Vector((pts[1][0] - u, pts[1][1] - v))
            elif i == len(pts) - 1:
                t = Vector((u - pts[i - 1][0], v - pts[i - 1][1]))
            else:
                t = Vector((pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]))
            t.normalize()
            n = Vector((-t.y, t.x))       # in-plane normal (outer side)
            w = width if i < len(pts) - 1 else width * 0.8
            ring = []
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                uu = u + n.x * d * 0.5 * b
                vv = v + n.y * d * 0.5 * b
                ring.append(_v(xc + a * w / 2, -side * uu, vv))
            rings.append(ring)
        L.add_loft(bm, rings)
        # Hardened tip insert.
        u, v = pts[-1]
        L.add_box(bm, (width * 0.8, 0.06, 0.04), L.mat((xc, -side * (u + 0.02), v)), mat_index=1)
    # Hub around the pin and the cylinder lug above/outboard of it.
    pin_boss(bm, (sum(xs) / len(xs), 0, 0), (1, 0, 0), 0.075, (max(xs) - min(xs)) + width)
    # Rz(90) maps the prism's (x, z) outline onto (y, z) and its extrusion onto -X.
    lu, lv = TONG_LUG
    for xc in xs:
        for dx in (-0.035, 0.035):
            L.add_prism(bm, [(0.0, 0.06), (side * (lu + 0.07), lv + 0.06), (side * (lu + 0.07), lv - 0.06),
                             (side * 0.06, -0.10)],
                        -(xc + dx) - 0.012, -(xc + dx) + 0.012, m=L.mat(rot=(0, 0, 90)))
        pin_boss(bm, (xc, side * lu, lv), (1, 0, 0), 0.03, 0.10, mat_index=1)
    L.make_object(tong.name + "Mesh", bm, coll, (mats["dark"], mats["steel"]), bevel=0.006, parent=tong)


TONG_LUG = (0.20, 0.10)   # tong-local (outward, up) of the cylinder rod pin


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = build_materials()
    root = empty("KBL_Base", coll, size=0.5)
    build_base(coll, mats, root)
    turret = empty("KBL_Turret", coll, root, (0, 0, TURRET_Z), 0.4)
    build_turret(coll, mats, turret)
    boom = empty("KBL_Boom", coll, turret, tuple(BOOM_PIN), 0.3)
    build_boom(coll, mats, boom)
    stick = empty("KBL_Stick", coll, boom, (L1, 0, 0), 0.3)
    build_stick(coll, mats, stick)
    dangle = empty("KBL_Dangle", coll, stick, (L2, 0, 0), 0.2)
    rotator = empty("KBL_Rotator", coll, dangle, (0, 0, 0), 0.2)
    build_grapple(coll, mats, dangle, rotator)
    tong_a = empty("KBL_TongA", coll, rotator, (0, TONG_PIVOT_Y, TONG_PIVOT_Z), 0.1)
    tong_b = empty("KBL_TongB", coll, rotator, (0, -TONG_PIVOT_Y, TONG_PIVOT_Z), 0.1)
    build_tong(coll, mats, tong_a, +1, (0.0,), 0.15)
    build_tong(coll, mats, tong_b, -1, (-0.20, 0.20), 0.11)
    bpy.context.view_layer.update()

    pairs = []
    yv = Vector((0, 1, 0))
    tw = turret.matrix_world
    bw = boom.matrix_world
    for s in (-1, 1):
        a, b = make_cylinder_pair(
            coll, mats, f"Lift{'L' if s > 0 else 'R'}", turret, boom,
            tw @ _v(LIFT_BASE[0], s * LIFT_Y, LIFT_BASE[1]), bw @ _v(LIFT_LUG[0], s * LIFT_Y, LIFT_LUG[1]),
            yv, 0.10, 0.05, 1.35, 1.30, 0.12)
        pairs.append((a, b, turret, (0, 1, 0)))
    sw = stick.matrix_world
    a, b = make_cylinder_pair(coll, mats, "Stick", boom, stick, bw @ _v(STICK_BASE[0], 0, STICK_BASE[1]),
                              sw @ _v(STICK_BUTT[0], 0, STICK_BUTT[1]), yv, 0.09, 0.045, 2.05, 2.00, 0.12)
    pairs.append((a, b, boom, (0, 1, 0)))
    rw = rotator.matrix_world
    for name, tong, side, xc in (("TongA", tong_a, +1, 0.0), ("TongB1", tong_b, -1, -0.20), ("TongB2", tong_b, -1, 0.20)):
        tl = tong.matrix_world
        lug = tl @ _v(xc, side * TONG_LUG[0], TONG_LUG[1])
        base = rw @ _v(xc, -side * 0.18, HEAD_TOP - 0.07)
        a, b = make_cylinder_pair(coll, mats, name, rotator, tong, base, lug, Vector((1, 0, 0)),
                                  0.05, 0.025, 0.32, 0.30, 0.07, paint="dark")
        pairs.append((a, b, rotator, (1, 0, 0)))
    bpy.context.scene["kbl_pairs"] = [(a.name, b.name, ax.name, list(v)) for a, b, ax, v in pairs]
    aim_cylinders(pairs)
    return {"objects": len(coll.objects)}


def pairs():
    out = []
    for a, b, ax, v in bpy.context.scene["kbl_pairs"]:
        out.append((bpy.data.objects[a], bpy.data.objects[b], bpy.data.objects[ax], tuple(v)))
    return out


def pose(slew=0.0, boom=20.0, stick=-90.0, tong=0.0, rot=0.0):
    """Joint angles in degrees. boom/stick are elevation/relative angles (up positive)."""
    O = bpy.data.objects
    O["KBL_Turret"].rotation_euler = (0, 0, math.radians(slew))
    O["KBL_Boom"].rotation_euler = (0, -math.radians(boom), 0)
    O["KBL_Stick"].rotation_euler = (0, -math.radians(stick), 0)
    # Dangle hangs plumb: undo the boom + stick pitch.
    O["KBL_Dangle"].rotation_euler = (0, math.radians(boom + stick), 0)
    O["KBL_Rotator"].rotation_euler = (0, 0, math.radians(rot))
    O["KBL_TongA"].rotation_euler = (math.radians(tong), 0, 0)
    O["KBL_TongB"].rotation_euler = (-math.radians(tong), 0, 0)
    aim_cylinders(pairs())


def cylinder_report():
    """Pin-to-pin distance range for every cylinder across the joint limits."""
    out = {}
    combos = []
    for b in (BOOM_RANGE[0], 30.0, BOOM_RANGE[1]):
        for s in (STICK_RANGE[0], -90.0, STICK_RANGE[1]):
            combos.append((b, s, 0.0))
    combos += [(20.0, -90.0, TONG_OPEN)]
    for b, s, t in combos:
        pose(0.0, b, s, t)
        bpy.context.view_layer.update()
        for a, r, _, _ in pairs():
            d = (a.matrix_world.translation - r.matrix_world.translation).length
            lo, hi = out.get(a.name, (9e9, 0.0))
            out[a.name] = (round(min(lo, d), 3), round(max(hi, d), 3))
    return out
