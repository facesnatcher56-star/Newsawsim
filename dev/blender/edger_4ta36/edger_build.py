"""USNR 4TA36 top-arbor edger with 3 saws and top re-man (chipping) head, job 3338.

Built from the manual drawings D-105855, D-110092, D-109905, D-110009 and
D-095195. Units are inches, converted with P(); Blender axes: +X feed
direction, +Y drive side (motors), Z up. The origin is at the infeed end,
centred across the machine; the jack pads stand on z = 0 and every part is
lifted 1 in for them. The lumber line (board bottom) is 30 in above the base.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
import mesh_lib as L  # noqa: E402

COLL = "Edger_4TA36"
IN = 0.0254

LENGTH = 105.5          # frame length along feed
IN_HALF = 20.75         # half width between side plates (41.5 in inside)
PLATE = 1.25            # side plate thickness
OUT_HALF = IN_HALF + PLATE
BASE_H = 15.0           # 15 in channel base
TOP_Z = 58.5            # frame top
LL = 30.0               # lumber line
TOP_T = 1.25

FEED_X = (46.5, 86.9, 99.8)    # knurled feed rolls under the board; none ahead of the saws
FEED_R = 3.0
PRESS_R = 4.28                  # 8.56 in press rolls
BOARD = 2.0                     # press rolls drawn resting on a 2 in board
SAW_X, SAW_Z, SAW_R = 28.75, 38.2, 10.0      # saws first, 28 3/4 in from the infeed
SAW_YS = (-9.0, 0.0, 9.0)
CHIP_X, CHIP_Z, CHIP_R = 68.25, 41.5, 11.0   # 22 in top chipping head, 37 1/4 in from the outfeed, set 1/2 in
GUIDE_SHAFT_X, GUIDE_SHAFT_ZS = 5.5, (44.7, 49.4, 53.0)   # 3 stacked shifter shafts at the infeed end
LID_X0, LID_X1 = 16.0, 42.0     # hinged top lid over the saws (26 in)
# Operator-side gate openings: arch centred on the arbor (radius) over a square bottom (z).
SAW_OPEN = (SAW_X, SAW_Z, 12.5, 26.0)
CHIP_OPEN = (CHIP_X, CHIP_Z, 14.5, 30.5)
GATE_BORDER = 1.25
# The reman (chipper) section is its own box that is set up and down as a unit, split from the saw section
# just after the first press roll. The saw section and the outfeed end are the fixed edger frame.
REMAN_X0, REMAN_X1 = 49.0, 93.0  # reman side plates; the fixed plates stop 1/2 in short each side
REMAN_Z0 = 32.0                  # bottom edge of the reman side plates (fixed plates below)
YOKE_Z = 44.5                    # press roll yokes, where the air cylinder rods push

DECK_Y = 100.0                  # drive-side motor deck, top at the base height
SAW_SHEAVE_Y = (33.0, 39.5)     # saw drive plane, outboard of the chip drive so the chip arbor clears it at any set
CHIP_SHEAVE_Y = (25.5, 32.0)    # chip head drive plane, just outboard of the reman plate
FEED_SHEAVE_Y = (39.0, 42.0)    # feed motor to gearbox
MAIN_MOTOR = (80.8, SAW_Z)      # 300 hp motor shaft level with the saw arbor, belt runs straight across
FEED_MOTOR = (35.2, 24.2)       # 25 hp feed motor, 24.8 in C-C to the gearbox
GEARBOX = (10.0, 24.2)          # Rex gearbox input shaft, level with the feed motor
TOP_MOTOR = (CHIP_X, 108.4)     # 200 hp motor straight above the chip head, 66.4 in C-C
MOTOR_PLATE_Z = 96.5            # top of the hinged 1 x 27 1/2 x 51 motor plate
TOWER_X0, TOWER_X1, TOWER_X2 = 52.0, 78.0, 85.0   # reman tower: upstream wall, foot and top of the leaning downstream wall
TOWER_Z = 92.0                  # top of the reman tower under the motor plate hinge


def P(x, y, z):
    return Vector((x * IN, y * IN, z * IN))


def mat_in(x, y, z, rot=(0, 0, 0)):
    return L.mat(P(x, y, z), rot)


def box(bm, c, s, mi=0, rot=(0, 0, 0)):
    return L.add_box(bm, (s[0] * IN, s[1] * IN, s[2] * IN), mat_in(*c, rot), mi)


def span(bm, p0, p1, mi=0):
    c = [(a + b) / 2 for a, b in zip(p0, p1)]
    s = [abs(b - a) for a, b in zip(p0, p1)]
    return box(bm, c, s, mi)


def cyl(bm, c, r, length, axis='y', mi=0, segs=24, r2=None):
    rot = {'x': (0, 90, 0), 'y': (90, 0, 0), 'z': (0, 0, 0)}[axis]
    return L.add_cyl(bm, r * IN, length * IN, mat_in(*c, rot), segs=segs, r2=None if r2 is None else r2 * IN, mat_index=mi)


def rod(bm, p0, p1, r, mi=0, segs=12):
    return L.add_rod(bm, P(*p0), P(*p1), r * IN, segs=segs, mat_index=mi)


def beam(bm, p0, p1, w, h, mi=0):
    return L.add_beam(bm, P(*p0), P(*p1), w * IN, h * IN, mat_index=mi)


def lathe_y(bm, profile_in, x, z, segs=48, mats=None, closed=False):
    """Spin an (radius, y) profile in inches around an axis parallel to Y through (x, z)."""
    prof = [(r * IN, a * IN) for r, a in profile_in]
    return L.add_lathe(bm, prof, segs, L.mat(P(x, 0, z)), mats=mats, closed=closed)


def obj(name, bm, coll, mats, bevel=0.003, segs=2, parent=None, smooth=40):
    o = L.make_object(name, bm, coll, mats, bevel=bevel, bevel_segments=segs, smooth_angle=smooth)
    if parent is not None:
        o.parent = parent
    return o


def outline_band(bm, outline, y0, y1, thickness, mi=0, caps=False):
    """Closed band (belt or guard wall) following a convex XZ outline given in inches."""
    n = len(outline)
    inner = []
    for i in range(n):
        p_prev, p, p_next = Vector(outline[i - 1]), Vector(outline[i]), Vector(outline[(i + 1) % n])
        e1, e2 = (p - p_prev).normalized(), (p_next - p).normalized()
        n1, n2 = Vector((e1.y, -e1.x)), Vector((e2.y, -e2.x))
        normal = (n1 + n2).normalized()
        inner.append(p - normal * thickness)
    rings = []
    for (ox, oz), q in zip(outline, inner):
        rings.append([bm.verts.new(P(ox, y0, oz)), bm.verts.new(P(ox, y1, oz)),
                      bm.verts.new(P(q.x, y1, q.y)), bm.verts.new(P(q.x, y0, q.y))])
    faces = []
    for k in range(n):
        a, b = rings[k], rings[(k + 1) % n]
        for i in range(4):
            j = (i + 1) % 4
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mi
            faces.append(f)
    if caps:
        for y in (y0, y1):
            f = bm.faces.new([bm.verts.new(P(ox, y, oz)) for ox, oz in outline])
            f.material_index = mi
            faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def outline_plate(bm, outline, y0, y1, mi=0):
    """Flat plate with a convex XZ outline (inches) between y0 and y1."""
    a = [bm.verts.new(P(x, y0, z)) for x, z in outline]
    b = [bm.verts.new(P(x, y1, z)) for x, z in outline]
    faces = [bm.faces.new(a), bm.faces.new(b[::-1])]
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        faces.append(bm.faces.new((a[i], b[i], b[j], a[j])))
    for f in faces:
        f.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def arch_top(cx, cz, r, x):
    return cz + math.sqrt(max(r * r - (x - cx) ** 2, 0.0))


def plate_with_openings(bm, x0, x1, y0, y1, z0, z1, openings, segs=20):
    """Side plate (XZ) between y0 and y1 with arched openings cut through it, built as column strips."""
    cuts = sorted(openings, key=lambda o: o[0])
    x = x0
    for cx, cz, r, oz in cuts:
        outline_plate(bm, [(x, z0), (cx - r, z0), (cx - r, z1), (x, z1)], y0, y1)
        for k in range(segs):
            xa = cx - r + 2 * r * k / segs
            xb = cx - r + 2 * r * (k + 1) / segs
            outline_plate(bm, [(xa, z0), (xb, z0), (xb, oz), (xa, oz)], y0, y1)
            outline_plate(bm, [(xa, arch_top(cx, cz, r, xa)), (xb, arch_top(cx, cz, r, xb)), (xb, z1), (xa, z1)], y0, y1)
        x = cx + r
    outline_plate(bm, [(x, z0), (x1, z0), (x1, z1), (x, z1)], y0, y1)


def arch_outline(cx, cz, r, oz, chamfer=0.0, steps=16):
    """Convex arch outline (XZ): square bottom at oz, semicircle of radius r round (cx, cz)."""
    pts = [(cx - r + chamfer, oz), (cx + r - chamfer, oz)]
    if chamfer:
        pts.append((cx + r, oz + chamfer))
    pts += [(cx + r * math.cos(math.pi * k / steps), cz + r * math.sin(math.pi * k / steps)) for k in range(steps + 1)]
    if chamfer:
        pts.append((cx - r, oz + chamfer))
    return pts


def radial_rot(a):
    """Euler rotation (degrees) turning a box's local Z to point radially at angle ``a`` in the XZ plane."""
    return (0, 90 - math.degrees(a), 0)


def hull_of_circles(circles, samples=48):
    pts = []
    for cx, cz, r in circles:
        for k in range(samples):
            a = 2 * math.pi * k / samples
            pts.append((round(cx + r * math.cos(a), 5), round(cz + r * math.sin(a), 5)))
    return L.convex_hull_2d(pts)


def toothed_disc(bm, x, z, y, r_tip, r_root, teeth, bore, thickness, mi=0):
    """Saw plate or sprocket: toothed outline in the XZ plane, centred on y."""
    outline = []
    for k in range(teeth):
        a0 = 2 * math.pi * k / teeth
        step = 2 * math.pi / teeth
        outline += [(a0, r_root), (a0 + step * 0.55, r_tip), (a0 + step * 0.7, r_tip - (r_tip - r_root) * 0.35)]
    ring = []
    for a, r in outline:
        c, s = math.cos(a), math.sin(a)
        ring.append([bm.verts.new(P(x + r * c, y - thickness / 2, z + r * s)), bm.verts.new(P(x + r * c, y + thickness / 2, z + r * s)),
                     bm.verts.new(P(x + bore * c, y + thickness / 2, z + bore * s)), bm.verts.new(P(x + bore * c, y - thickness / 2, z + bore * s))])
    faces = []
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        for i in range(4):
            j = (i + 1) % 4
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mi
            faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def sheave_profile(r, y0, y1, grooves, hub_r, hub_y0, hub_y1):
    """Multi-groove V-belt sheave profile (radius, y) from axis to axis."""
    prof = [(0, hub_y0), (hub_r, hub_y0), (hub_r, y0), (r, y0)]
    w = (y1 - y0) / grooves
    for g in range(grooves):
        a = y0 + g * w
        prof += [(r, a + 0.08 * w), (r - 0.55, a + 0.35 * w), (r - 0.55, a + 0.65 * w), (r, a + 0.92 * w)]
    prof += [(r, y1), (hub_r, y1), (hub_r, hub_y1), (0, hub_y1)]
    return prof


def flange_bearing(bm, x, z, y_face, outward, mi=0):
    """Piloted 4-bolt flange bearing on a plate face, housing towards ``outward`` (+1/-1)."""
    y = y_face + outward * 0.6
    box(bm, (x, y, z), (6.5, 1.2, 6.5), mi)
    cyl(bm, (x, y_face + outward * 1.9, z), 2.4, 1.6, 'y', mi, 24)
    for dx in (-2.4, 2.4):
        for dz in (-2.4, 2.4):
            cyl(bm, (x + dx, y_face + outward * 1.35, z + dz), 0.4, 0.3, 'y', mi, 6)


# ---------------------------------------------------------------- frame

def build_frame(coll, M):
    bm = bmesh.new()
    # 15 in channel base under each side plate, flanges turned inward.
    for s in (-1, 1):
        span(bm, (0, s * OUT_HALF, 0), (LENGTH, s * (OUT_HALF + 0.52), BASE_H))
        span(bm, (0, s * (OUT_HALF - 3.4), 0), (LENGTH, s * OUT_HALF, 0.65))                  # flanges stop at the web
        span(bm, (0, s * (OUT_HALF - 3.4), BASE_H - 0.65), (LENGTH, s * OUT_HALF, BASE_H))
    for x in (2.0, CHIP_X, SAW_X, LENGTH - 2.0):
        span(bm, (x - 0.26, -(OUT_HALF - 3.4), 0.65), (x + 0.26, OUT_HALF - 3.4, BASE_H - 0.65))
        span(bm, (x - 1.7, -(OUT_HALF - 3.4), BASE_H - 0.65), (x + 1.7, OUT_HALF - 3.4, BASE_H))
    # Drive-side plate: fixed saw and outfeed sections, low strip under the reman section.
    fx0, fx1 = REMAN_X0 - 0.5, REMAN_X1 + 0.5
    span(bm, (0, IN_HALF, BASE_H), (fx0, OUT_HALF, TOP_Z - TOP_T))
    span(bm, (fx1, IN_HALF, BASE_H), (LENGTH, OUT_HALF, TOP_Z - TOP_T))
    span(bm, (fx0, IN_HALF, BASE_H), (fx1, OUT_HALF, REMAN_Z0 - 0.5))
    span(bm, (LID_X0, IN_HALF, TOP_Z - TOP_T), (LID_X1, OUT_HALF, TOP_Z))         # full height beside the lid
    # Gibs on both split lines, both sides: the reman plates slide between them.
    for sgn in (-1, 1):
        for gx0, gx1 in ((fx0 - 1.0, REMAN_X0 + 0.5), (REMAN_X1 - 0.5, fx1 + 1.0)):
            span(bm, (gx0, sgn * OUT_HALF, REMAN_Z0), (gx1, sgn * (OUT_HALF + 0.75), TOP_Z - TOP_T))
    # End walls leaving the board throat open from just under the lumber line to 36.5 in.
    for x0, x1 in ((0, 1.0), (LENGTH - 1.0, LENGTH)):
        span(bm, (x0, -IN_HALF, BASE_H), (x1, IN_HALF, LL - 3.6))
        span(bm, (x0, -IN_HALF, 36.5), (x1, IN_HALF, TOP_Z - TOP_T))
    # Top plates either side of the lid opening (machined top, levelling reference).
    span(bm, (0, -OUT_HALF, TOP_Z - TOP_T), (LID_X0, OUT_HALF, TOP_Z))
    span(bm, (LID_X1, -OUT_HALF, TOP_Z - TOP_T), (fx0, OUT_HALF, TOP_Z))
    span(bm, (fx1, -OUT_HALF, TOP_Z - TOP_T), (LENGTH, OUT_HALF, TOP_Z))
    for x in (LID_X0 - 0.75, LID_X1 + 0.75):
        span(bm, (x - 0.75, -IN_HALF, TOP_Z - 4.0), (x + 0.75, IN_HALF, TOP_Z - TOP_T))
    # Cross members carrying the chip head anvil and the saw anvil.
    for x in (CHIP_X, SAW_X):
        span(bm, (x - 3.0, -IN_HALF, BASE_H), (x + 3.0, IN_HALF, LL - 2.5))
    # Jackscrew mounting pads (10 places).
    for x in (3.0, 27.0, 52.75, 78.0, 102.5):
        for s in (-1, 1):
            span(bm, (x - 2, s * (OUT_HALF - 1.6) - 2, -1.0), (x + 2, s * (OUT_HALF - 1.6) + 2, 0.0))
            cyl(bm, (x, s * (OUT_HALF - 1.6), 0.9), 0.55, 1.8, 'z', 0, 12)
    # Drive-side motor deck: plate on an outer 15 in channel and cross channels, flush with the base top.
    y0 = OUT_HALF + 0.52
    span(bm, (0, y0, BASE_H - 0.6), (LENGTH, DECK_Y, BASE_H))
    span(bm, (0, DECK_Y - 0.52, 0), (LENGTH, DECK_Y, BASE_H - 0.6))
    span(bm, (0, DECK_Y - 3.4, 0), (LENGTH, DECK_Y - 0.52, 0.65))
    for x in (0.26, 35.0, 70.0, LENGTH - 0.26):
        span(bm, (x - 0.26, y0, 0.65), (x + 0.26, DECK_Y - 0.52, BASE_H - 0.6))
        span(bm, (x - 1.7, y0, 0), (x + 1.7, DECK_Y - 0.52, 0.65))
    for x in (3.0, 52.75, 102.5):
        span(bm, (x - 2, DECK_Y - 4.0, -1.0), (x + 2, DECK_Y, 0.0))
        cyl(bm, (x, DECK_Y - 2.0, 0.9), 0.55, 1.8, 'z', 0, 12)
    o = obj("Frame", bm, coll, [M["green"]], bevel=0.004)
    o.location.z = 1.0 * IN
    build_operator_plate(coll, M)
    return o


def build_operator_plate(coll, M):
    """Fixed operator-side plate: saw section with the saw gate opening, low strip, outfeed end."""
    fx0, fx1 = REMAN_X0 - 0.5, REMAN_X1 + 0.5
    boxes = [((0, -OUT_HALF, BASE_H), (fx0, -IN_HALF, TOP_Z - TOP_T)),             # top plate sits on it
             ((LID_X0, -OUT_HALF, TOP_Z - TOP_T), (LID_X1, -IN_HALF, TOP_Z)),       # full height beside the lid
             ((fx0, -OUT_HALF, BASE_H), (fx1, -IN_HALF, REMAN_Z0 - 0.5)),
             ((fx1, -OUT_HALF, BASE_H), (LENGTH, -IN_HALF, TOP_Z - TOP_T))]
    return cut_plate("OperatorPlate", coll, M, boxes, (SAW_OPEN,))


def cut_plate(name, coll, M, boxes, openings):
    """Plate made of boxes with arched gate openings cut through it (boolean, applied)."""
    bm = bmesh.new()
    for a, b in boxes:
        span(bm, a, b)
    plate = L.make_object(name, bm, coll, [M["green"]], weighted=False)
    cutters = []
    for cx, cz, r, oz in openings:
        bmc = bmesh.new()
        outline_plate(bmc, arch_outline(cx, cz, r, oz, steps=48), -OUT_HALF - 1.0, -IN_HALF + 1.0)
        c = L.make_object("OperatorPlate_Cut", bmc, coll, weighted=False)
        md = plate.modifiers.new("Cut", 'BOOLEAN')
        md.object, md.solver = c, 'EXACT'
        cutters.append(c)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(plate.evaluated_get(dg))
    old = plate.data
    plate.modifiers.clear()
    plate.data = me
    me.shade_flat()
    bpy.data.meshes.remove(old)
    for c in cutters:
        m = c.data
        bpy.data.objects.remove(c)
        bpy.data.meshes.remove(m)
    md = plate.modifiers.new("Bevel", 'BEVEL')
    md.width, md.segments, md.limit_method, md.harden_normals = 0.004, 2, 'ANGLE', True
    plate.location.z = 1.0 * IN
    return plate


def build_bearings(coll, M):
    """Flange bearings on the plates for every shaft that passes through them."""
    bm = bmesh.new()
    for x in FEED_X:
        flange_bearing(bm, x, LL - FEED_R, -OUT_HALF, -1)
    flange_bearing(bm, SAW_X, SAW_Z, OUT_HALF, 1)
    o = obj("Bearings", bm, coll, [M["motor"]], bevel=0.002, segs=1)
    o.location.z = 1.0 * IN
    return o


# ---------------------------------------------------------------- rolls

def build_feed_rolls(coll, M):
    bm = bmesh.new()
    for x in FEED_X:
        prof = [(0, -(OUT_HALF + 3.5)), (1.5, -(OUT_HALF + 3.5)), (1.5, -IN_HALF + 0.3), (FEED_R, -IN_HALF + 0.3),
                (FEED_R, IN_HALF - 0.3), (1.5, IN_HALF - 0.3), (1.5, OUT_HALF + 1.3), (0, OUT_HALF + 1.3)]
        lathe_y(bm, prof, x, LL - FEED_R, 36, mats=[1, 1, 1, 0, 1, 1, 1])
    o = obj("FeedRolls", bm, coll, [M["knurl"], M["steel"]], bevel=0.0)
    o.location.z = 1.0 * IN
    return o


def press_roll(coll, M, name, roll_x, pivot, cyl_x):
    """Top press roll on two swing arms, pressed down by a 5 in air cylinder."""
    bm = bmesh.new()
    bms = bmesh.new()
    rz = LL + BOARD + PRESS_R
    lathe_y(bms, [(0, -19.5), (1.2, -19.5), (1.2, -17.25), (PRESS_R, -17.25), (PRESS_R, 17.25), (1.2, 17.25), (1.2, 19.5), (0, 19.5)],
            roll_x, rz, 36)
    for s in (-1, 1):
        beam(bm, (pivot[0], s * 19.2, pivot[1]), (roll_x, s * 19.2, rz), 1.0, 2.5)
        cyl(bm, (roll_x, s * 19.2, rz), 1.8, 1.0, 'y', 0, 20)
    cyl(bms, (pivot[0], 0, pivot[1]), 1.0, 2 * (IN_HALF + 0.6), 'y', 0, 16)  # pivot shaft, ends hidden in the line-bored plates
    t = (pivot[0] - cyl_x) / (pivot[0] - roll_x)
    bar_z = pivot[1] + t * (rz - pivot[1])
    span(bm, (cyl_x - 1.0, -19.7, bar_z - 1.0), (cyl_x + 1.0, 19.7, bar_z + 1.0))    # cross bar between the arms
    o = obj(name, bm, coll, [M["green"]], bevel=0.003)
    rolls = obj(name + "_Roll", bms, coll, [M["chrome"]], bevel=0.0)
    # Air cylinder: trunnion under the top plate, rod down to the cross bar.
    bmc = bmesh.new()
    span(bmc, (cyl_x - 2.0, -3.5, TOP_Z - TOP_T - 2.0), (cyl_x + 2.0, 3.5, TOP_Z - TOP_T))
    cyl(bmc, (cyl_x, 0, 51.0), 2.75, 8.0, 'z', 0, 24)
    cyl(bmc, (cyl_x, 0, TOP_Z - TOP_T - 2.6), 1.6, 1.2, 'z', 0, 16)
    cylinder = obj(name + "_AirCyl", bmc, coll, [M["hydraulic"]], bevel=0.002, segs=1)
    bmr = bmesh.new()
    rod(bmr, (cyl_x, 0, bar_z + 1.0), (cyl_x, 0, 47.0), 0.69, 0, 12)
    rodo = obj(name + "_Rod", bmr, coll, [M["chrome"]], bevel=0.0)
    for o2 in (o, rolls, cylinder, rodo):
        o2.location.z = 1.0 * IN
    return o


def roll_body(bms, roll_x, rz):
    lathe_y(bms, [(0, -19.5), (1.2, -19.5), (1.2, -17.25), (PRESS_R, -17.25), (PRESS_R, 17.25), (1.2, 17.25), (1.2, 19.5), (0, 19.5)],
            roll_x, rz, 36)


def top_air_cylinder(bmc, bmr, x, base_w, r, top_z, rod_bottom):
    """Tie-rod air cylinder standing on the top plate, rod down through the plate."""
    span(bmc, (x - base_w, -base_w, TOP_Z), (x + base_w, base_w, TOP_Z + 0.75))
    z0 = TOP_Z + 0.75
    cyl(bmc, (x, 0, (z0 + top_z) / 2), r, top_z - z0 - 2.0, 'z', 0, 24)
    for zc in (z0 + 0.5, top_z - 0.5):
        span(bmc, (x - r - 0.4, -r - 0.4, zc - 0.5), (x + r + 0.4, r + 0.4, zc + 0.5))    # end caps
    for dx in (-r, r):
        for dy in (-r, r):
            cyl(bmc, (x + dx, dy, (z0 + top_z) / 2), 0.3, top_z - z0, 'z', 0, 8)       # tie rods
    cyl(bmc, (x, 0, top_z + 0.4), 0.6, 0.8, 'z', 0, 8)                                 # air port
    rod(bmr, (x, 0, rod_bottom), (x, 0, z0 + 1.0), 0.75, 0, 12)


def press_roll_long_arm(coll, M, name, roll_x, pivot, cyl_x):
    """Press roll after the saws: long swing arms pivoting up near the top at the infeed end, running over the
    saws to the roll, pushed down through a yoke by one air cylinder standing on the top plate."""
    bm = bmesh.new()
    bms = bmesh.new()
    rz = LL + BOARD + PRESS_R
    roll_body(bms, roll_x, rz)
    for sg in (-1, 1):
        beam(bm, (pivot[0], sg * 19.2, pivot[1]), (roll_x, sg * 19.2, rz), 1.0, 2.5)
        cyl(bm, (roll_x, sg * 19.2, rz), 1.8, 1.0, 'y', 0, 20)
        span(bm, (cyl_x - 1.0, sg * 19.2 - 0.5, rz), (cyl_x + 1.0, sg * 19.2 + 0.5, YOKE_Z + 1.0))   # yoke tab
    span(bm, (cyl_x - 1.0, -19.7, YOKE_Z - 1.0), (cyl_x + 1.0, 19.7, YOKE_Z + 1.0))                   # yoke bar
    cyl(bms, (pivot[0], 0, pivot[1]), 1.0, 2 * (IN_HALF + 0.6), 'y', 0, 16)  # pivot shaft, ends hidden in the line-bored plates
    bmc, bmr = bmesh.new(), bmesh.new()
    top_air_cylinder(bmc, bmr, cyl_x, 2.75, 2.5, 71.6, YOKE_Z + 1.0)   # base stays on the fixed top, clear of the lid hinge
    objs = (obj(name, bm, coll, [M["green"]], bevel=0.003), obj(name + "_Roll", bms, coll, [M["chrome"]], bevel=0.0),
            obj(name + "_AirCyl", bmc, coll, [M["hydraulic"]], bevel=0.002, segs=1), obj(name + "_Rod", bmr, coll, [M["chrome"]], bevel=0.0))
    for o2 in objs:
        o2.location.z = 1.0 * IN


def press_roll_vertical(coll, M, name, roll_x):
    """Outfeed press roll: yoke sliding straight up and down in guides on the plates, one air cylinder on top."""
    bm = bmesh.new()
    bms = bmesh.new()
    bmg = bmesh.new()
    rz = LL + BOARD + PRESS_R
    roll_body(bms, roll_x, rz)
    top = rz + PRESS_R + 3.0
    for sg in (-1, 1):
        span(bm, (roll_x - 1.25, sg * 19.2 - 0.5, rz - 1.5), (roll_x + 1.25, sg * 19.2 + 0.5, top))     # yoke side plates
        cyl(bm, (roll_x, sg * 19.2, rz), 1.8, 1.0, 'y', 0, 20)
        for gx in (roll_x - 2.25, roll_x + 1.25):                                                     # guide strips
            span(bmg, (gx, min(sg * 19.7, sg * IN_HALF), 33.0), (gx + 1.0, max(sg * 19.7, sg * IN_HALF), TOP_Z - TOP_T))
    span(bm, (roll_x - 1.25, -19.7, top), (roll_x + 1.25, 19.7, top + 2.0))                         # cross head
    bmc, bmr = bmesh.new(), bmesh.new()
    top_air_cylinder(bmc, bmr, roll_x, 3.5, 3.4, 73.6, top + 2.0)
    objs = (obj(name, bm, coll, [M["green"]], bevel=0.003), obj(name + "_Roll", bms, coll, [M["chrome"]], bevel=0.0),
            obj(name + "_Guides", bmg, coll, [M["green"]], bevel=0.002, segs=1),
            obj(name + "_AirCyl", bmc, coll, [M["hydraulic"]], bevel=0.002, segs=1), obj(name + "_Rod", bmr, coll, [M["chrome"]], bevel=0.0))
    for o2 in objs:
        o2.location.z = 1.0 * IN


def build_press_rolls(coll, M):
    press_roll_long_arm(coll, M, "PressRoll_AfterSaws", FEED_X[0], (18.0, 56.0), 45.65)
    press_roll(coll, M, "PressRoll_AfterChipHead", FEED_X[1], (84.0, 45.0), 85.5)    # rides with the reman section
    press_roll_vertical(coll, M, "PressRoll_Outfeed", FEED_X[2])


def build_anvils(coll, M):
    bm = bmesh.new()
    span(bm, (CHIP_X - 10, -IN_HALF, LL - 2.5), (CHIP_X + 10, IN_HALF, LL))
    edges = [-IN_HALF]
    for y in SAW_YS:
        edges += [y - 0.4, y + 0.4]
    edges.append(IN_HALF)
    for k in range(0, len(edges), 2):
        span(bm, (SAW_X - 8, edges[k], LL - 2.5), (SAW_X + 8, edges[k + 1], LL))
    o = obj("Anvils", bm, coll, [M["chrome"]], bevel=0.002, segs=1)
    o.location.z = 1.0 * IN
    return o


# ---------------------------------------------------------------- heads

def build_chip_head(coll, M):
    """Top re-man chipping head in vertical saddles, lifted by a 4 in hydraulic cylinder."""
    bm = bmesh.new()       # arbor and spacers (steel)
    bmk = bmesh.new()      # chipping segments (steel) with carbide knives (slot 1)
    # Operator-side end stops in its saddle bearing, behind the access door.
    lathe_y(bm, [(0, -(OUT_HALF + 2.5)), (0.8, -(OUT_HALF + 2.5)), (1.45, -(OUT_HALF - 0.5)), (1.72, -(OUT_HALF - 0.5)),
                 (1.72, -19.0), (2.75, -19.0), (2.75, 19.0),
                 (1.72, 19.0), (1.72, CHIP_SHEAVE_Y[1] + 1.0), (0, CHIP_SHEAVE_Y[1] + 1.0)], CHIP_X, CHIP_Z, 32)
    for y in (-12.0, -6.0, 0.0, 6.0, 12.0):
        lathe_y(bmk, [(0, y - 1.31), (CHIP_R - 0.9, y - 1.31), (CHIP_R - 0.9, y + 1.31), (0, y + 1.31)], CHIP_X, CHIP_Z, 36)
        for k in range(6):
            a = 2 * math.pi * k / 6 + y * 0.05
            kx, kz = CHIP_X + (CHIP_R - 0.55) * math.cos(a), CHIP_Z + (CHIP_R - 0.55) * math.sin(a)
            box(bmk, (kx, y, kz), (0.45, 2.55, 1.1), 1, rot=radial_rot(a))
    for y in (-9.0, -3.0, 3.0, 9.0):
        cyl(bm, (CHIP_X, y, CHIP_Z), 4.0, 3.38, 'y', 0, 28)
    obj("ChipHead_Arbor", bm, coll, [M["steel"]], bevel=0.0)
    obj("ChipHead_Segments", bmk, coll, [M["steel"], M["carbide"]], bevel=0.0)
    for name in ("ChipHead_Arbor", "ChipHead_Segments"):
        bpy.data.objects[name].location.z = 1.0 * IN


def build_reman_section(coll, M):
    """The reman section's own box: side plates (operator one with the chip gate opening), top plate under the
    tower, the top anvil (hold-down shoe ahead of the head) and the arbor's drive-side bearing."""
    bm = bmesh.new()
    span(bm, (REMAN_X0, IN_HALF, REMAN_Z0), (REMAN_X1, OUT_HALF, TOP_Z - TOP_T))
    span(bm, (REMAN_X0, -OUT_HALF, TOP_Z - TOP_T), (REMAN_X1, OUT_HALF, TOP_Z))
    for x in (REMAN_X0 + 0.75, REMAN_X1 - 0.75):                                          # end stiffeners
        span(bm, (x - 0.75, -IN_HALF, TOP_Z - 4.0), (x + 0.75, IN_HALF, TOP_Z - TOP_T))
    frame = obj("Reman_Frame", bm, coll, [M["green"]], bevel=0.004)
    frame.location.z = 1.0 * IN
    cut_plate("Reman_OperatorPlate", coll, M, [((REMAN_X0, -OUT_HALF, REMAN_Z0), (REMAN_X1, -IN_HALF, TOP_Z - TOP_T))],
              (CHIP_OPEN,))
    bma = bmesh.new()
    shoe_z = CHIP_Z - CHIP_R + 0.25
    span(bma, (CHIP_X - 15.0, -(IN_HALF - 0.25), shoe_z), (CHIP_X - 11.5, IN_HALF - 0.25, shoe_z + 3.25))
    for sg in (-1, 1):                                                                     # hangers off the reman plates
        span(bma, (CHIP_X - 15.0, min(sg * (IN_HALF - 0.25), sg * IN_HALF), REMAN_Z0), (CHIP_X - 11.5, max(sg * (IN_HALF - 0.25), sg * IN_HALF), shoe_z + 3.25))
    anvil = obj("Reman_TopAnvil", bma, coll, [M["chrome"]], bevel=0.002, segs=1)
    anvil.location.z = 1.0 * IN
    bmb = bmesh.new()
    flange_bearing(bmb, CHIP_X, CHIP_Z, OUT_HALF, 1)
    brg = obj("Reman_Bearing", bmb, coll, [M["motor"]], bevel=0.002, segs=1)
    brg.location.z = 1.0 * IN


def build_saw_arbor(coll, M):
    bm = bmesh.new()
    lathe_y(bm, [(0, -(OUT_HALF + 3.0)), (0.8, -(OUT_HALF + 3.0)), (1.45, -(OUT_HALF - 0.5)), (1.72, -(OUT_HALF - 0.5)),
                 (1.72, -IN_HALF + 0.5), (3.0, -IN_HALF + 0.5),
                 (3.0, IN_HALF - 0.5), (1.72, IN_HALF - 0.5), (1.72, SAW_SHEAVE_Y[1] + 1.0), (0, SAW_SHEAVE_Y[1] + 1.0)],
            SAW_X, SAW_Z, 40)
    # Spline teeth along the arbor body.
    for k in range(16):
        a = 2 * math.pi * k / 16
        box(bm, (SAW_X + 3.0 * math.cos(a), 0, SAW_Z + 3.0 * math.sin(a)), (0.35, 2 * IN_HALF - 1.2, 0.35),
            rot=radial_rot(a))
    obj("SawArbor", bm, coll, [M["steel"]], bevel=0.0)
    bms = bmesh.new()
    for y in SAW_YS:
        toothed_disc(bms, SAW_X, SAW_Z, y, SAW_R, SAW_R - 0.45, 36, 3.05, 0.12)
        cyl(bms, (SAW_X, y - 0.3, SAW_Z), 4.2, 0.5, 'y', 0, 32)                           # saw collar
    obj("Saws", bms, coll, [M["saw"]], bevel=0.0)
    for name in ("SawArbor", "Saws"):
        bpy.data.objects[name].location.z = 1.0 * IN


def build_saw_guides(coll, M):
    """Babbitt guides straddling each saw, hung from two stacked chromed shifter shafts."""
    bm = bmesh.new()
    bmb = bmesh.new()
    bmc = bmesh.new()
    for z in GUIDE_SHAFT_ZS:
        cyl(bmc, (GUIDE_SHAFT_X, (IN_HALF - OUT_HALF - 1.0) / 2, z), 1.25, OUT_HALF + 1.0 + IN_HALF, 'y', 0, 20)
    gx, gz = SAW_X - 7.0, 37.0        # inside the saw rim, above the tallest (4 1/2 in) board
    for y in SAW_YS:
        for side in (-1, 1):
            yp = y + side * 0.6
            span(bmb, (gx - 2.5, yp - 0.4, gz - 2.0), (gx + 2.5, yp + 0.4, gz + 2.0))
            beam(bm, (gx, yp + side * 0.45, gz + 2.0), (GUIDE_SHAFT_X, yp + side * 0.45, GUIDE_SHAFT_ZS[-1] + 1.6), 1.0, 0.5)
        for z in GUIDE_SHAFT_ZS:
            cyl(bm, (GUIDE_SHAFT_X, y, z), 1.75, 3.0, 'y', 0, 20)                          # shifter bushing block
    obj("SawGuides", bm, coll, [M["green"]], bevel=0.002, segs=1)
    obj("SawGuidePads", bmb, coll, [M["babbitt"]], bevel=0.001, segs=1)
    obj("GuideShafts", bmc, coll, [M["chrome"]], bevel=0.0)
    for name in ("SawGuides", "SawGuidePads", "GuideShafts"):
        bpy.data.objects[name].location.z = 1.0 * IN


def build_operator_side(coll, M):
    """Saw setworks cylinders, valve panel, lube box and the stop bar on the operator side."""
    bm = bmesh.new()
    bmh = bmesh.new()
    span(bm, (1.5, -OUT_HALF - 1.0, 41.5), (9.5, -OUT_HALF, 56.5))                        # setworks mounting plate
    for z in GUIDE_SHAFT_ZS:
        cyl(bmh, (GUIDE_SHAFT_X, -OUT_HALF - 1.0 - 12.0, z), 1.5, 24.0, 'y', 0, 20)        # 2 x 24 in L/P cylinders
        cyl(bmh, (GUIDE_SHAFT_X, -OUT_HALF - 1.0 - 24.5, z), 1.9, 1.0, 'y', 0, 20)
    span(bm, (89.0, -OUT_HALF - 8.0, 15.5), (101.0, -OUT_HALF, 22.5))                     # lube pump box
    span(bm, (43.5, -OUT_HALF - 5.0, 15.5), (50.5, -OUT_HALF, 22.5))                      # WaterMizer cabinet
    # Infeed stop bar 4 3/4 in above the lumber line, on brackets off the plate ends.
    for s in (-1, 1):
        span(bm, (-3.0, s * IN_HALF - 0.5, LL + 2.0), (0.0, s * IN_HALF + 0.5, LL + 7.0))
    cyl(bmh, (-1.8, 0, LL + 4.75), 0.75, 2 * IN_HALF + 1.0, 'y', 0, 16)
    o = obj("OperatorSide", bm, coll, [M["green"]], bevel=0.003)
    h = obj("OperatorSideHardware", bmh, coll, [M["hydraulic"]], bevel=0.002, segs=1)
    for o2 in (o, h):
        o2.location.z = 1.0 * IN


# ---------------------------------------------------------------- moving covers

def build_lid_and_door(coll, M):
    """Top lid hinged on its downstream edge; chip head door hinged on its upstream edge.

    Origins sit on the hinge lines so rotating the object opens it.
    """
    bm = bmesh.new()
    w = LID_X1 - LID_X0
    span(bm, (-w, -IN_HALF + 0.1, 0), (0, IN_HALF - 0.1, 0.25))
    for s in (-1, 1):
        span(bm, (-w + 1.5, s * (IN_HALF - 2.0) - 0.125, -1.25), (-1.5, s * (IN_HALF - 2.0) + 0.125, 0))
    for s in (-1, 1):
        span(bm, (-w - 0.6, s * 14.0 - 1.0, -0.6), (-w + 0.6, s * 14.0 + 1.0, 0.6))           # latches
    cyl(bm, (0.4, 0, 0.3), 0.45, 2 * IN_HALF - 0.4, 'y', 0, 12)                            # 44 in piano hinge
    lid = obj("TopLid", bm, coll, [M["green"]], bevel=0.002, segs=1)
    lid.location = P(LID_X1, 0, TOP_Z + 1.0)
    lid["open_axis"] = "Y, positive angle opens"
    saw = build_gate(coll, M, "SawGate", SAW_OPEN, chamfer=0.0, swing=1)
    chip = build_gate(coll, M, "ChipGate", CHIP_OPEN, chamfer=2.0, swing=-1, pivot_gap=1.5)
    return lid, saw, chip


def build_gate(coll, M, name, opening, chamfer, swing, pivot_gap=2.5):
    """Arbor gate hung from a swing arm on the operator side.

    The gate carries the floating flange bearing that takes the arbor's nose cone, and hangs from a pin at its
    top on a short chain so it can be lined up. The arm pivots on a vertical pin at one side of the opening: swing=-1 puts it on
    the upstream edge so the gate swings left (towards the infeed), swing=+1 on the downstream edge so it swings
    right. The two pivots sit between the gates, so the saw gate swings towards the chip gate and vice versa.
    The arm's origin is on the pivot pin; a Z rotation of sign ``swing`` opens it.
    """
    cx, cz, r, oz = opening
    rd, zd = r + GATE_BORDER, oz - GATE_BORDER
    face = -(OUT_HALF + 1.25)
    top = cz + rd
    hy = -(OUT_HALF + 2.75)
    px, az = cx + swing * (rd + pivot_gap), top + 12.0
    bm = bmesh.new()       # gate (green), slot 1 steel
    outline_plate(bm, arch_outline(cx, cz, rd, zd, chamfer), face, -OUT_HALF)
    flange_bearing(bm, cx, cz, face, -1)
    cyl(bm, (cx, face - 3.1, cz), 1.5, 0.8, 'y', 1, 20)                                 # nose cone cover
    cyl(bm, (cx, face - 3.75, cz), 0.9, 0.5, 'y', 1, 6)                                # nose cone bolt
    # Yellow arbor nose cone guard: open-ended straight guard round the bolt, room for a socket but not a wrench.
    g0, g1 = face - 2.7, face - 6.7
    lathe_y(bm, [(2.3, g0), (2.3, g1), (2.12, g1), (2.12, g0)], cx, cz, 32, mats=[2, 2, 2, 2], closed=True)
    for k in range(14):                                                                 # door hold bolts
        a = math.pi * k / 13
        cyl(bm, (cx + (rd - 0.75) * math.cos(a), face - 0.2, cz + (rd - 0.75) * math.sin(a)), 0.55, 0.4, 'y', 1, 6)
    for bx in (cx - rd + 1.5, cx + rd - 1.5 - chamfer):
        cyl(bm, (bx, face - 0.2, zd + 0.9), 0.55, 0.4, 'y', 1, 6)
    span(bm, (cx - 1.0, hy - 0.4, top - 2.5), (cx + 1.0, face, top + 0.5))              # lifting lug
    L.add_torus(bm, 0.6 * IN, 0.25 * IN, mat_in(cx, hy, top + 1.2), segs=16, minor=6, mat_index=1)  # eye in the XZ plane
    span(bm, (cx + rd - 3.0, face - 2.5, cz - 3.0), (cx + rd - 2.0, face, cz + 3.0))     # handle
    box(bm, (cx + rd - 3.0, face - 0.6, cz + 7.0), (2.0, 1.2, 3.0))                     # door safety lock
    # Hanging chain from the arm down to the lug eye; links alternate 90 degrees.
    c0, c1 = az - 2.3, top + 3.3
    n = max(1, math.ceil((c0 - c1) / 1.9))
    for k in range(n + 1):
        z = c0 - (c0 - c1) * k / n
        rot = (0, 0, 90) if (n - k) % 2 == 0 else (0, 0, 0)                            # last link crosses the eye
        L.add_torus(bm, 0.7 * IN, 0.2 * IN, L.mat(P(cx, hy, z), rot, (1, 1, 1.6)), segs=16, minor=6, mat_index=1)
    for v in bm.verts:
        v.co -= P(cx, hy, 0)
    gate = obj(name, bm, coll, [M["green"], M["steel"], M["yellow"]], bevel=0.002, segs=1)
    # Swing arm: boss on the pivot pin, beam out over the gate, eye over the hanger pin.
    bma = bmesh.new()
    cyl(bma, (px, hy, az), 1.6, 3.0, 'z', 0, 20)
    span(bma, (px, hy - 1.0, az - 1.0), (cx, hy + 1.0, az + 1.0))
    cyl(bma, (cx, hy, az), 1.4, 2.0, 'z', 0, 20)
    for v in bma.verts:
        v.co -= P(px, hy, 0)
    arm = obj(name + "Arm", bma, coll, [M["green"]], bevel=0.002, segs=1)
    arm.location = P(px, hy, 1.0)
    gate.parent = arm
    gate.location = P(cx - px, 0, 0)
    arm["open_axis"] = "Z, %s angle swings the gate open to the %s" % (("negative", "left") if swing < 0 else ("positive", "right"))
    # Fixed pivot pin in two brackets on the side plate.
    bmb = bmesh.new()
    for bz in (cz - 4.0, TOP_Z - 3.0):
        span(bmb, (px - 1.5, -(OUT_HALF + 1.5) - 0.0, bz - 0.75), (px + 1.5, -OUT_HALF, bz + 0.75))
        span(bmb, (px - 0.75, hy, bz - 0.75), (px + 0.75, -(OUT_HALF + 1.5), bz + 0.75))
        cyl(bmb, (px, hy, bz), 1.4, 1.5, 'z', 0, 16)
    rod(bmb, (px, hy, cz - 5.0), (px, hy, az - 1.5), 0.75, 1, 12)
    brackets = obj(name + "Pivot", bmb, coll, [M["green"], M["steel"]], bevel=0.002, segs=1)
    brackets.location.z = 1.0 * IN
    return arm


# ---------------------------------------------------------------- drives

def motor(bm, x, z, y0, length, r, feet_z, mi_body=0, fins=24):
    """TEFC motor, drive end at y0 and fan cover towards +Y. Mirror the bmesh for a motor facing -Y."""
    y1 = y0 + length
    lathe_y(bm, [(0, y0 - 0.5), (r * 0.55, y0 - 0.5), (r * 0.8, y0), (r, y0 + 2.0), (r, y1 - 3.0), (r * 0.92, y1 - 0.6),
                 (r * 0.92, y1 + 4.0), (r * 0.6, y1 + 5.0), (0, y1 + 5.0)], x, z, 40)
    for k in range(fins):
        a = 2 * math.pi * k / fins
        if math.sin(a) < -0.55:
            continue
        box(bm, (x + (r + 0.6) * math.cos(a), (y0 + y1) / 2, z + (r + 0.6) * math.sin(a)), (0.25, length - 6.0, 1.2),
            rot=radial_rot(a))
    for yy in (y0 + 3.0, y1 - 5.0):
        span(bm, (x - r * 0.85, yy - 2.0, feet_z), (x + r * 0.85, yy + 2.0, z - r * 0.6))
    box(bm, (x, y0 + length * 0.35, z + r + 2.5), (r * 0.7, r * 0.7, 5.0))                    # terminal box
    cyl(bm, (x, y1 + 2.0, z + r * 0.95), 0.6, 0.6, 'y', 0, 8)


def mirror_y(bm, y):
    """Mirror a bmesh across the plane at y (inches), keeping faces pointing outward."""
    for v in bm.verts:
        v.co.y = 2 * y * IN - v.co.y
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])


def slide_base(bm, x0, x1, y0, y1, z0, z1, screw_x):
    """Motor slide base with the lug for its belt take-up screw."""
    span(bm, (x0, y0, z0), (x1, y1, z1))
    ym = (y0 + y1) / 2
    span(bm, (screw_x - 1.0, ym - 2.0, z0), (screw_x + 1.0, ym + 2.0, z1 + 2.5))


def build_motor_tower(bmg, bmr):
    """Reman tower: closed plate housing on the frame top with the hinged motor plate on top.

    Matches the manual photo (Figure 20): upstream edge vertical, downstream edge leaning out, one belt
    tension rod on the drive-side face at the upstream end. The chip head lift cylinder sits inside.
    """
    x0, x1, x2 = TOWER_X0, TOWER_X1, TOWER_X2
    for s in (-1, 1):
        outline_plate(bmg, [(x0, TOP_Z), (x1, TOP_Z), (x2, TOWER_Z), (x0, TOWER_Z)],
                      min(s * IN_HALF, s * OUT_HALF), max(s * IN_HALF, s * OUT_HALF))
    span(bmg, (x0, -IN_HALF, TOP_Z), (x0 + 1.25, IN_HALF, TOWER_Z))                                  # upstream wall
    outline_plate(bmg, [(x1 - 1.25, TOP_Z), (x1, TOP_Z), (x2, TOWER_Z), (x2 - 1.25, TOWER_Z)], -IN_HALF, IN_HALF)
    span(bmg, (x0, -OUT_HALF, TOWER_Z), (x2 + 0.5, OUT_HALF, TOWER_Z + 1.25))                        # cap plate
    # Hinge on the downstream edge: lugs on the cap, pin across, knuckles under the motor plate.
    hx, hz = x2 - 4.0, TOWER_Z + 2.4
    for y in (-18.0, 18.0):
        span(bmg, (hx - 1.5, y - 0.5, TOWER_Z + 1.25), (hx + 1.5, y + 0.5, hz + 1.5))
        span(bmg, (hx - 1.25, y + 0.5, hz - 1.25), (hx + 1.25, y + 2.0, MOTOR_PLATE_Z - 1.0))
    rod(bmr, (hx, -19.5, hz), (hx, 20.5, hz), 0.75, 0, 12)
    span(bmg, (CHIP_X - 13.75, -25.5, MOTOR_PLATE_Z - 1.0), (CHIP_X + 13.75, 25.5, MOTOR_PLATE_Z))  # 1 x 27 1/2 x 51 plate
    # Belt tension rod on the drive-side face: lug on the tower wall, threaded rod up through the plate.
    rx, ry, lug_z = x0 + 4.0, OUT_HALF + 1.5, 80.0
    span(bmg, (rx - 2.0, OUT_HALF, lug_z - 1.5), (rx + 2.0, OUT_HALF + 3.0, lug_z))
    outline_plate(bmg, [(rx - 0.4, lug_z - 6.0), (rx + 0.4, lug_z - 6.0), (rx + 0.4, lug_z - 1.5), (rx - 0.4, lug_z - 1.5)],
                  OUT_HALF, OUT_HALF + 3.0)                                                         # gusset
    rod(bmr, (rx, ry, lug_z - 2.5), (rx, ry, MOTOR_PLATE_Z + 3.0), 0.6, 0, 10)
    for z in (lug_z + 0.5, MOTOR_PLATE_Z - 1.6, MOTOR_PLATE_Z + 0.5):
        cyl(bmr, (rx, ry, z), 1.0, 1.0, 'z', 0, 6)


def build_drives(coll, M):
    """Three belt drives on the drive side. Every shaft runs straight across the machine (along Y); no belt guards."""
    bmm = bmesh.new()      # motors and gearbox (grey)
    bmg = bmesh.new()      # pedestal, slide bases, stand, chain case (green)
    bms = bmesh.new()      # sheaves and shafts (steel)
    bmb = bmesh.new()      # belts (rubber)
    bmr = bmesh.new()      # take-up screws, hinge pin (steel)

    # 300 hp saw motor on a pedestal so its shaft is level with the saw arbor: the belt runs straight across.
    mx, mz = MAIN_MOTOR
    r300, y300 = 12.5, 45.0
    feet = mz - r300 - 1.0
    span(bmg, (mx - 14.0, y300 - 1.0, BASE_H), (mx + 14.0, y300 + 50.0, feet - 1.5))        # fabricated pedestal
    slide_base(bmg, mx - 13.0, mx + 13.0, y300, y300 + 49.0, feet - 1.5, feet, mx + 14.0)
    rod(bmr, (mx + 14.0, y300 + 24.5, feet + 1.25), (mx + 10.0, y300 + 24.5, feet + 1.25), 0.5, 0, 10)
    motor(bmm, mx, mz, y300, 46.0, r300, feet)
    rod(bms, (mx, SAW_SHEAVE_Y[0] - 0.8, mz), (mx, y300, mz), 1.9, 0, 16)
    span(bmg, (mx - 3.0, 40.5, BASE_H), (mx + 3.0, 44.5, mz - 3.0))                          # outboard pillow block stand
    cyl(bmm, (mx, 42.5, mz), 3.0, 4.0, 'y', 0, 20)
    lathe_y(bms, sheave_profile(9.35, SAW_SHEAVE_Y[0], SAW_SHEAVE_Y[1], 10, 3.2, SAW_SHEAVE_Y[0] - 0.5, SAW_SHEAVE_Y[1] + 0.5), mx, mz, 48)
    lathe_y(bms, sheave_profile(5.65, SAW_SHEAVE_Y[0], SAW_SHEAVE_Y[1], 10, 2.8, SAW_SHEAVE_Y[0] - 0.5, SAW_SHEAVE_Y[1] + 0.5), SAW_X, SAW_Z, 40)
    outline_band(bmb, hull_of_circles([(mx, mz, 9.0), (SAW_X, SAW_Z, 5.3)]), SAW_SHEAVE_Y[0] + 0.3, SAW_SHEAVE_Y[1] - 0.3, 0.5)

    # 200 hp chipper motor on the hinged plate above the chip head; belt drops straight down the drive side.
    tx, tz = TOP_MOTOR
    bmtw, bmtr, bmcs, bmcb = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    build_motor_tower(bmtw, bmtr)
    bmt = bmesh.new()
    drive_end = 21.0
    motor(bmt, tx, tz, drive_end, 40.0, 11.0, MOTOR_PLATE_Z)
    mirror_y(bmt, drive_end)
    obj("Motor_Chipper", bmt, coll, [M["motor"]], bevel=0.004)
    rod(bmcs, (tx, drive_end, tz), (tx, CHIP_SHEAVE_Y[1] + 0.8, tz), 1.5, 0, 16)
    lathe_y(bmcs, sheave_profile(6.25, CHIP_SHEAVE_Y[0], CHIP_SHEAVE_Y[1], 10, 2.4, CHIP_SHEAVE_Y[0] - 0.5, CHIP_SHEAVE_Y[1] + 0.5), tx, tz, 40)
    lathe_y(bmcs, sheave_profile(5.65, CHIP_SHEAVE_Y[0], CHIP_SHEAVE_Y[1], 10, 2.4, CHIP_SHEAVE_Y[0] - 0.5, CHIP_SHEAVE_Y[1] + 0.5), CHIP_X, CHIP_Z, 40)
    outline_band(bmcb, hull_of_circles([(tx, tz, 5.9), (CHIP_X, CHIP_Z, 5.3)]), CHIP_SHEAVE_Y[0] + 0.3, CHIP_SHEAVE_Y[1] - 0.3, 0.5)
    obj("Reman_Tower", bmtw, coll, [M["green"]], bevel=0.003, segs=1)
    obj("Reman_TowerSteel", bmtr, coll, [M["steel"]], bevel=0.0)
    obj("Reman_ChipSheaves", bmcs, coll, [M["steel"]], bevel=0.0)
    obj("Reman_ChipBelt", bmcb, coll, [M["rubber"]], bevel=0.0)

    # Feed drive: 25 hp motor belted to the Rex gearbox; the gearbox output goes straight into the chain case.
    gx, gz = GEARBOX
    span(bmg, (gx - 9.0, 24.5, BASE_H), (gx + 9.0, 39.5, BASE_H + 2.0))
    span(bmm, (gx - 8.0, 25.5, BASE_H + 2.0), (gx + 8.0, 37.0, gz + 7.0))
    cyl(bmm, (gx, 37.5, gz), 2.6, 1.0, 'y', 0, 20)
    rod(bms, (gx, 37.0, gz), (gx, FEED_SHEAVE_Y[1] + 0.8, gz), 1.0, 0, 12)
    lathe_y(bms, sheave_profile(6.6, FEED_SHEAVE_Y[0], FEED_SHEAVE_Y[1], 2, 2.0, FEED_SHEAVE_Y[0] - 0.5, FEED_SHEAVE_Y[1] + 0.5), gx, gz, 32)
    rod(bms, (gx, OUT_HALF + 1.5, gz), (gx, 25.5, gz), 1.4, 0, 16)                           # output shaft
    cyl(bms, (gx, OUT_HALF + 2.9, gz), 2.2, 1.2, 'y', 0, 16)                                # coupling
    fx, fz = FEED_MOTOR
    slide_base(bmg, fx - 7.0, fx + 7.0, 44.0, 68.0, BASE_H, BASE_H + 2.0, fx + 8.0)
    rod(bmr, (fx + 8.0, 56.0, BASE_H + 3.25), (fx + 5.0, 56.0, BASE_H + 3.25), 0.4, 0, 10)
    motor(bmm, fx, fz, 44.5, 22.0, 7.0, BASE_H + 2.0, fins=16)
    rod(bms, (fx, FEED_SHEAVE_Y[0] - 0.8, fz), (fx, 44.5, fz), 0.85, 0, 12)
    lathe_y(bms, sheave_profile(4.6, FEED_SHEAVE_Y[0], FEED_SHEAVE_Y[1], 2, 1.6, FEED_SHEAVE_Y[0] - 0.5, FEED_SHEAVE_Y[1] + 0.5), fx, fz, 32)
    outline_band(bmb, hull_of_circles([(gx, gz, 6.3), (fx, fz, 4.3)]), FEED_SHEAVE_Y[0] + 0.3, FEED_SHEAVE_Y[1] - 0.3, 0.4)

    # Chain case on the drive-side plate enclosing the feed roll sprockets and the gearbox output sprocket.
    span(bmg, (2.0, OUT_HALF, 15.5), (102.0, OUT_HALF + 1.5, REMAN_Z0 - 1.0))
    obj("Motors", bmm, coll, [M["motor"]], bevel=0.004)
    obj("DriveSteel", bmg, coll, [M["green"]], bevel=0.003, segs=1)
    obj("Sheaves", bms, coll, [M["steel"]], bevel=0.0)
    obj("Belts", bmb, coll, [M["rubber"]], bevel=0.0)
    obj("TakeUpScrews", bmr, coll, [M["steel"]], bevel=0.0)
    for name in ("Motors", "Motor_Chipper", "DriveSteel", "Sheaves", "Belts", "TakeUpScrews",
                 "Reman_Tower", "Reman_TowerSteel", "Reman_ChipSheaves", "Reman_ChipBelt"):
        bpy.data.objects[name].location.z = 1.0 * IN


def build_details(coll, M):
    """Fabrication detail: bolt rows on the top plates, lifting lugs and the nameplate."""
    bm = bmesh.new()
    for x0, x1 in ((1.5, LID_X0 - 1.0), (LID_X1 + 1.0, LENGTH - 1.5)):
        n = int((x1 - x0) / 5.0)
        for k in range(n + 1):
            x = x0 + k * (x1 - x0) / n
            if REMAN_X0 - 1.5 < x < REMAN_X1 + 1.5:
                continue                                    # the reman section has its own top
            for s in (-1, 1):
                cyl(bm, (x, s * (OUT_HALF - 0.75), TOP_Z + 0.18), 0.45, 0.36, 'z', 0, 6)
    for x in (4.0, LENGTH - 4.0):
        for s in (-1, 1):
            span(bm, (x - 2.0, s * (OUT_HALF - 3.0) - 0.5, TOP_Z), (x + 2.0, s * (OUT_HALF - 3.0) + 0.5, TOP_Z + 3.0))
            L.add_torus(bm, 0.9 * IN, 0.35 * IN, mat_in(x, s * (OUT_HALF - 3.0), TOP_Z + 3.4, (90, 0, 0)), segs=16, minor=6)
    o = obj("Details", bm, coll, [M["green"]], bevel=0.0015, segs=1)
    bmp = bmesh.new()
    span(bmp, (1.5, -OUT_HALF - 0.12, 26.0), (14.0, -OUT_HALF, 33.0))
    plate = obj("Nameplate", bmp, coll, [M["brass"]], bevel=0.001, segs=1)
    for o2 in (o, plate):
        o2.location.z = 1.0 * IN
    for text, z, size in (("USNR", 30.0, 2.4), ("4TA36  S/N 3338", 27.0, 1.1)):
        cu = bpy.data.curves.new("NameplateText", 'FONT')
        cu.body = text
        cu.size = size * IN
        cu.extrude = 0.03 * IN
        cu.align_x = 'CENTER'
        t = bpy.data.objects.new("Nameplate_" + text.split()[0], cu)
        coll.objects.link(t)
        t.location = P(7.75, -OUT_HALF - 0.16, z + 1.0)
        t.rotation_euler = (math.radians(90), 0, 0)
        cu.materials.append(M["black"])


def build(materials):
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    build_frame(coll, materials)
    build_bearings(coll, materials)
    build_feed_rolls(coll, materials)
    build_press_rolls(coll, materials)
    build_anvils(coll, materials)
    build_chip_head(coll, materials)
    build_saw_arbor(coll, materials)
    build_saw_guides(coll, materials)
    build_operator_side(coll, materials)
    build_lid_and_door(coll, materials)
    build_drives(coll, materials)
    build_details(coll, materials)
    build_reman_section(coll, materials)
    reman = bpy.data.objects.new("RemanSection", None)
    coll.objects.link(reman)
    reman.empty_display_size = 0.3
    reman["set_axis"] = "Z: raise 1/2 in to 5 in to set the net cut; everything parented here moves with it"
    for o in list(coll.objects):
        if o.parent is None and (o.name.startswith("Reman_") or o.name.startswith("ChipHead_") or o.name.startswith("ChipGate")
                                 or o.name.startswith("PressRoll_AfterChipHead") or o.name == "Motor_Chipper"):
            o.parent = reman
    return {"objects": len(coll.all_objects)}
