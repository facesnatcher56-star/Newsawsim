"""Band headrig line: log deck, stop-loaders, chain turner, setworks carriage, band mill,
outfeed live rolls and sawyer's cab (run inside Blender).

A conventional band headrig of the size a small softwood mill runs for 0.5 m logs, in
the style of Hurdle / Corley / McDonough lines:
  - live chain log deck (3 deg, six light strands) from the log kicker's skids down to
    three stop-loader arms that hold the front log and throw it onto the carriage, and a
    two-arm chain turner between them that rolls the log against the knees
  - setworks carriage on two rails, wire-rope drive from a drum house: three headblocks,
    each a base with a sliding knee (setworks pinions on one shaft) and a hydraulic dog
  - C-frame band mill with 1.7 m wheels: lower (drive) wheel in a pit housing, upper wheel
    on a strain slide, upper guide on a vertical slide, lower guide fixed; the cutting span
    sits on the mill's saw line (z 5.73) and the frame stays behind the wheels so the sawn
    slab and boards pass clear
  - live outfeed rolls carrying the boards on to the roller bed, and a raised sawyer's cab
    with a seated sawyer looking back at the cut

Built in mill coordinates: Godot (x, y, z) = Blender (x, -z, y + 1.288), see G().

  HR_Frame        track, drum house, deck frame, band mill frame and guards, lower guide,
                  outfeed frame, cab and sawyer
  HR_DeckHead / HR_DeckTail             deck sprocket shafts (spin about X)
  HR_UpperWheel / HR_LowerWheel         band wheels (spin about X)
  HR_Band / HR_Tooth                    band strip (static) and one tooth for instancing
  HR_UpperGuide                         upper guide slide (moves along Y)
  HR_Carriage > HR_Knee1..3 > HR_Dog1..3, HR_CarWheel1..4   (carriage moves along X at
                  carriage-local x = 0 under the log centre; knees along Z; dogs along Y;
                  wheels spin about Z)
  HR_Loader1..3, HR_Turner1..2          arms (rotate about X at their pivots)
  HR_OutRoll1..n                        outfeed rolls (spin about Z)
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

COLL = "Headrig"
FLOOR = -1.288
LOG_R = 0.245

# Saw line and band mill.
SAW_X = 21.9
SAW_Z = 5.73
WHEEL_R = 0.85
WHEEL_Z = SAW_Z - WHEEL_R
UPPER_Y = 2.95
LOWER_Y = -0.95
BAND_W = 0.26
BAND_FRONT_X = SAW_X - 0.13
WHEEL_T = 0.24
LOWER_GUIDE_Y = -0.12
UPPER_GUIDE_Y = 0.80                    # guide bottom, rest (above the biggest log)
TOOTH_PITCH = 0.0445
# Carriage.
CAR_HOME_X = 16.90                      # log centre over the carriage at home
CAR_LEN = 5.6
HEADBLOCK_X = (-1.95, 0.0, 1.95)
RAIL_Z = (6.15, 7.45)
RAIL_TOP_Y = -0.63
WHEEL_CY = -0.47
CAR_WHEEL_R = 0.16
BASE_TOP_Y = 0.0
BASE_Z = (5.95, 7.35)
KNEE_FACE_REST = 6.62                   # knee face (z) when receded
DOG_OPEN_Y = 0.92
TRACK_X = (13.0, 28.6)
DRUM_X = 12.0
# Log deck.
DECK_X = (13.9, 19.9)
DECK_Z = (3.12, 5.35)
DECK_SLOPE = math.radians(3.0)
DECK_Y0 = 0.063 + (3.25 - DECK_Z[0]) * math.tan(DECK_SLOPE)   # surface at the kicker end
STRANDS = (14.4, 15.4, 16.4, 17.4, 18.4, 19.4)
LOADER_X = (14.9, 16.9, 18.9)
TURNER_X = (15.9, 17.9)
LOADER_PIVOT = (5.48, -0.32)            # (z, y)
# The turner arms ride on the loader shaft; at rest the tip stands clear of the carriage,
# turning swings it TURN_DEG up under the log's deck-side quarter.
TURNER_PIVOT = LOADER_PIVOT
TURNER_REST_TIP = (5.85, 0.27)
TURN_DEG = 31.0
# Outfeed live rolls.
OUT_X = (22.35, 29.0)
OUT_Z = (4.8, 5.7)
OUT_TOP_Y = -0.15
OUT_ROLL_R = 0.1
# Sawyer's cab.
CAB_X = (23.6, 25.8)
CAB_Z = (2.35, 4.05)
CAB_FLOOR_Y = 0.45
CAB_ROOF_Y = 2.75


def G(x, y, z):
    return Vector((x, -z, y - FLOOR))


def deck_y(z):
    return DECK_Y0 - (z - DECK_Z[0]) * math.tan(DECK_SLOPE)


def empty(name, coll, parent=None, loc=(0, 0, 0), size=0.15):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = size
    coll.objects.link(obj)
    obj.parent = parent
    # loc is in world space; nothing in this hierarchy is rotated, so a child's location
    # is its world position less its parents'.
    p = parent
    loc = Vector(loc)
    while p is not None:
        loc -= p.location
        p = p.parent
    obj.location = loc
    return obj


def box(bm, centre, size, mat_index=0):
    L.add_box(bm, size, Matrix.Translation(centre), mat_index)


def gbox(bm, x0, x1, y0, y1, z0, z1, mat_index=0, o=Vector()):
    a, b = G(x0, y0, z0) - o, G(x1, y1, z1) - o
    lo = Vector((min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)))
    hi = Vector((max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
    box(bm, (lo + hi) / 2, hi - lo, mat_index)


def beam(bm, p0, p1, w, h, mat_index=0, o=Vector()):
    L.add_beam(bm, G(*p0) - o, G(*p1) - o, w, h, mat_index=mat_index)


def cyl_x(bm, centre, r, length, segs=20, mat_index=0):
    L.add_cyl(bm, r, length, Matrix.Translation(centre) @ L.mat(rot=(0, 90, 0)), segs=segs, mat_index=mat_index)


def cyl_y(bm, centre, r, length, segs=20, mat_index=0):
    """Along Blender Y (Godot Z)."""
    L.add_cyl(bm, r, length, Matrix.Translation(centre) @ L.mat(rot=(90, 0, 0)), segs=segs, mat_index=mat_index)


def cyl_z(bm, centre, r, length, segs=20, mat_index=0, r2=None):
    L.add_cyl(bm, r, length, Matrix.Translation(centre), segs=segs, r2=r2, mat_index=mat_index)


def plate_zy(bm, x, thick, zy, mat_index=0, o=Vector()):
    """Vertical plate at Godot x, outline as Godot (z, y) points."""
    m = Matrix(((0, 1, 0, x - o.x), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
    pts = [(-z - o.y, y - FLOOR - o.z) for z, y in zy]
    L.add_prism(bm, pts, -thick / 2, thick / 2, m, mat_index)


def build_materials():
    frame = ((0.05, 0.11, 0.16), (0.09, 0.18, 0.25), (0.15, 0.26, 0.33))
    yellow = ((0.42, 0.26, 0.012), (0.62, 0.40, 0.02), (0.78, 0.55, 0.08))
    mill = ((0.08, 0.20, 0.10), (0.13, 0.32, 0.16), (0.22, 0.42, 0.24))
    glass = ML.simple("HR_Glass", (0.35, 0.45, 0.5), 0.05, 0.0)
    glass.diffuse_color = (0.35, 0.45, 0.5, 0.3)
    bsdf = next((n for n in glass.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is not None:
        bsdf.inputs['Alpha'].default_value = 0.25
    for attr, value in (("blend_method", 'BLEND'), ("surface_render_method", 'BLENDED')):
        if hasattr(glass, attr):
            try:
                setattr(glass, attr, value)
            except TypeError:
                pass
    return {
        "frame": ML.painted_steel("HR_Frame", *frame, chip_amount=0.55, dirt_height=1.2),
        "moving": ML.painted_steel("HR_Moving", *yellow, chip_amount=0.7, dirt_height=1.0),
        "mill": ML.painted_steel("HR_Mill", *mill, chip_amount=0.5, dirt_height=1.3),
        "wear": ML.simple("HR_Wear", (0.24, 0.235, 0.225), 0.38, 0.9, 50, 0.05),
        "dark": ML.painted_steel("HR_Dark", (0.02, 0.02, 0.02), (0.04, 0.04, 0.04), (0.07, 0.07, 0.065),
                                 chip_amount=0.8, dirt_height=1.5),
        "chrome": ML.simple("HR_Chrome", (0.75, 0.75, 0.74), 0.08, 1.0),
        "blade": ML.simple("HR_Blade", (0.62, 0.62, 0.64), 0.18, 1.0),
        "rubber": ML.rubber("HR_Rubber"),
        "motor": ML.painted_steel("HR_Motor", (0.03, 0.06, 0.12), (0.05, 0.10, 0.20), (0.09, 0.15, 0.27),
                                  chip_amount=0.4, dirt_height=0.5),
        "red": ML.simple("HR_Red", (0.5, 0.03, 0.02), 0.5, 0.0),
        "glass": glass,
        "concrete": ML.simple("HR_Concrete", (0.38, 0.37, 0.35), 0.9, 0.0, 30, 0.3),
        "cloth": ML.simple("HR_Cloth", (0.12, 0.16, 0.25), 0.9, 0.0),
        "skin": ML.simple("HR_Skin", (0.55, 0.38, 0.28), 0.6, 0.0),
        "vest": ML.simple("HR_Vest", (0.95, 0.45, 0.05), 0.7, 0.0),
    }


VIEWPORT = {
    "HR_Frame": ((0.09, 0.18, 0.25), 0.3, 0.55),
    "HR_Moving": ((0.62, 0.40, 0.02), 0.2, 0.55),
    "HR_Mill": ((0.13, 0.32, 0.16), 0.3, 0.55),
    "HR_Wear": ((0.30, 0.295, 0.285), 0.45, 0.42),
    "HR_Dark": ((0.04, 0.04, 0.04), 0.5, 0.5),
    "HR_Chrome": ((0.78, 0.78, 0.77), 1.0, 0.08),
    "HR_Blade": ((0.66, 0.66, 0.68), 0.9, 0.2),
    "HR_Rubber": ((0.02, 0.02, 0.02), 0.0, 0.85),
    "HR_Motor": ((0.05, 0.10, 0.20), 0.4, 0.5),
    "HR_Red": ((0.5, 0.03, 0.02), 0.0, 0.5),
    "HR_Glass": ((0.35, 0.45, 0.5), 0.1, 0.05),
    "HR_Concrete": ((0.38, 0.37, 0.35), 0.0, 0.9),
    "HR_Cloth": ((0.12, 0.16, 0.25), 0.0, 0.9),
    "HR_Skin": ((0.55, 0.38, 0.28), 0.0, 0.6),
    "HR_Vest": ((0.95, 0.45, 0.05), 0.0, 0.7),
}
MAT_ORDER = ("frame", "moving", "mill", "wear", "dark", "chrome", "blade", "rubber", "motor", "red", "glass",
             "concrete", "cloth", "skin", "vest")
M = {k: i for i, k in enumerate(MAT_ORDER)}


def make(name, bm, coll, mats, parent=None):
    return L.make_object(name, bm, coll, [mats[k] for k in MAT_ORDER], parent=parent)


# --- Track and drive -------------------------------------------------------------------

def build_track(bm):
    x0, x1 = TRACK_X
    for z in RAIL_Z:
        # Rail on a sill beam on piers.
        gbox(bm, x0, x1, RAIL_TOP_Y - 0.06, RAIL_TOP_Y, z - 0.035, z + 0.035, M["wear"])
        gbox(bm, x0, x1, RAIL_TOP_Y - 0.36, RAIL_TOP_Y - 0.06, z - 0.15, z + 0.15, M["frame"])
        x = x0 + 0.4
        while x < x1:
            gbox(bm, x - 0.18, x + 0.18, FLOOR, RAIL_TOP_Y - 0.36, z - 0.2, z + 0.2, M["concrete"])
            x += 1.6
    # Cross ties and the end bumpers.
    x = x0 + 0.4
    while x < x1:
        gbox(bm, x - 0.08, x + 0.08, RAIL_TOP_Y - 0.36, RAIL_TOP_Y - 0.2, RAIL_Z[0], RAIL_Z[1], M["frame"])
        x += 1.6
    for xe, s in ((x0, -1), (x1, 1)):
        for z in RAIL_Z:
            gbox(bm, xe - s * 0.1, xe + s * 0.25, RAIL_TOP_Y - 0.36, RAIL_TOP_Y + 0.35, z - 0.2, z + 0.2, M["frame"])
            cyl_x(bm, G(xe - s * 0.12, RAIL_TOP_Y + 0.15, z), 0.09, 0.18, mat_index=M["rubber"])
    # Wire rope drive: drum house behind the track start, return sheave at the far end.
    zc = (RAIL_Z[0] + RAIL_Z[1]) / 2
    gbox(bm, DRUM_X - 0.7, DRUM_X + 0.6, FLOOR, FLOOR + 0.12, zc - 0.9, zc + 0.9, M["concrete"])
    for s in (-1, 1):
        gbox(bm, DRUM_X - 0.5, DRUM_X + 0.4, FLOOR + 0.12, -0.3, zc + s * 0.55 - 0.06, zc + s * 0.55 + 0.06, M["frame"])
    cyl_y(bm, G(DRUM_X, -0.62, zc), 0.38, 1.0, segs=32, mat_index=M["dark"])
    for k in range(9):
        cyl_y(bm, G(DRUM_X, -0.62, zc - 0.4 + k * 0.1), 0.385, 0.012, segs=32, mat_index=M["wear"])
    gbox(bm, DRUM_X - 0.6, DRUM_X - 0.1, FLOOR + 0.12, -0.75, zc + 0.75, zc + 1.4, M["motor"])
    cyl_y(bm, G(DRUM_X - 0.35, -0.95, zc + 1.6), 0.2, 0.55, mat_index=M["motor"])
    cyl_y(bm, G(x1 + 0.35, -0.75, zc), 0.25, 0.12, segs=28, mat_index=M["dark"])
    gbox(bm, x1 + 0.2, x1 + 0.5, FLOOR, -0.75, zc - 0.15, zc + 0.15, M["frame"])
    # Rope runs under the carriage between the rails.
    for y in (-0.80, -0.70):
        gbox(bm, DRUM_X, x1 + 0.35, y - 0.008, y + 0.008, zc - 0.008, zc + 0.008, M["dark"])


# --- Log deck, stop-loaders, turner ------------------------------------------------------

def build_deck(bm):
    z0, z1 = DECK_Z
    for x in STRANDS:
        # Chain trough on a stringer.
        a, b = G(x, deck_y(z0) - 0.03, z0), G(x, deck_y(z1) - 0.03, z1)
        m, length = L.frame_between(a, b)
        L.add_box(bm, (length, 0.12, 0.02), m @ Matrix.Translation((0, 0, -0.01)), M["wear"])
        L.add_box(bm, (length, 0.1, 0.22), m @ Matrix.Translation((0, 0, -0.13)), M["frame"])
    for z in (z0 + 0.25, (z0 + z1) / 2, z1 - 0.3):
        y = deck_y(z) - 0.28
        gbox(bm, DECK_X[0], DECK_X[1], y - 0.2, y, z - 0.08, z + 0.08, M["frame"])
        for x in (DECK_X[0] + 0.2, 16.9, DECK_X[1] - 0.2):
            gbox(bm, x - 0.08, x + 0.08, FLOOR, y - 0.2, z - 0.08, z + 0.08, M["frame"])
    # Sprocket shaft bearings at both ends.
    for z in (z0 + 0.1, z1 - 0.12):
        for x in (DECK_X[0] + 0.05, DECK_X[1] - 0.05):
            gbox(bm, x - 0.1, x + 0.1, deck_y(z) - 0.32, deck_y(z) - 0.12, z - 0.09, z + 0.09, M["dark"])
    # Drive on the head shaft (deck end), +X side.
    zd = z1 - 0.12
    gbox(bm, DECK_X[1] + 0.05, DECK_X[1] + 0.45, deck_y(zd) - 0.5, deck_y(zd) - 0.05, zd - 0.2, zd + 0.2,
         M["motor"])
    cyl_y(bm, G(DECK_X[1] + 0.25, deck_y(zd) + 0.12, zd - 0.45), 0.12, 0.45, mat_index=M["motor"])
    # Stop-loader and turner shafts with their bearings and cylinders' anchors.
    pz, py = LOADER_PIVOT
    cyl_x(bm, G((DECK_X[0] + DECK_X[1]) / 2, py, pz), 0.06, DECK_X[1] - DECK_X[0], mat_index=M["dark"])
    for x in (DECK_X[0] + 0.1, 16.4, 17.4, DECK_X[1] - 0.1):
        gbox(bm, x - 0.08, x + 0.08, FLOOR, py - 0.06, pz - 0.1, pz + 0.1, M["frame"])
        cyl_x(bm, G(x, py, pz), 0.1, 0.14, mat_index=M["dark"])
    # Kicker-side lip and the stop beam the loaders sit behind.
    gbox(bm, DECK_X[0], DECK_X[1], deck_y(z1) - 0.25, deck_y(z1) + 0.02, z1 + 0.02, z1 + 0.1, M["frame"])


def build_loader(coll, mats, idx, x):
    pz, py = LOADER_PIVOT
    o = G(x, py, pz)
    root = empty("HR_Loader%d" % idx, coll, None, o, 0.25)
    bm = bmesh.new()
    # Curved arm: hub on the shaft, rising toward the deck to a stop horn above the deck end.
    zs = DECK_Z[1]
    ys = deck_y(zs)
    plate_zy(bm, x, 0.07, [(pz + 0.1, py), (pz + 0.06, py + 0.25), (zs - 0.05, ys + 0.30),
                           (zs - 0.16, ys + 0.38), (zs - 0.2, ys + 0.30), (zs - 0.08, ys + 0.12),
                           (pz - 0.12, py - 0.02), (pz, py - 0.1)], M["moving"], o)
    cyl_x(bm, G(x, py, pz) - o, 0.11, 0.12, mat_index=M["dark"])
    gbox(bm, x - 0.045, x + 0.045, ys + 0.30, ys + 0.39, zs - 0.21, zs - 0.13, M["wear"], o)
    make("HR_Loader%dMesh" % idx, bm, coll, mats, root)
    return root


def build_turner(coll, mats, idx, x):
    pz, py = TURNER_PIVOT
    o = G(x, py, pz)
    root = empty("HR_Turner%d" % idx, coll, None, o, 0.25)
    bm = bmesh.new()
    # Arm reaching up toward the carriage, with a chain loop and a dog at the tip that
    # bites the log's underside when it swings up.
    tip = TURNER_REST_TIP
    plate_zy(bm, x, 0.08, [(pz + 0.08, py), (tip[0] + 0.05, tip[1] - 0.05), (tip[0], tip[1] + 0.06),
                           (tip[0] - 0.08, tip[1] + 0.02), (pz - 0.08, py + 0.04)], M["moving"], o)
    cyl_x(bm, G(x, py, pz) - o, 0.12, 0.14, mat_index=M["dark"])
    cyl_x(bm, G(x, tip[1], tip[0]) - o, 0.07, 0.14, mat_index=M["dark"])
    for k in range(9):
        t = k / 8
        zz = pz + (tip[0] - pz) * t
        yy = py + 0.12 + (tip[1] - py) * t
        gbox(bm, x - 0.05, x + 0.05, yy - 0.015, yy + 0.015, zz - 0.04, zz + 0.04, M["dark"], o)
    gbox(bm, x - 0.04, x + 0.04, tip[1] + 0.06, tip[1] + 0.12, tip[0] - 0.03, tip[0] + 0.03, M["wear"], o)
    make("HR_Turner%dMesh" % idx, bm, coll, mats, root)
    return root


def build_deck_shafts(coll, mats):
    out = []
    for name, z in (("HR_DeckTail", DECK_Z[0] + 0.1), ("HR_DeckHead", DECK_Z[1] - 0.12)):
        y = deck_y(z) - 0.03 - 0.12
        root = empty(name, coll, None, G(16.9, y, z), 0.2)
        bm = bmesh.new()
        cyl_x(bm, Vector((0, 0, 0)), 0.04, DECK_X[1] - DECK_X[0] + 0.2, mat_index=M["dark"])
        for x in STRANDS:
            L.add_cyl(bm, 0.11, 0.035, L.mat((x - 16.9, 0, 0), (0, 90, 0)), segs=16, mat_index=M["wear"])
        make(name + "Mesh", bm, coll, mats, root)
        out.append(root)
    return out


# --- Carriage --------------------------------------------------------------------------

def build_carriage(coll, mats):
    origin = G(CAR_HOME_X, 0.0, 0.0)
    car = empty("HR_Carriage", coll, None, origin, 0.5)
    bm = bmesh.new()
    hx = CAR_LEN / 2
    X = CAR_HOME_X
    o = origin
    # Main side frames over the rails, and cross members.
    for z in RAIL_Z:
        gbox(bm, X - hx, X + hx, -0.40, -0.10, z - 0.13, z + 0.13, M["frame"], o)
    for dx in (-hx + 0.1, -0.98, 0.98, hx - 0.1):
        gbox(bm, X + dx - 0.08, X + dx + 0.08, -0.36, -0.12, RAIL_Z[0], RAIL_Z[1], M["frame"], o)
    # Headblock bases with their racks, and a riding deck plate between.
    for dx in HEADBLOCK_X:
        gbox(bm, X + dx - 0.13, X + dx + 0.13, -0.40, BASE_TOP_Y - 0.03, BASE_Z[0], BASE_Z[1], M["frame"], o)
        gbox(bm, X + dx - 0.13, X + dx + 0.13, BASE_TOP_Y - 0.03, BASE_TOP_Y, BASE_Z[0], BASE_Z[1], M["wear"], o)
        for k in range(14):
            z = BASE_Z[0] + 0.25 + k * 0.08
            gbox(bm, X + dx + 0.13, X + dx + 0.15, -0.12, -0.04, z - 0.02, z + 0.02, M["dark"], o)
    gbox(bm, X - hx + 0.2, X + hx - 0.2, -0.13, -0.10, 7.0, RAIL_Z[1] + 0.12, M["wear"], o)
    # Setworks shaft along the bases, with its drive at the carriage's far end.
    cyl_x(bm, G(X, -0.08, 7.2) - o, 0.045, CAR_LEN - 0.4, mat_index=M["dark"])
    gbox(bm, X + hx - 0.5, X + hx - 0.05, -0.10, 0.35, 6.95, 7.45, M["motor"], o)
    cyl_x(bm, G(X + hx - 0.28, 0.48, 7.2) - o, 0.14, 0.4, mat_index=M["motor"])
    # Hydraulic manifold and hose reel box at the near end.
    gbox(bm, X - hx + 0.05, X - hx + 0.45, -0.10, 0.25, 6.95, 7.45, M["dark"], o)
    gbox(bm, X - hx + 0.1, X - hx + 0.4, 0.25, 0.32, 7.0, 7.4, M["red"], o)
    # Wheels.
    wheels = []
    for i, (dx, z) in enumerate([(-2.3, RAIL_Z[0]), (2.3, RAIL_Z[0]), (-2.3, RAIL_Z[1]), (2.3, RAIL_Z[1])]):
        w = empty("HR_CarWheel%d" % (i + 1), coll, car, G(X + dx, WHEEL_CY, z), 0.12)
        wb = bmesh.new()
        L.add_cyl(wb, CAR_WHEEL_R, 0.09, L.mat((0, 0, 0), (90, 0, 0)), segs=24, mat_index=M["dark"])
        L.add_cyl(wb, CAR_WHEEL_R + 0.03, 0.025, L.mat((0, 0.055, 0), (90, 0, 0)), segs=24, mat_index=M["dark"])
        for k in range(6):
            a = k * math.pi / 3
            L.add_box(wb, (0.03, 0.1, 0.03), Matrix.Translation(Vector((math.cos(a), 0, math.sin(a))) * 0.1), M["wear"])
        make("HR_CarWheel%dMesh" % (i + 1), wb, coll, mats, w)
        wheels.append(w)
        gbox(bm, X + dx - 0.12, X + dx + 0.12, WHEEL_CY - 0.05, -0.38, z - 0.1, z + 0.1, M["frame"], o)
    make("HR_CarriageMesh", bm, coll, mats, car)
    # Knees: slide on the bases (z), each with a dog on a vertical slide (y).
    for i, dx in enumerate(HEADBLOCK_X):
        x = X + dx
        ko = G(x, BASE_TOP_Y, KNEE_FACE_REST)
        knee = empty("HR_Knee%d" % (i + 1), coll, car, ko, 0.2)
        kb = bmesh.new()
        f = KNEE_FACE_REST
        # Knee casting: tall face plate, raked back, with ribs.
        plate_zy(kb, x, 0.2, [(f, 0.0), (f, 0.86), (f + 0.12, 0.92), (f + 0.42, 0.1), (f + 0.62, 0.0)],
                 M["mill"], ko)
        gbox(kb, x - 0.12, x + 0.12, 0.0, 0.08, f, f + 0.7, M["mill"], ko)
        gbox(kb, x - 0.11, x + 0.11, 0.02, 0.84, f - 0.012, f, M["wear"], ko)
        # Dog cylinder on the back of the knee.
        cyl_z(kb, G(x + 0.14, 0.95, f + 0.1) - ko, 0.05, 0.55, mat_index=M["dark"])
        make("HR_Knee%dMesh" % (i + 1), kb, coll, mats, knee)
        dog = empty("HR_Dog%d" % (i + 1), coll, knee, G(x, DOG_OPEN_Y, f), 0.15)
        do = G(x, DOG_OPEN_Y, f)
        db = bmesh.new()
        # Slide block on the knee face rails and the hooked dog bar reaching over the log.
        gbox(db, x - 0.09, x + 0.09, DOG_OPEN_Y - 0.08, DOG_OPEN_Y + 0.12, f - 0.06, f + 0.02, M["moving"], do)
        plate_zy(db, x, 0.06, [(f - 0.04, DOG_OPEN_Y + 0.08), (f - 0.3, DOG_OPEN_Y + 0.04), (f - 0.36, DOG_OPEN_Y - 0.08),
                               (f - 0.3, DOG_OPEN_Y - 0.03), (f - 0.04, DOG_OPEN_Y - 0.02)], M["moving"], do)
        for k in range(3):
            cyl_z(db, G(x, DOG_OPEN_Y - 0.09, f - 0.12 - k * 0.08) - do, 0.012, 0.05, segs=6, r2=0.001,
                  mat_index=M["wear"])
        cyl_z(db, G(x + 0.14, DOG_OPEN_Y + 0.38, f + 0.1) - do, 0.025, 0.45, mat_index=M["chrome"])
        make("HR_Dog%dMesh" % (i + 1), db, coll, mats, dog)
    return car


# --- Band mill -------------------------------------------------------------------------

def wheel(coll, mats, name, y):
    root = empty(name, coll, None, G(SAW_X, y, WHEEL_Z), 0.4)
    bm = bmesh.new()
    # Spoked cast wheel with a crowned rim; the band rides the rim.
    L.add_lathe(bm, [(WHEEL_R - 0.08, -WHEEL_T / 2), (WHEEL_R, -WHEEL_T / 2 + 0.01), (WHEEL_R + 0.004, 0.0),
                     (WHEEL_R, WHEEL_T / 2 - 0.01), (WHEEL_R - 0.08, WHEEL_T / 2)], segs=64,
               m=L.mat(rot=(0, 0, 90)), mats=[M["mill"]], closed=True)
    L.add_cyl(bm, 0.2, WHEEL_T + 0.06, L.mat(rot=(0, 90, 0)), segs=32, mat_index=M["mill"])
    for k in range(6):
        a = k * math.pi / 3
        d = Vector((0, math.cos(a), math.sin(a)))
        m, length = L.frame_between(d * 0.18, d * (WHEEL_R - 0.07))
        L.add_box(bm, (length, 0.06, 0.14), m, M["mill"])
    cyl_x(bm, Vector((0, 0, 0)), 0.07, 0.9, mat_index=M["dark"])
    make(name + "Mesh", bm, coll, mats, root)
    return root


def band_loop(s):
    """Band centreline at distance s round the loop, as Godot (y, z) and the travel
    direction (dy, dz). Cutting span runs down at z = SAW_Z."""
    run = UPPER_Y - LOWER_Y
    total = 2 * run + 2 * math.pi * WHEEL_R
    s %= total
    if s < run:
        return (UPPER_Y - s, SAW_Z), (-1.0, 0.0)
    s -= run
    if s < math.pi * WHEEL_R:
        a = s / WHEEL_R
        return (LOWER_Y - WHEEL_R * math.sin(a), WHEEL_Z + WHEEL_R * math.cos(a)), (-math.cos(a), -math.sin(a))
    s -= math.pi * WHEEL_R
    if s < run:
        return (LOWER_Y + s, WHEEL_Z - WHEEL_R), (1.0, 0.0)
    a = (s - run) / WHEEL_R
    return (UPPER_Y + WHEEL_R * math.sin(a), WHEEL_Z - WHEEL_R * math.cos(a)), (math.cos(a), math.sin(a))


def build_band(coll, mats):
    run = UPPER_Y - LOWER_Y
    total = 2 * run + 2 * math.pi * WHEEL_R
    bm = bmesh.new()
    n = 160
    rings = []
    for i in range(n):
        (y, z), _ = band_loop(total * i / n)
        # Normal out of the loop: away from the nearer wheel centre / span centreline.
        rings.append((y, z))
    verts_a, verts_b = [], []
    for y, z in rings:
        verts_a.append(bm.verts.new(G(BAND_FRONT_X, y, z)))
        verts_b.append(bm.verts.new(G(BAND_FRONT_X + BAND_W, y, z)))
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((verts_a[i], verts_a[j], verts_b[j], verts_b[i]))
        f.material_index = M["blade"]
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.004)
    band = make("HR_Band", bm, coll, mats)
    band["no_smooth"] = 1
    # One tooth, in band-local terms: tip forward (travel +Z here, Godot) at the front
    # edge (-X), set into the band's thickness (Y).
    tb = bmesh.new()
    # Prism (u, w) -> Godot (z, x): u along the travel, w out from the band's front edge;
    # the extrusion is the band's thickness (Godot y). Blender = (gx, -gz, gy).
    L.add_prism(tb, [(0.0, 0.0), (0.03, 0.0), (0.03, -0.022)], -0.0035, 0.0035,
                Matrix(((0, 0, 1, 0), (-1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))), M["chrome"])
    tooth = make("HR_Tooth", tb, coll, mats)
    tooth.location = (SAW_X, -8.0, 4.0)
    return band, tooth


def build_mill(coll, mats):
    bm = bmesh.new()
    o = Vector()
    # C-frame: heavy column behind the wheels with arms out to both axle bearings, all on
    # the +X side of the band so the log and boards pass clear on the saw side.
    cx0, cx1 = SAW_X + 0.22, SAW_X + 0.62
    gbox(bm, SAW_X - 0.6, SAW_X + 0.9, FLOOR, FLOOR + 0.25, 3.3, 4.2, M["concrete"])
    gbox(bm, cx0, cx1, FLOOR + 0.25, UPPER_Y + 0.6, 3.45, 3.95, M["mill"])
    for y in (UPPER_Y, LOWER_Y):
        gbox(bm, cx0, cx1, y - 0.22, y + 0.22, 3.95, WHEEL_Z + 0.18, M["mill"])
        cyl_x(bm, G((cx0 + cx1) / 2, y, WHEEL_Z), 0.16, cx1 - cx0 + 0.04, mat_index=M["dark"])
    # Upper wheel strain slide and its cylinder.
    gbox(bm, cx1, cx1 + 0.12, UPPER_Y - 0.4, UPPER_Y + 0.5, WHEEL_Z - 0.2, WHEEL_Z + 0.2, M["dark"])
    cyl_z(bm, G(cx1 + 0.2, UPPER_Y + 0.45, WHEEL_Z), 0.08, 0.5, mat_index=M["dark"])
    # Lower wheel drive: motor and belt guard on the +X side.
    gbox(bm, cx1 + 0.05, cx1 + 0.75, FLOOR + 0.25, FLOOR + 0.95, 3.3, 3.95, M["motor"])
    cyl_x(bm, G(cx1 + 0.9, FLOOR + 0.6, 3.62), 0.3, 0.75, mat_index=M["motor"])
    gbox(bm, cx1 + 0.02, cx1 + 0.12, FLOOR + 0.5, LOWER_Y + 0.4, 3.5, WHEEL_Z + 0.2, M["moving"])
    # Lower wheel pit housing: the wheel turns in a pit; the housing stands round its top.
    gbox(bm, SAW_X - 0.25, SAW_X + 0.2, FLOOR, LOWER_Y + WHEEL_R + 0.12, WHEEL_Z - WHEEL_R - 0.15, WHEEL_Z - 0.1,
         M["mill"])
    gbox(bm, SAW_X - 0.25, SAW_X - 0.21, FLOOR, LOWER_Y + 0.55, WHEEL_Z - 0.1, SAW_Z - 0.06, M["mill"])
    # Upper wheel guard: hood over the back half of the wheel.
    for k in range(9):
        a = math.pi / 2 + k * math.pi / 8
        a2 = a + math.pi / 8
        p0 = (UPPER_Y + (WHEEL_R + 0.1) * math.sin(a), WHEEL_Z + (WHEEL_R + 0.1) * math.cos(a))
        p1 = (UPPER_Y + (WHEEL_R + 0.1) * math.sin(a2), WHEEL_Z + (WHEEL_R + 0.1) * math.cos(a2))
        beam(bm, (SAW_X - 0.04, p0[0], p0[1]), (SAW_X - 0.04, p1[0], p1[1]), 0.32, 0.012, M["moving"])
    gbox(bm, SAW_X - 0.2, SAW_X + 0.12, UPPER_Y - 0.1, UPPER_Y + 0.95, WHEEL_Z - 0.96, WHEEL_Z - 0.94, M["moving"])
    # Lower guide (fixed) under the cut, on an arm from the pit housing.
    gbox(bm, SAW_X - 0.02, SAW_X + 0.18, LOWER_GUIDE_Y - 0.22, LOWER_GUIDE_Y, SAW_Z - 0.13, SAW_Z - 0.006,
         M["dark"])
    gbox(bm, SAW_X - 0.02, SAW_X + 0.18, LOWER_GUIDE_Y - 0.22, LOWER_GUIDE_Y, SAW_Z + 0.006, SAW_Z + 0.04,
         M["dark"])
    gbox(bm, SAW_X + 0.05, SAW_X + 0.15, LOWER_GUIDE_Y - 0.6, LOWER_GUIDE_Y - 0.22, SAW_Z - 0.4, SAW_Z - 0.05,
         M["mill"])
    # Upper guide slide column (the moving guide block is HR_UpperGuide).
    gbox(bm, SAW_X + 0.2, SAW_X + 0.3, 0.6, UPPER_Y - 0.4, SAW_Z - 0.32, SAW_Z - 0.2, M["mill"])
    # Sawdust hopper under the lower guide.
    L.add_loft(bm, [[G(SAW_X - 0.2, -0.75, SAW_Z - 0.3), G(SAW_X + 0.3, -0.75, SAW_Z - 0.3),
                     G(SAW_X + 0.3, -0.75, SAW_Z + 0.02), G(SAW_X - 0.2, -0.75, SAW_Z + 0.02)],
                    [G(SAW_X - 0.08, FLOOR + 0.05, SAW_Z - 0.2), G(SAW_X + 0.18, FLOOR + 0.05, SAW_Z - 0.2),
                     G(SAW_X + 0.18, FLOOR + 0.05, SAW_Z - 0.05), G(SAW_X - 0.08, FLOOR + 0.05, SAW_Z - 0.05)]],
               cap_top=False, mat_index=M["dark"])
    # Safety rail along the saw side by the cut.
    for z in (SAW_Z - 1.15,):
        for x in (SAW_X - 1.4, SAW_X - 0.5):
            gbox(bm, x - 0.03, x + 0.03, FLOOR, FLOOR + 1.1, z - 0.03, z + 0.03, M["moving"])
        gbox(bm, SAW_X - 1.4, SAW_X - 0.5, FLOOR + 1.07, FLOOR + 1.13, z - 0.03, z + 0.03, M["moving"])
    return bm


def build_upper_guide(coll, mats):
    o = G(SAW_X, UPPER_GUIDE_Y, SAW_Z)
    root = empty("HR_UpperGuide", coll, None, o, 0.2)
    bm = bmesh.new()
    gbox(bm, SAW_X - 0.02, SAW_X + 0.2, UPPER_GUIDE_Y, UPPER_GUIDE_Y + 0.28, SAW_Z - 0.13, SAW_Z - 0.006, M["dark"], o)
    gbox(bm, SAW_X - 0.02, SAW_X + 0.2, UPPER_GUIDE_Y, UPPER_GUIDE_Y + 0.28, SAW_Z + 0.006, SAW_Z + 0.05, M["dark"], o)
    gbox(bm, SAW_X + 0.18, SAW_X + 0.32, UPPER_GUIDE_Y + 0.05, UPPER_GUIDE_Y + 0.45, SAW_Z - 0.34, SAW_Z - 0.0, M["mill"], o)
    cyl_z(bm, G(SAW_X + 0.25, UPPER_GUIDE_Y + 0.9, SAW_Z - 0.26) - o, 0.03, 0.9, mat_index=M["chrome"])
    make("HR_UpperGuideMesh", bm, coll, mats, root)
    return root


# --- Outfeed and cab -------------------------------------------------------------------

def build_outfeed(coll, mats, bm):
    x0, x1 = OUT_X
    z0, z1 = OUT_Z
    yc = OUT_TOP_Y - OUT_ROLL_R
    for z in (z0 - 0.06, z1 + 0.06):
        gbox(bm, x0, x1, yc - 0.15, yc + 0.06, z - 0.05, z + 0.05, M["frame"])
    x = x0 + 0.4
    while x < x1:
        for z in (z0 - 0.06, z1 + 0.06):
            gbox(bm, x - 0.05, x + 0.05, FLOOR, yc - 0.15, z - 0.05, z + 0.05, M["frame"])
        x += 1.5
    # Line-shaft drive along the far side.
    cyl_x(bm, G((x0 + x1) / 2, yc - 0.12, z0 - 0.2), 0.035, x1 - x0, mat_index=M["dark"])
    gbox(bm, x1 - 0.5, x1, FLOOR, yc - 0.15, z0 - 0.6, z0 - 0.15, M["motor"])
    rolls = []
    n = int((x1 - x0) / 0.45)
    for i in range(n):
        x = x0 + 0.225 + i * (x1 - x0 - 0.45) / (n - 1)
        r = empty("HR_OutRoll%d" % (i + 1), coll, None, G(x, yc, (z0 + z1) / 2), 0.1)
        rb = bmesh.new()
        L.add_cyl(rb, OUT_ROLL_R, z1 - z0, L.mat(rot=(90, 0, 0)), segs=20, mat_index=M["wear"])
        L.add_cyl(rb, 0.03, z1 - z0 + 0.16, L.mat(rot=(90, 0, 0)), segs=10, mat_index=M["dark"])
        for k in range(3):
            L.add_box(rb, (0.012, z1 - z0 - 0.04, 0.012),
                      Matrix.Rotation(k * 2 * math.pi / 3, 4, 'Y') @ Matrix.Translation((0, 0, OUT_ROLL_R)), M["dark"])
        make("HR_OutRoll%dMesh" % (i + 1), rb, coll, mats, r)
        rolls.append(r)
    return rolls


def build_cab(bm):
    x0, x1 = CAB_X
    z0, z1 = CAB_Z
    fy, ry = CAB_FLOOR_Y, CAB_ROOF_Y
    # Legs, floor, roof.
    for x in (x0 + 0.08, x1 - 0.08):
        for z in (z0 + 0.08, z1 - 0.08):
            gbox(bm, x - 0.07, x + 0.07, FLOOR, fy, z - 0.07, z + 0.07, M["frame"])
            gbox(bm, x - 0.05, x + 0.05, fy, ry, z - 0.05, z + 0.05, M["frame"])
    gbox(bm, x0, x1, fy - 0.12, fy, z0, z1, M["frame"])
    gbox(bm, x0 - 0.08, x1 + 0.08, ry, ry + 0.12, z0 - 0.08, z1 + 0.08, M["frame"])
    # Walls: solid lower panels, glazing above; the window to the saw side (+Z) and the
    # carriage end (-X) is full height.
    sill = fy + 0.95
    gbox(bm, x0, x1, fy, sill, z0, z0 + 0.04, M["frame"])
    gbox(bm, x1 - 0.04, x1, fy, ry, z0, z1, M["frame"])
    gbox(bm, x0, x0 + 0.04, fy, fy + 0.5, z0, z1, M["frame"])
    gbox(bm, x0, x1, fy, fy + 0.5, z1 - 0.04, z1, M["frame"])
    gbox(bm, x0 + 0.02, x0 + 0.03, fy + 0.5, ry, z0 + 0.05, z1 - 0.05, M["glass"])
    gbox(bm, x0 + 0.05, x1 - 0.05, fy + 0.5, ry, z1 - 0.03, z1 - 0.02, M["glass"])
    gbox(bm, x0 + 0.05, x1 - 0.05, sill, ry, z0 + 0.01, z0 + 0.02, M["glass"])
    for z in ((z0 + z1) / 2,):
        gbox(bm, x0, x0 + 0.05, fy + 0.5, ry, z - 0.03, z + 0.03, M["frame"])
    gbox(bm, (x0 + x1) / 2 - 0.03, (x0 + x1) / 2 + 0.03, fy + 0.5, ry, z1 - 0.05, z1, M["frame"])
    # Door and steps on the far side.
    gbox(bm, x1 - 0.95, x1 - 0.2, fy + 0.02, ry - 0.2, z0 - 0.01, z0 + 0.005, M["dark"])
    for k in range(5):
        y = fy - (k + 1) * (fy - FLOOR) / 6
        gbox(bm, x1 - 0.95, x1 - 0.25, y - 0.025, y + 0.025, z0 - 0.35 - k * 0.24, z0 - 0.1 - k * 0.24,
             M["wear"])
    beam(bm, (x1 - 0.95, fy, z0 - 0.05), (x1 - 0.95, FLOOR, z0 - 1.45), 0.04, 0.16, M["frame"])
    beam(bm, (x1 - 0.25, fy, z0 - 0.05), (x1 - 0.25, FLOOR, z0 - 1.45), 0.04, 0.16, M["frame"])
    # Console with joysticks and a screen in front of the sawyer.
    cx, cz = x0 + 0.55, z1 - 0.45
    gbox(bm, cx - 0.35, cx + 0.35, fy, fy + 0.7, cz + 0.08, cz + 0.3, M["dark"])
    gbox(bm, cx - 0.22, cx + 0.22, fy + 0.7, fy + 0.92, cz + 0.22, cz + 0.27, M["dark"])
    gbox(bm, cx - 0.2, cx + 0.2, fy + 0.72, fy + 0.9, cz + 0.215, cz + 0.22, M["motor"])


def build_sawyer(bm):
    """Seated sawyer at the console, facing the saw side (+Z) and the carriage."""
    x, z = CAB_X[0] + 0.55, CAB_Z[1] - 0.95
    fy = CAB_FLOOR_Y
    # Chair.
    gbox(bm, x - 0.25, x + 0.25, fy + 0.42, fy + 0.5, z - 0.22, z + 0.22, M["dark"])
    gbox(bm, x - 0.25, x + 0.25, fy + 0.5, fy + 1.15, z - 0.28, z - 0.2, M["dark"])
    cyl_z(bm, G(x, fy + 0.21, z), 0.04, 0.42, mat_index=M["chrome"])
    for s in (-1, 1):
        gbox(bm, x + s * 0.28 - 0.04, x + s * 0.28 + 0.04, fy + 0.62, fy + 0.68, z - 0.15, z + 0.25, M["dark"])
        # Joystick on each armrest.
        cyl_z(bm, G(x + s * 0.28, fy + 0.76, z + 0.2), 0.018, 0.16, mat_index=M["dark"])
        L.add_sphere(bm, 0.03, Matrix.Translation(G(x + s * 0.28, fy + 0.86, z + 0.2)), mat_index=M["red"])
    # Legs, torso, arms, head, hard hat.
    for s in (-1, 1):
        gbox(bm, x + s * 0.1 - 0.075, x + s * 0.1 + 0.075, fy + 0.5, fy + 0.64, z - 0.15, z + 0.28, M["cloth"])
        gbox(bm, x + s * 0.1 - 0.065, x + s * 0.1 + 0.065, fy + 0.08, fy + 0.6, z + 0.2, z + 0.32, M["cloth"])
        gbox(bm, x + s * 0.1 - 0.07, x + s * 0.1 + 0.07, fy, fy + 0.08, z + 0.18, z + 0.42, M["dark"])
    L.add_loft(bm, [[G(x - 0.19, fy + 0.6, z - 0.18), G(x + 0.19, fy + 0.6, z - 0.18), G(x + 0.19, fy + 0.6, z + 0.02),
                     G(x - 0.19, fy + 0.6, z + 0.02)],
                    [G(x - 0.22, fy + 1.12, z - 0.16), G(x + 0.22, fy + 1.12, z - 0.16),
                     G(x + 0.22, fy + 1.12, z + 0.06), G(x - 0.22, fy + 1.12, z + 0.06)]], mat_index=M["vest"])
    for s in (-1, 1):
        beam(bm, (x + s * 0.25, fy + 1.06, z - 0.05), (x + s * 0.28, fy + 0.8, z + 0.05), 0.09, 0.09, M["cloth"])
        beam(bm, (x + s * 0.28, fy + 0.8, z + 0.05), (x + s * 0.28, fy + 0.84, z + 0.2), 0.08, 0.08, M["cloth"])
        L.add_sphere(bm, 0.045, Matrix.Translation(G(x + s * 0.28, fy + 0.83, z + 0.2)), mat_index=M["skin"])
    cyl_z(bm, G(x, fy + 1.17, z - 0.05), 0.06, 0.1, mat_index=M["skin"])
    L.add_sphere(bm, 0.11, Matrix.Translation(G(x, fy + 1.32, z - 0.04)), segs=20, rings=12, mat_index=M["skin"])
    L.add_sphere(bm, 0.125, Matrix.Translation(G(x, fy + 1.37, z - 0.05)) @ Matrix.Diagonal((1.0, 1.0, 0.6, 1.0)),
                 segs=20, rings=10, mat_index=M["vest"])
    L.add_cyl(bm, 0.15, 0.015, Matrix.Translation(G(x, fy + 1.36, z - 0.03)), segs=20, mat_index=M["vest"])


def pose(loader_deg=0.0, turner_deg=0.0, knee_dz=0.0, dog_dy=0.0, carriage_dx=0.0, guide_dy=0.0):
    """Loader/turner swing (deg), knees forward toward the saw (m, -Z), dogs down (m),
    carriage along the track (m), upper guide down (m)."""
    for i in range(len(LOADER_X)):
        bpy.data.objects["HR_Loader%d" % (i + 1)].rotation_euler = (math.radians(loader_deg), 0, 0)
    for i in range(len(TURNER_X)):
        bpy.data.objects["HR_Turner%d" % (i + 1)].rotation_euler = (math.radians(turner_deg), 0, 0)
    car = bpy.data.objects["HR_Carriage"]
    car.location.x = CAR_HOME_X + carriage_dx
    for i in range(len(HEADBLOCK_X)):
        k = bpy.data.objects["HR_Knee%d" % (i + 1)]
        k.location.y = -KNEE_FACE_REST + knee_dz       # Blender Y = -Godot Z; relative to the carriage
        d = bpy.data.objects["HR_Dog%d" % (i + 1)]
        d.location.z = DOG_OPEN_Y - BASE_TOP_Y - dog_dy
    g = bpy.data.objects["HR_UpperGuide"]
    g.location.z = UPPER_GUIDE_Y - FLOOR - guide_dy


def build_all():
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    mats = build_materials()
    frame = empty("HR_Frame", coll, None, (0, 0, 0), 0.5)
    bm = bmesh.new()
    build_track(bm)
    build_deck(bm)
    mill_bm = build_mill(coll, mats)
    build_cab(bm)
    build_sawyer(bm)
    rolls = build_outfeed(coll, mats, bm)
    make("HR_FrameMesh", bm, coll, mats, frame)
    make("HR_MillMesh", mill_bm, coll, mats, frame)
    build_deck_shafts(coll, mats)
    wheel(coll, mats, "HR_UpperWheel", UPPER_Y)
    wheel(coll, mats, "HR_LowerWheel", LOWER_Y)
    build_band(coll, mats)
    build_upper_guide(coll, mats)
    build_carriage(coll, mats)
    for i, x in enumerate(LOADER_X):
        build_loader(coll, mats, i + 1, x)
    for i, x in enumerate(TURNER_X):
        build_turner(coll, mats, i + 1, x)
    return {"objects": len(coll.all_objects), "rolls": len(rolls), "deck_y0": DECK_Y0}
