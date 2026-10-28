"""Procedural double-track, track-through batch (charge) dry kiln (run inside Blender).

Kiln-local frame, Godot axes: +Z along the tracks (front/green door line at z = 0, green yard
at z < 0, rear/dry door line at Z_REAR, dry yard beyond), +X across, +Y up; boards lie along Z
like everywhere else in the mill, so the lumber material's grain runs the right way.

How it works (every step is a physical part):
- Stickered packages from the green stacker sit on kiln carts: 4 short carts coupled make a
  16 ft cart-set; each set carries 2 packages side by side, 2 high, with 4x4 bunks between the
  levels so a forklift can lift the top package off. 4 sets make a track's charge (16 packages);
  one chamber, two tracks: 32 packages a charge.
- The tracks run straight through. A forklift pushes the green string in from the front yard;
  when the charge is dry it is pulled out the rear door onto the dry yard rails.
- Each end has a door leaf per track. Closed, a door hangs on hangers on the kiln wall and rests
  against the seal frame. One overhead rail per end carries a fork dolly the operator pushes
  along: its forks slide into pockets on the door, lift it off the hangers and draw it out in
  front of the other (still closed) door, so the rail is only as wide as the kiln.
- Inside: a false ceiling over the charge; in the attic above it a fan wall down the middle
  under the ridge with reversible fans; sloped finned steam coil banks at the top of each side
  (attic down to the ceiling edge) and a vertical coil bank down the middle between the tracks.
  Air goes across the attic, through one top coil, down the side plenum, across both loads and
  the middle coil, up the far plenum through the other top coil and back to the fans. Hinged
  hatch vents on the roof, steam valves low on the walls with risers up to the coils.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "bin_sorter"))
sys.path.insert(0, os.path.join(HERE, "..", "green_stacker"))
import mesh_lib as L  # noqa: E402
import sorter_build as S  # noqa: E402
import stacker_build as SB  # noqa: E402
from materials_lib import Graph  # noqa: E402

G, gbox, gbox_span, gcyl, grod, gbeam, ibeam, obj = S.G, S.gbox, S.gbox_span, S.gcyl, S.grod, S.gbeam, S.ibeam, S.obj

COLL = "DryKilns"
INCH = 0.0254

# ---------------------------------------------------------------- lumber and carts
PKG_LEN = 4.877                                  # 16 ft
PKG_W = 52 * INCH                                # stacker package width
PKG_LAYERS = 31
BOARD_T, BOARD_W = SB.PREVIEW_T, SB.PREVIEW_W    # 2x8s, 7 a layer
PKG_H = PKG_LAYERS * (BOARD_T + SB.STICK_T)
BUNK = 3.5 * INCH                                # 4x4 bunks between package levels
PAIR_GAP = 0.10                                  # between the two packages side by side
LOAD_W = 2 * PKG_W + PAIR_GAP

CART_LEN = 1.22                                  # 4 ft carts, 4 coupled = one 16 ft set
CARTS_PER_SET = 4
SET_GAP = 0.10                                   # between cart-sets in a string
SET_LEN = CARTS_PER_SET * CART_LEN
SETS_PER_TRACK = 4
GAUGE = 1.80                                     # rail centres
WHEEL_R = 0.15
CART_TOP = 0.52                                  # bolster top: packages sit here
BOLSTER_HALF = LOAD_W / 2 + 0.08
LOAD_TOP = CART_TOP + 2 * PKG_H + BUNK

# ---------------------------------------------------------------- building
WALL_T = 0.20
SIDE_PLENUM = 0.90                               # air goes down/up each side wall
CENTER_GAP = 1.00                                # between the two loads: the middle coil bank
CH_IN = 2 * SIDE_PLENUM + 2 * LOAD_W + CENTER_GAP
X_IN0 = WALL_T
X_IN1 = WALL_T + CH_IN
BUILD_W = CH_IN + 2 * WALL_T
XM = BUILD_W / 2
TRACKS = (X_IN0 + SIDE_PLENUM + LOAD_W / 2, X_IN1 - SIDE_PLENUM - LOAD_W / 2)
STRING_LEN = SETS_PER_TRACK * SET_LEN + (SETS_PER_TRACK - 1) * SET_GAP
INSIDE_LEN = STRING_LEN + 0.9
Z_FRONT = 0.0                                    # front (green) wall outer face
Z_IN0 = WALL_T
Z_IN1 = Z_IN0 + INSIDE_LEN
Z_REAR = Z_IN1 + WALL_T                          # rear (dry) wall outer face
EAVE_Y = 5.80
ROOF_PITCH = math.radians(22)
RIDGE_Y = EAVE_Y + BUILD_W / 2 * math.tan(ROOF_PITCH)
ROOF_T = 0.14
CEIL_Y = 4.40                                    # false ceiling underside
CEIL_X0 = X_IN0 + SIDE_PLENUM + 0.90             # ceiling edge each side (mirrored)
COIL_TOP = (X_IN0 + 0.25, EAVE_Y - 0.45)         # top coil bank runs from here down to the ceiling edge
DOOR_H = 4.50
DOOR_CLEAR = LOAD_W / 2 + 0.25                   # opening half-width about a track
DOOR_LAP = 0.20                                  # door leaf overlaps the opening each side
YARD_LEN = STRING_LEN + 1.0                      # a whole charge fits outside at either end
FAN_R = 0.75
FAN_Y = 5.60
FAN_ZS = tuple(Z_IN0 + 1.4 + k * 2.6 for k in range(8))
# Doors and dolly, as distances out from an end wall's outer face.
SEAL_D = 0.04                                    # seal frame; closed door's back face
DOOR_T = 0.16
POCKET_D = 0.12                                  # fork pockets stand off the door face
LUG_DX = 1.50                                    # hanger lugs either side of the door centre
FORK_DX = 1.00                                   # fork pockets either side of the door centre
POCKET_Y = (4.38, 4.52)
RAIL_D = 0.55
RAIL_Y = 5.20                                    # underside of the door rail
CARRY_OUT = 0.42                                 # dolly draws a door out this far ...
CARRY_LIFT = 0.10                                # ... after lifting it this much off the hangers


def set_z0(k, start=Z_IN0 + 0.45):
    return start + k * (SET_LEN + SET_GAP)


def openings():
    return [(xc - DOOR_CLEAR, xc + DOOR_CLEAR) for xc in TRACKS]


def end_face(e):
    """Outer face z of end e (0 = front/green, 1 = rear/dry) and its outward sign."""
    return (Z_FRONT, -1.0) if e == 0 else (Z_REAR, 1.0)


def out_z(e, d):
    """z of a point d metres out from end e's wall face."""
    face, s = end_face(e)
    return face + s * d


def roof_under(x):
    """Underside of the roof at x."""
    return EAVE_Y + (RIDGE_Y - EAVE_Y) * (1 - abs(x - XM) / (BUILD_W / 2))


# ---------------------------------------------------------------- materials

def materials(M):
    """Add the kiln's own materials to the shared set: ribbed aluminium cladding, painted
    cart steel, rail steel and blue door frames / valve actuators."""
    g = Graph("Kiln_Aluminium")
    obj_c = g.coord.outputs['Object']
    # Ribs run up the walls and down the roof: band along object X on faces that look along
    # Y (end walls), along Y on faces that look along X (side walls, roof slopes).
    pos = g.node('ShaderNodeSeparateXYZ')
    g.link(obj_c, pos.inputs[0])
    nrm = g.node('ShaderNodeSeparateXYZ')
    g.link(g.geo.outputs['Normal'], nrm.inputs[0])
    side = g.math('GREATER_THAN', g.math('ABSOLUTE', nrm.outputs['X']), g.math('ABSOLUTE', nrm.outputs['Y']))
    along = g.mixf(side, pos.outputs['X'], pos.outputs['Y'])
    rib_v = g.node('ShaderNodeCombineXYZ')
    g.link(along, rib_v.inputs['X'])
    ribs = g.node('ShaderNodeTexWave', wave_type='BANDS', bands_direction='X')
    g.link(rib_v.outputs['Vector'], ribs.inputs['Vector'])
    ribs.inputs['Scale'].default_value = 3.0
    ribs.inputs['Distortion'].default_value = 0.0
    dents = g.noise(obj_c, 1.5, 4, 0.5).outputs['Fac']
    col = g.ramp(dents, [(0.3, (0.55, 0.56, 0.57)), (0.7, (0.72, 0.73, 0.74))])
    streak = g.maprange(g.noise(g.mapping(obj_c, scale=(6, 6, 0.4)), 1.0, 4, 0.5).outputs['Fac'], 0.55, 0.75)
    col = g.mix(g.math('MULTIPLY', streak, 0.35), col, (0.35, 0.34, 0.32))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Metallic'].default_value = 0.9
    g.link(g.mixf(dents, 0.28, 0.42), g.bsdf.inputs['Roughness'])
    g.link(g.bump(ribs.outputs['Fac'], 0.35, 0.02), g.bsdf.inputs['Normal'])
    M["alu"] = g.mat
    from sorter_materials import mill_paint
    M["cart"] = mill_paint("Kiln_CartBlack", (0.015, 0.015, 0.016), (0.03, 0.03, 0.032), (0.07, 0.07, 0.07), chip=0.8)
    M["blue"] = mill_paint("Kiln_DoorBlue", (0.01, 0.02, 0.12), (0.02, 0.04, 0.22), (0.05, 0.08, 0.3), chip=0.5)
    M["kiln_green"] = M["green"]
    return M


# ---------------------------------------------------------------- floor and rails

def build_rails(coll, M):
    """Flush rails cast into the slab, straight through the kiln from the green yard to the
    dry yard, with a flangeway groove beside each and end stops at both yard ends."""
    bm, bmg = bmesh.new(), bmesh.new()
    z0, z1 = -YARD_LEN, Z_REAR + YARD_LEN
    for xc in TRACKS:
        for side in (-1, 1):
            x = xc + side * GAUGE / 2
            gbox_span(bm, (x - 0.035, -0.10, z0), (x + 0.035, 0.004, z1))                      # rail head flush
            gx = x - side * 0.06                                                                   # flangeway inboard
            gbox_span(bmg, (gx - 0.025, -0.002, z0), (gx + 0.025, 0.001, z1))
        for z, d in ((z0, -1), (z1, 1)):                                                           # end stops
            gbox_span(bm, (xc - GAUGE / 2 - 0.15, 0.0, z + d * 0.05 - 0.15), (xc + GAUGE / 2 + 0.15, 0.30, z + d * 0.05 + 0.15))
    obj("KilnRails", bm, coll, [M["shaft"]], bevel=0.002, segs=1)
    obj("KilnFlangeways", bmg, coll, [M["rubber"]], bevel=0.0)


def build_cart(coll, M):
    """One 4 ft kiln cart, origin centred on the track at rail-top level: two side channels
    over the rails, four flanged wheels in pedestals, end crossbars, a central bolster the
    packages sit on, and a coupler bar at each end."""
    bm, bms = bmesh.new(), bmesh.new()
    h = CART_LEN / 2
    for side in (-1, 1):
        x = side * GAUGE / 2
        gbox_span(bm, (x - 0.06, 0.28, -h), (x + 0.06, 0.40, h))                           # side channel
        for z in (-0.38, 0.38):
            gbox_span(bm, (x - 0.07, 0.10, z - 0.11), (x - 0.055, 0.30, z + 0.11))          # pedestal cheeks
            gbox_span(bm, (x + 0.055, 0.10, z - 0.11), (x + 0.07, 0.30, z + 0.11))
            gcyl(bms, (x, WHEEL_R, z), WHEEL_R, 0.08, 'x', segs=24)                          # wheel
            gcyl(bms, (x - side * 0.035, WHEEL_R, z), WHEEL_R + 0.02, 0.015, 'x', segs=24)   # flange, inboard
            gcyl(bms, (x, WHEEL_R, z), 0.03, 0.16, 'x', segs=10)                             # stub axle
    for z in (-h + 0.04, h - 0.04):
        gbox_span(bm, (-GAUGE / 2, 0.30, z - 0.04), (GAUGE / 2, 0.38, z + 0.04))            # end crossbars
        gbox_span(bm, (-0.08, 0.26, z), (0.08, 0.34, z + math.copysign(0.07, z)))            # coupler bar / push block
    gbox_span(bm, (-BOLSTER_HALF, 0.40, -0.06), (BOLSTER_HALF, CART_TOP, 0.06))                # bolster
    for side in (-1, 1):
        gbeam(bm, (side * GAUGE / 2, 0.40, 0.0), (side * (BOLSTER_HALF - 0.05), CART_TOP - 0.02, 0.0), 0.08, 0.02)
    cart = obj("KilnCart", bm, coll, [M["cart"]], bevel=0.004)
    wheels = obj("KilnCartWheels", bms, coll, [M["shaft"]], bevel=0.002, segs=1)
    wheels.parent = cart
    return cart


# ---------------------------------------------------------------- building

def build_building(coll, M):
    """One chamber: end walls with a door opening per track at both ends, side walls, gables,
    a single gable roof, seal frames, door hangers, lights, control panel and man doors."""
    bm, bmf = bmesh.new(), bmesh.new()
    ops = openings()
    for e in (0, 1):
        face, s = end_face(e)
        za, zb = face, face - s * WALL_T                       # wall thickness runs inward
        piers = [0.0] + [x for o in ops for x in o] + [BUILD_W]
        for a, b in zip(piers[0::2], piers[1::2]):
            gbox_span(bm, (a, 0.0, za), (b, EAVE_Y, zb))
        for x0, x1 in ops:
            gbox_span(bm, (x0, DOOR_H, za), (x1, EAVE_Y, zb))                                  # lintel
            for xa, xb in ((x0 - 0.12, x0), (x1, x1 + 0.12)):                                   # seal frame
                gbox_span(bmf, (xa, 0.0, out_z(e, SEAL_D)), (xb, DOOR_H + 0.12, face))
            gbox_span(bmf, (x0 - 0.12, DOOR_H, out_z(e, SEAL_D)), (x1 + 0.12, DOOR_H + 0.12, face))
            # Door hangers: a bracket on the wall under each door lug, with an upturned lip.
            xc = (x0 + x1) / 2
            for dx in (-LUG_DX, LUG_DX):
                x = xc + dx
                gbox_span(bmf, (x - 0.08, DOOR_H + 0.14, face), (x + 0.08, DOOR_H + 0.48, out_z(e, 0.02)))      # wall plate
                gbox_span(bmf, (x - 0.06, DOOR_H + 0.32, face), (x + 0.06, DOOR_H + 0.40, out_z(e, 0.12)))      # arm
                gbox_span(bmf, (x - 0.06, DOOR_H + 0.40, out_z(e, 0.10)), (x + 0.06, DOOR_H + 0.44, out_z(e, 0.12)))  # lip
        L.add_prism(bm, [(0.0, EAVE_Y), (BUILD_W, EAVE_Y), (XM, RIDGE_Y)], -max(za, zb), -min(za, zb))   # gable
    gbox_span(bm, (0.0, 0.0, Z_IN0), (WALL_T, EAVE_Y, Z_IN1))                                   # side walls
    gbox_span(bm, (BUILD_W - WALL_T, 0.0, Z_IN0), (BUILD_W, EAVE_Y, Z_IN1))
    for xe in (0.0, BUILD_W):                                                                    # roof slabs
        d = Vector((XM - xe, RIDGE_Y - EAVE_Y)).normalized()
        p0 = Vector((xe, EAVE_Y)) - d * 0.35
        L.add_prism(bm, [(p0.x, p0.y), (XM, RIDGE_Y), (XM, RIDGE_Y + ROOF_T), (p0.x, p0.y + ROOF_T)],
                    -(Z_REAR + 0.3), -(Z_FRONT - 0.3))
    gbox_span(bmf, (XM - 0.15, RIDGE_Y + ROOF_T - 0.04, Z_FRONT - 0.3), (XM + 0.15, RIDGE_Y + ROOF_T + 0.06, Z_REAR + 0.3))   # ridge cap
    for x in (-0.55, BUILD_W + 0.35):                                                            # eave gutters
        gbox_span(bmf, (x, EAVE_Y - 0.30, Z_FRONT - 0.3), (x + 0.2, EAVE_Y - 0.12, Z_REAR + 0.3))
    # Fittings: a flood light on each gable above the door rail, the kiln control panel and a
    # man door on the +X (boiler) side wall, a man door on the -X wall.
    bmd = bmesh.new()
    for e in (0, 1):
        gbox(bmd, (XM, RIDGE_Y - 0.9, out_z(e, 0.15)), (0.45, 0.3, 0.3))
    gbox(bmd, (BUILD_W + 0.12, 1.3, Z_IN0 + 1.6), (0.2, 1.0, 0.7))
    for x, s in ((0.0, -1), (BUILD_W, 1)):
        gbox_span(bmd, (x + s * 0.06, 0.0, Z_IN0 + 3.0), (x, 2.1, Z_IN0 + 3.95))
    obj("KilnBuilding", bm, coll, [M["alu"]], bevel=0.01, segs=1)
    obj("KilnTrim", bmf, coll, [M["grey"]], bevel=0.004, segs=1)
    obj("KilnFittings", bmd, coll, [M["grey"]], bevel=0.01, segs=1)


# ---------------------------------------------------------------- interior

def hole_plate(bm, x, zc, yc, half, r, t=0.04, segs=32):
    """Square plate (in the YZ plane at x) with a round hole: quads between the hole edge
    and the square edge, front and back, and the hole's bore."""
    rings = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        ca, sa = math.cos(a), math.sin(a)
        s = half / max(abs(ca), abs(sa))
        rings.append(((zc + r * ca, yc + r * sa), (zc + s * ca, yc + s * sa)))
    for xf in (x - t / 2, x + t / 2):
        vin = [bm.verts.new(G(xf, p[1], p[0])) for p, _ in rings]
        vout = [bm.verts.new(G(xf, q[1], q[0])) for _, q in rings]
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((vin[k], vout[k], vout[j], vin[j]))
        if xf == x - t / 2:
            front_in = vin
        else:
            for k in range(segs):
                j = (k + 1) % segs
                bm.faces.new((front_in[k], front_in[j], vin[j], vin[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def mirror_x(x):
    return BUILD_W - x


def build_interior(coll, M):
    """False ceiling, hinged top baffles, fan wall under the ridge with shrouded openings and a
    motor per fan, sloped top coil banks each side, the vertical middle coil bank with its
    columns, spray line, steam valves low on the walls with risers up to the coils."""
    bm, bmc, bmv, bmb = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    za, zb = Z_IN0 + 0.05, Z_IN1 - 0.05
    gbox_span(bm, (CEIL_X0, CEIL_Y, za), (mirror_x(CEIL_X0), CEIL_Y + 0.06, zb))           # false ceiling
    load_edge = X_IN0 + SIDE_PLENUM + 0.05
    for side in (0, 1):
        fx = (lambda x: x) if side == 0 else mirror_x
        # Hinged top baffle from the ceiling edge down onto the load's outer top edge, so air
        # can't short-cut over the charge.
        gbeam(bm, (fx(CEIL_X0), CEIL_Y, (za + zb) / 2), (fx(load_edge), LOAD_TOP + 0.06, (za + zb) / 2), zb - za - 0.6, 0.012)
        grod(bmv, (fx(CEIL_X0), CEIL_Y - 0.02, za + 0.3), (fx(CEIL_X0), CEIL_Y - 0.02, zb - 0.3), 0.025, segs=10)   # hinge
        # Top coil bank: finned steam pipes along the kiln on a slope from under the eave down
        # to the ceiling edge, two rows deep, with a header box at each end and hangers.
        p_top, p_bot = Vector(COIL_TOP), Vector((CEIL_X0, CEIL_Y + 0.08))
        u = (p_bot - p_top).normalized()
        n = Vector((-u.y, u.x)) if u.x > 0 else Vector((u.y, -u.x))
        span = (p_bot - p_top).length
        npipe = 10
        for i in range(npipe):
            for row in (-0.5, 0.5):
                p = p_top + u * (0.08 + i * (span - 0.16) / (npipe - 1)) + n * row * 0.11
                grod(bmc, (fx(p.x), p.y, Z_IN0 + 0.75), (fx(p.x), p.y, Z_IN1 - 0.75), 0.042, segs=10)
        for z in (Z_IN0 + 0.65, Z_IN1 - 0.65):                                             # headers
            gbeam(bmc, (fx(p_top.x), p_top.y, z), (fx(p_bot.x), p_bot.y, z), 0.18, 0.30)
        for z in [Z_IN0 + 3.0 + 3.5 * k for k in range(5)]:                                  # support bars
            gbeam(bmv, (fx(p_top.x), p_top.y - 0.17, z), (fx(p_bot.x), p_bot.y - 0.17, z), 0.06, 0.03)
            grod(bmv, (fx(p_bot.x - 0.05), p_bot.y, z), (fx(p_bot.x - 0.05), roof_under(fx(p_bot.x - 0.05)), z), 0.012, segs=6)
            grod(bmv, (fx(p_top.x + 0.05), p_top.y, z), (fx(p_top.x + 0.05), roof_under(fx(p_top.x + 0.05)), z), 0.012, segs=6)
        gbox_span(bm, (fx(X_IN0), p_top.y + 0.18, za), (fx(p_top.x), p_top.y + 0.22, zb))   # closer: coil top to wall
        # Steam: a valve station low on the wall at the front end with a riser up the side
        # plenum to the top of the bank; condensate down at the rear end to a trap.
        xr = fx(X_IN0 + 0.14)
        for z, top_y, r in ((Z_IN0 + 0.65, p_top.y + 0.1, 0.045), (Z_IN1 - 0.65, p_top.y - 0.12, 0.03)):
            grod(bmc, (xr, 0.25, z), (xr, top_y, z), r, segs=10)
            grod(bmc, (xr, top_y, z), (fx(p_top.x), top_y, z), r, segs=10)
            grod(bmc, (fx(X_IN0), 0.35, z), (xr, 0.35, z), r, segs=10)                    # through the wall
        gcyl(bmc, (xr, 1.05, Z_IN0 + 0.65), 0.08, 0.22, 'y', segs=14)                       # valve body
        gcyl(bmb, (xr, 1.42, Z_IN0 + 0.65), 0.11, 0.30, 'y', segs=16)                       # actuator
        gbox(bmb, (xr, 0.45, Z_IN1 - 0.65), (0.14, 0.14, 0.2))                               # trap
    # Middle coil bank: two columns of finned pipes stacked up between the loads, carried by
    # columns that also hold the ceiling; headers at each end, fed from a valve at the front.
    for i in range(11):
        y = 0.75 + i * (CEIL_Y - 1.0) / 10
        for dx in (-0.11, 0.11):
            grod(bmc, (XM + dx, y, Z_IN0 + 0.75), (XM + dx, y, Z_IN1 - 0.75), 0.042, segs=10)
    for z in (Z_IN0 + 0.65, Z_IN1 - 0.65):
        gbox_span(bmc, (XM - 0.2, 0.6, z - 0.09), (XM + 0.2, CEIL_Y - 0.1, z + 0.09))
    for z in [Z_IN0 + 2.0 + 4.1 * k for k in range(5)]:
        ibeam(bmv, 'y', (XM, CEIL_Y / 2, z), CEIL_Y, h=0.2, w=0.2)
    grod(bmc, (XM - 0.3, 0.0, Z_IN0 + 0.3), (XM - 0.3, 0.7, Z_IN0 + 0.3), 0.045, segs=10)   # up from the floor trench
    grod(bmc, (XM - 0.3, 0.7, Z_IN0 + 0.3), (XM - 0.3, 0.7, Z_IN0 + 0.6), 0.045, segs=10)
    gcyl(bmc, (XM - 0.3, 0.35, Z_IN0 + 0.3), 0.08, 0.22, 'y', segs=14)
    gcyl(bmb, (XM - 0.3, 0.35, Z_IN0 + 0.12), 0.1, 0.26, 'z', segs=16)
    gbox(bmb, (XM, 0.3, Z_IN1 - 0.4), (0.14, 0.14, 0.18))                                    # trap
    gbox_span(bmv, (XM - 0.45, -0.01, Z_IN0 + 0.05), (XM + 0.45, 0.01, Z_IN0 + 0.55))      # trench cover
    # Fan wall under the ridge: panels between the fans, a plate with a round hole and shroud
    # ring round each fan, so air can only pass through the fans.
    top = RIDGE_Y
    half = FAN_R + 0.05
    zs = [Z_IN0] + [e for z in FAN_ZS for e in (z - half, z + half)] + [Z_IN1]
    for za_, zb_ in zip(zs[0::2], zs[1::2]):
        gbox_span(bm, (XM - 0.02, CEIL_Y + 0.06, za_), (XM + 0.02, top, zb_))
    for z in FAN_ZS:
        gbox_span(bm, (XM - 0.02, CEIL_Y + 0.06, z - half), (XM + 0.02, FAN_Y - half, z + half))
        gbox_span(bm, (XM - 0.02, FAN_Y + half, z - half), (XM + 0.02, top, z + half))
        hole_plate(bm, XM, z, FAN_Y, half, FAN_R + 0.04)
        ring = []
        for k in range(33):
            a = 2 * math.pi * k / 32
            ring.append((z + (FAN_R + 0.04) * math.cos(a), FAN_Y + (FAN_R + 0.04) * math.sin(a)))
        for k in range(32):
            (z0, y0), (z1, y1) = ring[k], ring[k + 1]
            gbeam(bm, (XM, y0, z0), (XM, y1, z1), 0.25, 0.012)
        # Direct-drive motor on a cradle off the fan wall (axis across the kiln); the fan hub
        # sits on its shaft on the other side of the wall.
        gcyl(bmv, (XM + 0.32, FAN_Y, z), 0.19, 0.42, 'x', segs=20)
        gcyl(bmv, (XM + 0.1, FAN_Y, z), 0.035, 0.24, 'x', segs=10)
        for dz in (-0.16, 0.16):
            gbox_span(bmv, (XM + 0.02, FAN_Y - 0.24, z + dz - 0.02), (XM + 0.5, FAN_Y - 0.18, z + dz + 0.02))
            gbeam(bmv, (XM + 0.02, FAN_Y - 0.6, z + dz), (XM + 0.45, FAN_Y - 0.22, z + dz), 0.04, 0.04)
    for z in (Z_IN0 + 3.0, Z_IN0 + 8.0, Z_IN0 + 13.0, Z_IN0 + 18.0):                          # ceiling hangers
        for x in (XM - 1.4, XM + 1.4):
            grod(bmv, (x, CEIL_Y + 0.06, z), (x, roof_under(x), z), 0.015, segs=6)
    grod(bmc, (XM - 0.5, top - 0.6, Z_IN0 + 0.5), (XM - 0.5, top - 0.6, Z_IN1 - 0.5), 0.025, segs=8)   # spray line
    for z in FAN_ZS:
        gcyl(bmc, (XM - 0.5, top - 0.67, z), 0.02, 0.08, 'y', segs=8)
    # Steam mains outside both side walls, low, feeding the valve stations; the -X main is fed
    # by a crossover under the green apron (in a trench) from the boiler side.
    for xo in (-0.25, BUILD_W + 0.25):
        grod(bmc, (xo, 0.35, Z_IN0 + 0.3), (xo, 0.35, Z_IN1 - 0.3), 0.06, segs=12)
        grod(bmc, (xo, 0.35, Z_IN0 + 0.65), (X_IN0 if xo < 0 else X_IN1, 0.35, Z_IN0 + 0.65), 0.045, segs=10)
        for z in [Z_IN0 + 1.0 + 3.0 * k for k in range(7)]:
            gbox_span(bmv, (xo - 0.04, 0.0, z - 0.04), (xo + 0.04, 0.29, z + 0.04))
    grod(bmc, (BUILD_W + 0.25, 0.35, Z_IN0 + 10.0), (BUILD_W + 4.5, 0.35, Z_IN0 + 10.0), 0.075, segs=12)   # from the boiler house
    obj("KilnFanDeck", bm, coll, [M["alu"]], bevel=0.003, segs=1)
    obj("KilnCoils", bmc, coll, [M["shaft"]], bevel=0.0)
    obj("KilnMachinery", bmv, coll, [M["grey"]], bevel=0.004, segs=1)
    obj("KilnActuators", bmb, coll, [M["blue"]], bevel=0.004, segs=1)


def build_roof_vents(coll, M, open_side=-1):
    """Hinged hatch vents along both roof slopes into the attic, each on a curb with a push-rod
    actuator; the open_side slope's hatches are shown open on their prop rods. Fresh-air inlet
    hoods near each eave, and conduit along the eaves feeding the actuators."""
    bm, bmd, bmr = bmesh.new(), bmesh.new(), bmesh.new()
    a = ROOF_PITCH
    for s in (-1, 1):
        ridge = Vector((XM, RIDGE_Y + ROOF_T))
        u = Vector((s * math.cos(a), -math.sin(a)))
        n = Vector((s * math.sin(a), math.cos(a)))

        def P(t, h):
            return ridge + u * t + n * h

        t0, t1 = 1.1, 2.0
        for k in range(7):
            zc = (FAN_ZS[k] + FAN_ZS[k + 1]) / 2
            w = 0.9
            for t in (t0, t1):                                                       # curb sides along z
                p, q = P(t, 0.0), P(t, 0.15)
                gbeam(bm, (p.x, p.y, zc), (q.x, q.y, zc), w + 0.08, 0.04)
            for dz in (-w / 2, w / 2):                                               # curb ends
                p, q = P(t0, 0.075), P(t1, 0.075)
                gbeam(bm, (p.x, p.y, zc + dz), (q.x, q.y, zc + dz), 0.04, 0.15)
            p, q = P(t0, 0.01), P(t1, 0.01)
            if s == open_side:
                gbeam(bmd, (p.x, p.y, zc), (q.x, q.y, zc), w - 0.02, 0.02)          # dark opening
                hinge = P(t0, 0.15)
                ang = math.radians(72)
                d = u * math.cos(ang) + n * math.sin(ang)
                tip = hinge + d * (t1 - t0 + 0.06)
                gbeam(bm, (hinge.x, hinge.y, zc), (tip.x, tip.y, zc), w + 0.1, 0.04)   # lid
                gbeam(bm, (hinge.x, hinge.y, zc), (tip.x, tip.y, zc), 0.08, 0.10)   # lid stiffener
                prop_a, prop_b = P(t1 + 0.05, 0.15), hinge + d * 0.7
                grod(bmr, (prop_a.x, prop_a.y, zc + w / 2 - 0.08), (prop_b.x, prop_b.y, zc + w / 2 - 0.08), 0.015, segs=6)
            else:
                p, q = P(t0 - 0.03, 0.17), P(t1 + 0.03, 0.17)
                gbeam(bm, (p.x, p.y, zc), (q.x, q.y, zc), w + 0.1, 0.04)             # closed lid
            act_a, act_b = P(t1 + 0.35, 0.06), P(t1 + 0.05, 0.25)                   # push-rod actuator
            grod(bmr, (act_a.x, act_a.y, zc - w / 2 + 0.1), (act_b.x, act_b.y, zc - w / 2 + 0.1), 0.03, segs=8)
        # Fresh-air inlet hoods near the eave and the conduit run feeding the actuators.
        t_eave = (BUILD_W / 2) / math.cos(a) - 0.2
        for k in (1, 3, 5):
            zc = FAN_ZS[k] + 1.3
            c = P(t_eave - 0.6, 0.12)
            gbeam(bm, (c.x - u.x * 0.25, c.y - u.y * 0.25, zc), (c.x + u.x * 0.25, c.y + u.y * 0.25, zc), 0.55, 0.22)
        c0 = P(t_eave - 0.15, 0.04)
        grod(bmr, (c0.x, c0.y, Z_FRONT - 0.1), (c0.x, c0.y, Z_REAR + 0.1), 0.02, segs=6)
    obj("KilnRoofVents", bm, coll, [M["alu"]], bevel=0.004, segs=1)
    obj("KilnVentOpenings", bmd, coll, [M["rubber"]], bevel=0.0)
    obj("KilnVentRods", bmr, coll, [M["shaft"]], bevel=0.0)


def build_fan(coll, M):
    """Reversible propeller fan, built about Z; placed rotated so it spins about X (across the
    kiln, on its motor shaft through the fan wall)."""
    bm = bmesh.new()
    gcyl(bm, (0, 0, 0), 0.14, 0.2, 'z', segs=20)
    for k in range(6):
        a = 2 * math.pi * k / 6
        d = Vector((math.cos(a), math.sin(a)))
        p0, p1 = d * 0.12, d * (FAN_R - 0.02)
        m, length = L.frame_between(G(p0.x, p0.y, 0), G(p1.x, p1.y, 0))
        L.add_box(bm, (length, 0.24, 0.012), m @ L.mat(rot=(25, 0, 0)))
    return obj("KilnFan", bm, coll, [M["galv"]], bevel=0.003, segs=1)


# ---------------------------------------------------------------- doors

def build_door_rail(coll, M, e):
    """End e's single overhead door rail, the width of the kiln, on cantilever arms off the end
    wall with knee braces above the rail so the dolly trolleys pass underneath."""
    bm = bmesh.new()
    x0, x1 = 0.1, BUILD_W - 0.1
    zr = out_z(e, RAIL_D)
    ibeam(bm, 'x', ((x0 + x1) / 2, RAIL_Y + 0.1, zr), x1 - x0, h=0.2, w=0.15)
    for x in (x0, x1):                                                                       # end stops
        gbox_span(bm, (x - 0.05, RAIL_Y, zr - 0.08), (x + 0.05, RAIL_Y + 0.2, zr + 0.08))
    face, _ = end_face(e)
    for x in [x0 + 0.2 + k * 2.04 for k in range(int((x1 - x0 - 0.4) / 2.04) + 1)] + [x1 - 0.2]:
        gbox_span(bm, (x - 0.05, RAIL_Y + 0.2, face), (x + 0.05, RAIL_Y + 0.32, out_z(e, RAIL_D + 0.1)))   # arm
        gbeam(bm, (x, RAIL_Y + 0.62, face), (x, RAIL_Y + 0.32, out_z(e, RAIL_D + 0.05)), 0.06, 0.06)       # brace
    return obj("KilnDoorRail_%s" % "FR"[e], bm, coll, [M["grey"]], bevel=0.004)


def build_door(coll, M, e, t):
    """Door leaf for track t at end e, closed on its hangers: insulated aluminium panel lapping
    the opening, blue stiffening frame, a hanger lug with a hook either side at the top and a
    fork pocket either side on the outer face."""
    bm, bmb = bmesh.new(), bmesh.new()
    o0, o1 = openings()[t]
    x0, x1 = o0 - DOOR_LAP, o1 + DOOR_LAP
    xc = (x0 + x1) / 2
    db, df = SEAL_D, SEAL_D + DOOR_T
    gbox_span(bm, (x0, 0.02, out_z(e, db)), (x1, DOOR_H + 0.25, out_z(e, df)))
    for x in (x0 + 0.45, xc, x1 - 0.45):                                                     # blue frame
        gbox_span(bmb, (x - 0.05, 0.3, out_z(e, df)), (x + 0.05, DOOR_H + 0.12, out_z(e, df + 0.08)))
    for y in (0.35, 1.9, 3.3, DOOR_H + 0.07):
        gbox_span(bmb, (x0 + 0.4, y - 0.05, out_z(e, df)), (x1 - 0.4, y + 0.05, out_z(e, df + 0.08)))
    for dx in (-LUG_DX, LUG_DX):                                                             # hanger lugs and hooks
        x = xc + dx
        gbox_span(bmb, (x - 0.05, DOOR_H + 0.2, out_z(e, 0.13)), (x + 0.05, DOOR_H + 0.50, out_z(e, 0.18)))
        gbox_span(bmb, (x - 0.05, DOOR_H + 0.44, out_z(e, 0.03)), (x + 0.05, DOOR_H + 0.50, out_z(e, 0.18)))
        gbox_span(bmb, (x - 0.05, DOOR_H + 0.40, out_z(e, 0.03)), (x + 0.05, DOOR_H + 0.44, out_z(e, 0.06)))
    for dx in (-FORK_DX, FORK_DX):                                                           # fork pockets
        x = xc + dx
        gbox_span(bmb, (x - 0.09, POCKET_Y[0], out_z(e, df)), (x + 0.09, POCKET_Y[1], out_z(e, df + POCKET_D)))
        gbox_span(bm, (x - 0.06, POCKET_Y[0] + 0.03, out_z(e, df + POCKET_D - 0.005)), (x + 0.06, POCKET_Y[1] - 0.03, out_z(e, df + POCKET_D + 0.001)))
    door = obj("KilnDoor_%s%d" % ("FR"[e], t), bm, coll, [M["alu"]], bevel=0.01, segs=1)
    frame = obj("KilnDoorFrame_%s%d" % ("FR"[e], t), bmb, coll, [M["blue"]], bevel=0.004)
    frame.parent = door
    return door


def door_carry_offset(e, t, over):
    """Offset (Godot x, y, z) that moves end e's door t from closed on its hangers to carried by
    the dolly: lifted, drawn out to clear the other door, and moved across to 'over' (a track)."""
    _, s = end_face(e)
    return (TRACKS[over] - TRACKS[t], CARRY_LIFT, s * CARRY_OUT)


def build_dolly(coll, M, e, carrying=True):
    """End e's door fork dolly, built about x = 0 (its location's x moves it along the rail):
    two trolleys on the rail's bottom flange, a spreader, reach guides out toward the wall, a
    fork carriage hanging from them with two forks pointing at the wall, a lift cylinder each
    side and the operator's pendant. carrying: forks drawn out (door clear of the other door),
    else run in to the wall to pick a closed door."""
    bm, bmb, bms = bmesh.new(), bmesh.new(), bmesh.new()
    zr = out_z(e, RAIL_D)
    for x in (-1.1, 1.1):                                                                     # trolleys
        for dz in (-0.12, 0.12):
            gbox_span(bm, (x - 0.22, RAIL_Y - 0.03, zr + dz - 0.015), (x + 0.22, RAIL_Y + 0.24, zr + dz + 0.015))
            for dx in (-0.12, 0.12):
                gcyl(bms, (x + dx, RAIL_Y + 0.05, zr + dz * 0.55), 0.045, 0.04, 'z', segs=12)
        gbox_span(bm, (x - 0.22, RAIL_Y - 0.10, zr - 0.14), (x + 0.22, RAIL_Y - 0.03, zr + 0.14))
    gbox_span(bm, (-1.3, RAIL_Y - 0.20, zr - 0.06), (1.3, RAIL_Y - 0.10, zr + 0.06))         # spreader
    d_in, d_out = 0.28, 0.92
    gx = 0.62
    for x in (-gx, gx):                                                                       # reach guides
        gbox_span(bm, (x - 0.05, RAIL_Y - 0.30, out_z(e, d_in)), (x + 0.05, RAIL_Y - 0.20, out_z(e, d_out)))
    door_face = SEAL_D + DOOR_T + POCKET_D + (CARRY_OUT if carrying else 0.0)
    cd = door_face + 0.06                                                                      # carriage beam centre
    lift = CARRY_LIFT if carrying else 0.0
    for x in (-gx, gx):                                                                       # hangers + lift cylinders
        gbox_span(bm, (x - 0.08, RAIL_Y - 0.36, out_z(e, cd - 0.08)), (x + 0.08, RAIL_Y - 0.30, out_z(e, cd + 0.08)))
        gbox_span(bm, (x - 0.04, POCKET_Y[0] + lift - 0.08, out_z(e, cd + 0.02)), (x + 0.04, RAIL_Y - 0.36, out_z(e, cd + 0.08)))
        gcyl(bmb, (x, RAIL_Y - 0.62, out_z(e, cd - 0.03)), 0.045, 0.45, 'y', segs=12)
    beam_y = POCKET_Y[0] + lift + 0.06
    gbox_span(bm, (-1.2, beam_y - 0.12, out_z(e, cd - 0.05)), (1.2, beam_y + 0.12, out_z(e, cd + 0.05)))   # carriage beam
    for dx in (-FORK_DX, FORK_DX):                                                            # forks into the pockets
        gbox_span(bm, (dx - 0.05, beam_y - 0.04, out_z(e, cd - 0.05)), (dx + 0.05, beam_y + 0.0, out_z(e, door_face - POCKET_D + 0.02)))
    # Operator pendant on its cable and a push handle.
    grod(bms, (1.15, RAIL_Y - 0.2, out_z(e, d_out - 0.05)), (1.15, 1.45, out_z(e, d_out - 0.05)), 0.006, segs=6)
    gbox(bmb, (1.15, 1.3, out_z(e, d_out - 0.05)), (0.1, 0.25, 0.08))
    grod(bms, (-1.2, beam_y, out_z(e, cd + 0.05)), (-1.2, 1.2, out_z(e, cd + 0.35)), 0.02, segs=8)
    grod(bms, (-1.45, 1.2, out_z(e, cd + 0.35)), (-0.95, 1.2, out_z(e, cd + 0.35)), 0.02, segs=8)
    dolly = obj("KilnDoorDolly_%s" % "FR"[e], bm, coll, [M["yellow"] if "yellow" in M else M["grey"]], bevel=0.004)
    for name, b, mat in (("Cyl", bmb, M["blue"]), ("Steel", bms, M["shaft"])):
        o = obj("KilnDoorDolly%s_%s" % (name, "FR"[e]), b, coll, [mat], bevel=0.002, segs=1)
        o.parent = dolly
    return dolly


# ---------------------------------------------------------------- lumber

def kiln_package(bm, x0, y0, z0):
    """A stacker package lying along the track: 7 2x8s a layer across X, sticks across every
    layer, boards along Z from z0."""
    n = SB.PREVIEW_PER_LAYER
    for j in range(PKG_LAYERS):
        y = y0 + j * (BOARD_T + SB.STICK_T)
        for k in range(n):
            jit = math.sin((x0 * 7 + z0 * 3 + j * 13 + k) * 12.9898) * 43758.5453
            jit -= math.floor(jit)
            SB.board(bm, x0 + k * (BOARD_W + 0.003) + 0.002 * jit, y, BOARD_T, BOARD_W, z0=z0 + 0.006 * jit)
        for s in range(9):
            SB.stick(bm, x0 - 0.02, y + BOARD_T, z0 + 0.04 + s * (PKG_LEN - 0.08) / 8)


def load_cart_set(bm, xc, z0, levels=2):
    """Two packages side by side, 'levels' high, with 4x4 bunks over each bolster between levels."""
    y = CART_TOP
    for lvl in range(levels):
        for side in (-1, 1):
            kiln_package(bm, xc + side * (PAIR_GAP / 2 + PKG_W / 2) - PKG_W / 2, y, z0)
        y += PKG_H
        if lvl < levels - 1:
            for k in range(CARTS_PER_SET):
                zc = z0 + (k + 0.5) * CART_LEN
                SB.tag_board(bm, gbox_span(bm, (xc - LOAD_W / 2, y, zc - BUNK / 2), (xc + LOAD_W / 2, y + BUNK, zc + BUNK / 2), 1))
            y += BUNK


# ---------------------------------------------------------------- preview

def place_string(coll, cart, prefix, xc, z_start, loaded_sets):
    """A track's cart string: SETS_PER_TRACK sets of coupled carts from z_start, the first
    loaded_sets of them loaded."""
    w = bpy.data.objects["KilnCartWheels"]
    for k in range(SETS_PER_TRACK):
        z0 = set_z0(k, z_start)
        for i in range(CARTS_PER_SET):
            L.link_copy(cart, "%s_%d_%d" % (prefix, k, i), coll, G(xc, 0.0, z0 + (i + 0.5) * CART_LEN))
            L.link_copy(w, "%sW_%d_%d" % (prefix, k, i), coll, G(xc, 0.0, z0 + (i + 0.5) * CART_LEN))
    return [set_z0(k, z_start) for k in range(loaded_sets)]


def build_preview(coll, M, cart):
    """Track 1 charged and shut. Track 0 between charges: its dried string has been pulled out
    the rear door onto the dry yard and that door re-hung; the front door is on the dolly,
    parked in front of track 1's front door, and the green string waits at the front ready to
    be pushed in. The rear dolly is parked empty at the -X end, forks drawn out."""
    lumber = SB.lumber_bmesh()
    t0, t1 = TRACKS
    for z0 in place_string(coll, cart, "CartIn1", t1, Z_IN0 + 0.45, 4):
        load_cart_set(lumber, t1, z0)
    for z0 in place_string(coll, cart, "CartGreen0", t0, -STRING_LEN - 1.2, 4):
        load_cart_set(lumber, t0, z0)
    for z0 in place_string(coll, cart, "CartDry0", t0, Z_REAR + 0.9, 4):
        load_cart_set(lumber, t0, z0)
    o = L.make_object("KilnPreviewLumber", lumber, coll, [M["lumber"], M["sticks"]], bevel=0.002, bevel_segments=1, weighted=False)
    o.data.polygons.foreach_set("use_smooth", [False] * len(o.data.polygons))
    bpy.data.objects["KilnDoor_F0"].location = G(*door_carry_offset(0, 0, 1))
    bpy.data.objects["KilnDoorDolly_F"].location = G(TRACKS[1], 0, 0)
    bpy.data.objects["KilnDoorDolly_R"].location = G(1.4, 0, 0)
    fan = bpy.data.objects["KilnFan"]
    for i, z in enumerate(FAN_ZS):
        L.link_copy(fan, "KilnFan_%d" % i, coll, G(XM - 0.08, FAN_Y, z), (0, 0, 90))


def build(M, preview=True):
    materials(M)
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    parts = L.collection("KilnParts", coll)
    build_rails(coll, M)
    build_building(coll, M)
    build_interior(coll, M)
    build_roof_vents(coll, M)
    for e in (0, 1):
        build_door_rail(coll, M, e)
        for t in (0, 1):
            build_door(coll, M, e, t)
        build_dolly(coll, M, e, carrying=True)
    cart = build_cart(parts, M)
    fan = build_fan(parts, M)
    if preview:
        build_preview(coll, M, cart)
    for src in (cart, bpy.data.objects["KilnCartWheels"], fan):
        src.hide_render = True
    cart.location = G(-6, 0, -30)
    fan.location = G(-6, 0, -32)
    return {"objects": len(coll.all_objects), "build_w": round(BUILD_W, 3), "inside_len": round(INSIDE_LEN, 3),
            "ridge": round(RIDGE_Y, 3), "tracks": [round(x, 3) for x in TRACKS], "load_top": round(LOAD_TOP, 3),
            "z_rear": round(Z_REAR, 3), "openings": [tuple(round(v, 3) for v in o) for o in openings()]}
