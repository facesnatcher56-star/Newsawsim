"""USNR job 3338 board line: unscrambler -> take-away -> lug loader -> scanner chains -> positioners ->
lineal infeed -> 4TA36 edger -> picker belt outfeed.

Laid out from setting plan D-108393.1 and elevation D-108393.2 plus what the user confirmed (see the
project memory notes). Units are inches. Axes match the edger: +X is the edger feed direction, +Y the
edger's drive side, Z up from the raised mill floor the scanner deck and edger stand on. Boards cross the
transfer from the unscrambler (operator side, large -Y) towards the lineal infeed at Y = 0. ``Ye`` below is
the drawing's transfer distance from the infeed centre line (Y = -Ye). The zero lumber line (board ends) is
at X = ZERO_X. Every chain loop is described by its carrying run, drawn with the carrying surface on the
left of the direction of travel along the list of points (so lists run towards larger Ye or larger X).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "edger_4ta36"))
import mesh_lib as L  # noqa: E402
import edger_build as E  # noqa: E402
from edger_build import IN, P, span, cyl, rod, beam, obj  # noqa: E402

COLL = "Line_3338"

LL_Z = 44.0                     # top of chain / lumber line on the raised deck
LOWER_Z = -51.625               # lower floor the unscrambler stands on
ZERO_X = -7.75                  # zero lumber line: board ends are pulled to here
EDGER_Z = 13.0                  # edger on 12 1/2 in sub-steel: its lumber line lands on LL_Z

INFEED_X0, INFEED_X1 = -239.75, -6.0
STATIONS = (-28.25, -75.25, -113.25, -165.25)          # positioner / cushion stations
HOLD_X = (-24.0, -68.6, -108.0)                        # overhead hold-down press rolls
RAMP_X = (-18.0, -52.0, -95.0, -140.0, -190.0, -225.0)  # parking ramps

SCAN_X = tuple(ZERO_X - 9.0 - 26.0 * k for k in range(9))
SCAN_YE = (43.5, 227.0)
SCANNER_YE = 121.0
ZERO_ROLL_YE = 196.0
def _clear_of(xs, others, gap=3.5):
    """Nudge chain positions that sit alongside another section's chain to at least ``gap`` apart."""
    out = []
    for x in xs:
        near = min(others, key=lambda o: abs(o - x))
        if abs(near - x) < gap:
            x = near + (gap if x >= near else -gap)
        out.append(x)
    return tuple(out)


LUG_X = _clear_of(tuple(ZERO_X - d for d in (13, 39, 59, 85, 111, 140, 162.5, 207)), SCAN_X)
LUG_YE = (234.0, 292.0)        # shafts of neighbouring sections clear each other's sprockets
STOP_YE = (239.0, 266.0)        # pop-up stops: at the scanner end, and the halfway set
FLIP_YE = 268.0                 # flipper D's on the halfway shaft
TAKE_X = _clear_of(tuple(ZERO_X - d for d in (20.75, 51.25, 88.25, 129.25, 170.25, 211.25)), LUG_X)
TAKE_YE = (298.0, 313.5)
UNS_PAIRS = tuple((ZERO_X - a, ZERO_X - b) for a, b in ((25, 47), (62, 84), (99, 125), (140, 166), (181, 207)))
UNS_TOP_YE, UNS_R, UNS_ANGLE = 322.0, 72.0, 40.0
FEED_CHAIN_X = tuple(ZERO_X - d for d in (36, 73, 112, 153, 194))
WALL_YE = 305.0                 # edge of the raised floor


def Ye(y):
    return -y


# ---------------------------------------------------------------- generic pieces

def plate_yz(bm, pts, x0, x1, mi=0):
    """Convex polygon given as (Ye, z) points, extruded along X from x0 to x1."""
    a = [bm.verts.new(P(x0, -u, v)) for u, v in pts]
    b = [bm.verts.new(P(x1, -u, v)) for u, v in pts]
    faces = [bm.faces.new(a), bm.faces.new(b[::-1])]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((a[i], b[i], b[j], a[j])))
    for f in faces:
        f.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def offset_path(path, d):
    """Offset a 2D polyline by d along its left normal."""
    out = []
    for i, p in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, len(path) - 1)]
        t = (b - a).normalized()
        out.append(p + Vector((-t.y, t.x)) * d)
    return out


def arc(c, r, a0, a1, n):
    return [c + Vector((math.cos(a0 + (a1 - a0) * k / n), math.sin(a0 + (a1 - a0) * k / n))) * r for k in range(n + 1)]


def loop_from_path(path, rs):
    """Closed chain loop (2D) round two sprockets: carrying run along ``path`` (first point = tail end the chain
    leaves, last = head), sprocket radius rs under each end, return run underneath."""
    def left(i0, i1):
        t = (path[i1] - path[i0]).normalized()
        return Vector((-t.y, t.x))
    n0, n1 = left(0, 1), left(-2, -1)
    c0, c1 = path[0] - n0 * rs, path[-1] - n1 * rs
    a1 = math.atan2(n1.y, n1.x)
    a0 = math.atan2(n0.y, n0.x)
    ret = offset_path(path, -2 * rs)[::-1]
    loop = list(path) + arc(c1, rs, a1, a1 - math.pi, 10)[1:-1] + ret + arc(c0, rs, a0 - math.pi, a0 - 2 * math.pi, 10)[1:-1]
    return loop, c0, c1


def walk(loop, pitch):
    """Points every ``pitch`` along a closed 2D loop, with their tangents."""
    segs = [(loop[i], loop[(i + 1) % len(loop)]) for i in range(len(loop))]
    total = sum((b - a).length for a, b in segs)
    n = max(4, round(total / pitch))
    step = total / n
    pts, s, i, acc = [], 0.0, 0, 0.0
    for k in range(n):
        target = k * step
        while acc + (segs[i][1] - segs[i][0]).length < target:
            acc += (segs[i][1] - segs[i][0]).length
            i += 1
        a, b = segs[i]
        t = (target - acc) / max((b - a).length, 1e-9)
        pts.append((a + (b - a) * t, (b - a).normalized()))
    return pts


class Chain:
    """Roller chain built link by link round a 2D loop placed in a vertical plane.

    ``to3d(u, v)`` maps loop coordinates to 3D inches; ``side`` is the world axis across the chain.
    """

    def __init__(self, bm_plate, bm_roller, to3d, side, gauge=1.0, plate_h=1.2, plate_t=0.18, roller_r=0.4):
        self.bp, self.br, self.to3d, self.side = bm_plate, bm_roller, to3d, Vector(side)
        self.g, self.h, self.t, self.r = gauge, plate_h, plate_t, roller_r

    def build(self, loop, pitch, lug_every=0, lug_h=2.5, bm_lug=None, lug_w=2.5, points=False):
        pts = walk(loop, pitch)
        for k, (p, tan) in enumerate(pts):
            q = pts[(k + 1) % len(pts)][0]
            a, b = Vector(self.to3d(*p)), Vector(self.to3d(*q))
            off = self.g / 2 + (self.t / 2 if k % 2 == 0 else self.t * 1.5)
            for sg in (-1, 1):
                d = self.side * sg * off
                L.add_beam(self.bp, (a + d) * IN, (b + d) * IN, self.h * IN, self.t * IN, up=tuple(self.side))
            L.add_rod(self.br, (a - self.side * self.g / 2) * IN, (a + self.side * self.g / 2) * IN, self.r * IN, segs=8)
            nrm = Vector((-tan.y, tan.x))
            if points and k % 2 == 0:
                tip = Vector(self.to3d(*(p + (q - p) * 0.5 + nrm * (self.h / 2 + 0.45))))
                base = Vector(self.to3d(*(p + (q - p) * 0.5 + nrm * (self.h / 2 - 0.05))))
                L.add_beam(self.bp, base * IN, tip * IN, 0.3 * IN, self.g * 0.8 * IN, up=tuple(self.side))
            if lug_every and bm_lug is not None and k % lug_every == 0:
                base = Vector(self.to3d(*(p + nrm * (self.h / 2 - 0.1))))
                tip = Vector(self.to3d(*(p + nrm * (self.h / 2 + lug_h))))
                L.add_beam(bm_lug, base * IN, tip * IN, 0.75 * IN, lug_w * IN, up=tuple(self.side))


def yz(x):
    return lambda u, v: (x, -u, v)


def sprocket_x(bm, x, ye, z, r, t=0.6):
    cyl(bm, (x, -ye, z), r, t, 'x', 0, 24)
    cyl(bm, (x, -ye, z), r * 0.45, t + 1.4, 'x', 0, 16)


def gearmotor(bm, x0, y, z, hp_r, along=-1):
    """Inline gear motor on a base, output shaft along X towards ``x0``; body extends along -X by default."""
    m = hp_r
    span(bm, (x0, y - m * 1.1, z - m * 1.1), (x0 + along * 5.0, y + m * 1.1, z + m * 1.1))                 # reducer on the shaft end
    cyl(bm, (x0 + along * (5 + m * 1.5), y, z), m, m * 3.0, 'x', 0, 20)            # motor


def legs(bm, pts, z_top, z_floor, w=3.0):
    for x, y in pts:
        span(bm, (x - w / 2, y - w / 2, z_floor), (x + w / 2, y + w / 2, z_top))
        span(bm, (x - w, y - w, z_floor), (x + w, y + w, z_floor + 0.5))


# ---------------------------------------------------------------- lineal infeed

def build_infeed(coll, M):
    bm = bmesh.new()     # frame (green)
    bmo = bmesh.new()    # moving parts (orange)
    bms = bmesh.new()    # shafts, race (steel)
    bmc = bmesh.new()    # cylinders (black)
    bmy = bmesh.new()    # cones (yellow)
    x0, x1 = INFEED_X0, INFEED_X1
    # Base frame: two side channels on legs, centre beam carrying the chain race.
    for y in (-9.0, 9.0):
        span(bm, (x0, y - 0.25, 24.0), (x1, y + 0.25, 30.0))
    span(bm, (x0, -3.0, 24.0), (x1, 3.0, 30.0))
    for x in [x0 + 2] + list(range(int(x0) + 40, int(x1), 40)) + [x1 - 2]:
        span(bm, (x - 1.5, -9.0, 24.0), (x + 1.5, 9.0, 26.0))
        legs(bm, [(x, -9.0), (x, 9.0)], 24.0, 0.0)
    for sg in (-1, 1):                                       # race webs straddling the return chain
        span(bm, (x0 + 6, sg * 1.6, 30.0), (x1 - 1, sg * 1.9, 41.4))
    span(bms, (x0 + 6, -1.9, 41.4), (x1 - 1, 1.9, 42.8))     # machined race
    # Centerline chain: 5-point sharp-top chain round head (edger end) and tail sprockets.
    path = [Vector((x0 + 8.0, LL_Z - 0.6)), Vector((x1 - 2.0, LL_Z - 0.6))]
    loop, c0, c1 = loop_from_path(path, 4.0)
    bmp, bmr = bmesh.new(), bmesh.new()
    Chain(bmp, bmr, lambda u, v: (u, 0.0, v), (0, 1, 0)).build(loop, 1.5, points=True)
    for c in (c0, c1):
        cyl(bms, (c.x, 0, c.y), 4.2, 0.6, 'y', 0, 24)
        cyl(bms, (c.x, 0, c.y), 0.9, 7.0, 'y', 0, 12)
        for sg in (-1, 1):
            span(bm, (c.x - 2.0, sg * 3.5 - 0.5, 24.0), (c.x + 2.0, sg * 3.5 + 0.5, c.y + 1.5))   # sprocket bearing plates
    span(bm, (c0.x - 10.0, -2.5, 30.0), (c0.x - 4.5, 2.5, 34.0))                                 # chain tensioner
    # Parking ramps: orange plates on short shafts, all on one linkage bar and hydraulic cylinder.
    for x in RAMP_X:
        plate_yz(bmo, [(8.0, 36.5), (17.0, 41.0), (15.0, 45.2), (2.6, 44.7), (2.6, 43.6), (5.0, 37.5)], x - 0.375, x + 0.375)   # stops short of the race
        cyl(bms, (x, -10.0, 38.0), 1.1, 6.0, 'x', 0, 16)
        for dx in (-3.0, 3.0):
            span(bm, (x + dx - 0.5, -12.5, 30.0), (x + dx + 0.5, -7.5, 38.0))                    # bearing posts
        span(bmo, (x - 0.4, -15.5, 33.0), (x + 0.4, -10.0, 38.0))                                 # lever arm
    span(bms, (RAMP_X[-1] - 2.0, -15.4, 33.5), (RAMP_X[0] + 2.0, -14.6, 34.5))                 # linkage bar
    cyl(bmc, (RAMP_X[-1] - 7.5, -15.0, 34.0), 1.4, 12.0, 'x', 0, 16)                           # ramp cylinder
    # Positioners (operator side) and cushion shoes (drive side) at each station.
    for x in STATIONS:
        span(bm, (x - 2.5, -50.0, 15.0), (x + 2.5, 12.0, 17.0))                                  # guide rail
        legs(bm, [(x, -48.0), (x, 10.0)], 15.0, 0.0, 2.5)
        cyl(bmc, (x, 34.0, 20.0), 1.5, 44.0, 'y', 0, 16)                                          # 2 x 42 setworks cylinder
        span(bm, (x - 2.0, 11.0, 15.0), (x + 2.0, 13.0, 23.0))
        span(bm, (x - 2.0, 55.0, 0.0), (x + 2.0, 57.0, 23.0))
        rod(bms, (x, 12.0, 20.0), (x, -26.0, 20.0), 0.5, 0, 10)                                   # rod under the race
        span(bmo, (x - 2.5, -30.0, 17.0), (x + 2.5, -24.0, 23.0))                                 # positioner carriage
        span(bmo, (x - 1.0, -29.0, 23.0), (x + 1.0, -27.0, LL_Z + 2.0))                           # pivoting head arm
        span(bmo, (x - 2.0, -30.0, LL_Z - 1.0), (x + 2.0, -25.5, LL_Z + 4.0))                     # head with insert
        cyl(bmy, (x, -24.6, LL_Z + 1.5), 1.2, 1.8, 'y', 0, 16, r2=0.3)
        cyl(bmc, (x - 3.5, -27.0, 26.0), 0.9, 7.0, 'z', 0, 12)                                    # head pivot air cylinder
        # Cushion shoe on the far (drive) side.
        span(bm, (x - 2.0, 9.0, 30.0), (x + 2.0, 13.0, LL_Z + 6.0))
        cyl(bmc, (x, 19.0, LL_Z + 2.5), 1.6, 12.0, 'y', 0, 16)
        rod(bms, (x, 13.0, LL_Z + 2.5), (x, 6.0, LL_Z + 2.5), 0.5, 0, 10)
        span(bmo, (x - 3.0, 4.5, LL_Z + 0.5), (x + 3.0, 6.0, LL_Z + 5.0))
    # Overhead hold-down press rolls: post on the drive side, arm over the chain, air cylinder down to the roll.
    for x in HOLD_X:
        span(bm, (x - 2.0, 16.0, 0.0), (x + 2.0, 20.0, 72.0))
        span(bm, (x - 2.0, -4.0, 68.0), (x + 2.0, 20.0, 72.0))
        cyl(bmc, (x, 0, 62.0), 2.5, 12.0, 'z', 0, 20)
        rod(bms, (x, 0, 56.0), (x, 0, 54.0 + 1.5), 0.6, 0, 10)
        for sg in (-1, 1):
            span(bm, (x - 1.0, sg * 6.6 - 0.4, 50.0), (x + 1.0, sg * 6.6 + 0.4, 55.5))
        span(bm, (x - 1.0, -7.0, 55.5), (x + 1.0, 7.0, 57.0))
        cyl(bms, (x, 0, 50.0), 4.0, 12.0, 'y', 0, 24)                                            # roll on a 2 in board
        cyl(bms, (x, 0, 50.0), 0.8, 14.0, 'y', 0, 12)                                            # axle into the yoke
    out = [obj("Infeed_Frame", bm, coll, [M["green"]], bevel=0.003, segs=1),
           obj("Infeed_Moving", bmo, coll, [M["orange"]], bevel=0.003, segs=1),
           obj("Infeed_Steel", bms, coll, [M["steel"]], bevel=0.0),
           obj("Infeed_Cylinders", bmc, coll, [M["hydraulic"]], bevel=0.002, segs=1),
           obj("Infeed_Cones", bmy, coll, [M["yellow"]], bevel=0.0),
           obj("Infeed_ChainPlates", bmp, coll, [M["chain"]], bevel=0.0, smooth=10),
           obj("Infeed_ChainRollers", bmr, coll, [M["steel"]], bevel=0.0)]
    return out


# ---------------------------------------------------------------- transfer chains

def chain_module(coll, M, name, xs, ye0, ye1, rs=4.0, pitch=2.6, lug_every=0, drive_at="head", leg_ye=None):
    """A set of parallel transfer chains running in Ye from ye0 (tail) to ye1 (head) at the deck height."""
    bm, bms, bmw = bmesh.new(), bmesh.new(), bmesh.new()      # frame, shafts/sprockets, UHMW
    bmp, bmr, bml = bmesh.new(), bmesh.new(), bmesh.new()
    zc = LL_Z - 0.6
    path = [Vector((ye0, zc)), Vector((ye1, zc))]
    loop, c_head, c_tail = loop_from_path(path, rs)
    depth = 2 * rs - 2.6                                        # stringer fits between the carrying and return runs
    for x in xs:
        Chain(bmp, bmr, yz(x), (1, 0, 0)).build(loop, pitch, lug_every=lug_every, bm_lug=bml)
        span(bm, (x - 1.5, -(ye1 - rs - 0.5), zc - 1.2 - depth), (x + 1.5, -(ye0 + rs + 0.5), zc - 1.2))   # stringer
        span(bmw, (x - 1.3, -(ye1 - rs - 0.5), zc - 0.6 - 0.6), (x + 1.3, -(ye0 + rs + 0.5), zc - 0.6))         # wear strip
        for c in (c_head, c_tail):
            sprocket_x(bms, x, c.x, c.y, rs + 0.2)
    xa, xb = min(xs) - 6.0, max(xs) + 4.0
    for c in (c_head, c_tail):
        cyl(bms, ((xa + xb) / 2, -c.x, c.y), 1.0, xb - xa, 'x', 0, 16)                          # shaft
        for x in (xa, xb):
            span(bm, (x - 1.5, -c.x - 2.0, 0.0), (x + 1.5, -c.x + 2.0, c.y - 1.0))               # bearing stands
            span(bm, (x - 2.0, -c.x - 2.0, c.y - 1.0), (x + 2.0, -c.x + 2.0, c.y + 1.0))
    beam_top = zc - 2 * rs - 0.9 - (lug_every and 3.0)           # under the return run (and its lugs)
    for ye in (leg_ye or [ye0 + rs + 6.0, (ye0 + ye1) / 2, ye1 - rs - 6.0]):
        span(bm, (xa, -ye - 2.0, beam_top - 5.0), (xb, -ye + 2.0, beam_top))                       # cross beam
        for x in xs:                                                     # stringer posts beside the return run
            span(bm, (x + 1.5, -ye - 1.0, beam_top), (x + 2.5, -ye + 1.0, zc - 1.2))
        legs(bm, [(xa + 2.0, -ye), (xb - 2.0, -ye), ((xa + xb) / 2, -ye)], beam_top - 5.0, 0.0)
    bmm = bmesh.new()
    c_drive = c_head if drive_at == "head" else c_tail
    gearmotor(bmm, xa, -c_drive.x, c_drive.y, 3.0)
    out = [obj(name + "_Frame", bm, coll, [M["green"]], bevel=0.003, segs=1),
           obj(name + "_Shafts", bms, coll, [M["steel"]], bevel=0.0),
           obj(name + "_WearStrips", bmw, coll, [M["uhmw"]], bevel=0.0),
           obj(name + "_ChainPlates", bmp, coll, [M["chain"]], bevel=0.0, smooth=10),
           obj(name + "_ChainRollers", bmr, coll, [M["steel"]], bevel=0.0),
           obj(name + "_Drive", bmm, coll, [M["motor"]], bevel=0.003, segs=1)]
    if lug_every:
        out.append(obj(name + "_Lugs", bml, coll, [M["chain"]], bevel=0.0))
    return out


def build_scanner(coll, M):
    """Scanner frame across all the chains at the scanner centre line, sensor heads above and below."""
    bm, bmh, bmd = bmesh.new(), bmesh.new(), bmesh.new()
    y = -SCANNER_YE
    xa, xb = ZERO_X - 290.0, ZERO_X + 6.0
    for x in (xa, xb):
        span(bm, (x - 3.0, y - 15.0, 0.0), (x + 3.0, y + 15.0, 4.0))
        for sg in (-1, 1):
            span(bm, (x - 2.0, y + sg * 12.0 - 2.0, 0.0), (x + 2.0, y + sg * 12.0 + 2.0, 66.0))
        span(bm, (x - 2.0, y - 14.0, 62.0), (x + 2.0, y + 14.0, 66.0))
    span(bm, (xa, y - 5.0, 60.0), (xb, y + 5.0, 66.0))                                          # top beam
    span(bm, (xa, y - 5.0, 22.0), (xb, y + 5.0, 27.0))                                          # bottom beam
    for x in (xa, xb):
        span(bm, (x - 2.0, y - 10.0, 22.0), (x + 2.0, y + 10.0, 27.0))                          # ties to the uprights
    for k in range(int((xb - xa - 12.0) / 14.5) + 1):
        x = xa + 6.0 + 14.5 * k
        span(bmh, (x - 3.0, y - 4.0, 53.0), (x + 3.0, y + 4.0, 60.0))                           # top heads
        if all(abs(x - cx) > 4.0 for cx in SCAN_X):
            span(bmh, (x - 3.0, y - 4.0, 27.0), (x + 3.0, y + 4.0, 33.0))                       # bottom heads
    cyl(bmd, ((xa + xb) / 2, y, 72.0), 6.0, xb - xa, 'x', 0, 24)                                # 12 in blower duct
    for x in (xa + 20.0, (xa + xb) / 2, xb - 20.0):
        span(bmd, (x - 1.0, y - 1.0, 66.0), (x + 1.0, y + 1.0, 66.5))
    return [obj("Scanner_Frame", bm, coll, [M["green"]], bevel=0.003, segs=1),
            obj("Scanner_Heads", bmh, coll, [M["motor"]], bevel=0.003, segs=1),
            obj("Scanner_Duct", bmd, coll, [M["steel"]], bevel=0.0)]


def build_zero_rollers(coll, M):
    """Rollers between the scanner chains that pull each board endwise to the zero line."""
    bm, bms = bmesh.new(), bmesh.new()
    xs = sorted(SCAN_X)
    for a, b in zip(xs, xs[1:]):
        x = (a + b) / 2
        cyl(bms, (x, -ZERO_ROLL_YE, LL_Z - 1.7), 2.0, 12.0, 'y', 0, 20)
        cyl(bms, (x, -ZERO_ROLL_YE, LL_Z - 1.7), 0.6, 16.0, 'y', 0, 10)
        for sg in (-1, 1):
            span(bm, (x - 1.5, -ZERO_ROLL_YE + sg * 7.0 - 0.5, LL_Z - 13.0), (x + 1.5, -ZERO_ROLL_YE + sg * 7.0 + 0.5, LL_Z - 1.0))
        span(bm, (x - 2.5, -ZERO_ROLL_YE - 8.0, LL_Z - 14.0), (x + 2.5, -ZERO_ROLL_YE + 8.0, LL_Z - 13.0))
        legs(bm, [(x, -ZERO_ROLL_YE)], LL_Z - 14.0, 0.0, 2.0)
        span(bm, (x - 2.0, -ZERO_ROLL_YE + 8.0, LL_Z - 6.0), (x + 2.0, -ZERO_ROLL_YE + 14.0, LL_Z - 1.5))   # hydraulic drive
    return [obj("ZeroRollers_Frame", bm, coll, [M["green"]], bevel=0.003, segs=1),
            obj("ZeroRollers_Rolls", bms, coll, [M["chrome"]], bevel=0.0)]


def build_lug_loader_extras(coll, M):
    """Pop-up stops at the scanner end and halfway, and the flipper D's on the halfway shaft."""
    bmo, bmc, bms = bmesh.new(), bmesh.new(), bmesh.new()
    xa, xb = min(LUG_X) - 6.0, max(LUG_X) + 4.0
    for ye in STOP_YE:
        for x in LUG_X:
            span(bmo, (x + 1.9, -ye - 0.6, LL_Z - 6.0), (x + 3.1, -ye + 0.6, LL_Z + 2.5))          # stop (up)
            cyl(bmc, (x + 2.5, -ye, LL_Z - 9.5), 0.9, 7.0, 'z', 0, 12)                             # air cylinder
    cyl(bms, ((xa + xb) / 2, -FLIP_YE, LL_Z - 2.5), 1.1, xb - xa, 'x', 0, 16)                     # flipper shaft
    xs = sorted(LUG_X)
    for a, b in zip(xs, xs[1:]):
        x = (a + b) / 2
        d = [(FLIP_YE + 3.2 * math.cos(math.pi + math.pi * k / 12), LL_Z - 0.4 + 3.2 * math.sin(math.pi + math.pi * k / 12)) for k in range(13)]
        plate_yz(bmo, d, x - 0.5, x + 0.5)                                                           # D: flat side up
    gm = bmesh.new()
    span(gm, (xa - 8.0, -FLIP_YE - 4.0, LL_Z - 7.0), (xa, -FLIP_YE + 4.0, LL_Z + 1.0))             # rotary actuator
    return [obj("LugLoader_Stops", bmo, coll, [M["orange"]], bevel=0.002, segs=1),
            obj("LugLoader_StopCyls", bmc, coll, [M["hydraulic"]], bevel=0.0),
            obj("LugLoader_FlipShaft", bms, coll, [M["steel"]], bevel=0.0),
            obj("LugLoader_FlipActuator", gm, coll, [M["hydraulic"]], bevel=0.002, segs=1)]


# ---------------------------------------------------------------- unscrambler and feed chains

def unscrambler_path():
    """Carrying run from the foot up the 40 degree incline and over the 6 ft radius to the top discharge."""
    zc = LL_Z - 0.9
    a = math.radians(UNS_ANGLE)
    c = Vector((UNS_TOP_YE, zc - UNS_R))
    top_arc = arc(c, UNS_R, math.pi / 2 - a, math.pi / 2, 12)            # from incline tangent to horizontal
    t0 = top_arc[0]
    foot_z = LOWER_Z + 15.75
    run = (t0.y - foot_z) / math.sin(a)
    foot = t0 + Vector((math.cos(a), -math.sin(a))) * run
    path = [foot] + top_arc + [Vector((UNS_TOP_YE - 2.0, zc))]
    return [Vector((p.x, p.y)) for p in path]


def build_unscrambler(coll, M):
    bm, bms, bmw = bmesh.new(), bmesh.new(), bmesh.new()
    bmp, bmr, bmb = bmesh.new(), bmesh.new(), bmesh.new()
    path = unscrambler_path()
    up_path = path[::-1]                       # discharge -> foot, Ye increasing, carrying surface on the left
    loop, c_top, c_foot = loop_from_path(up_path, 5.0)
    for pair in UNS_PAIRS:
        for x in pair:
            Chain(bmp, bmr, yz(x), (1, 0, 0), gauge=1.4, plate_h=1.75, plate_t=0.25, roller_r=0.6).build(loop, 4.06)
            for c in (c_top, c_foot):
                sprocket_x(bms, x, c.x, c.y, 5.3, 0.8)
        # Carrier bars with lugs across each pair, every 30 in.
        for p, tan in walk(loop, 30.0):
            nrm = Vector((-tan.y, tan.x))
            q = p + nrm * 1.2
            base, tip = q, q + nrm * 2.0
            L.add_beam(bmb, P(min(pair) - 1.2, -base.x, base.y), P(max(pair) + 1.2, -base.x, base.y), 1.0 * IN, 1.0 * IN)
            lug = q + nrm * 3.2
            L.add_beam(bmb, P(min(pair) + 2.0, -q.x, q.y), P(min(pair) + 2.0, -lug.x, lug.y), 1.0 * IN, 2.0 * IN, up=(1, 0, 0))
            L.add_beam(bmb, P(max(pair) - 2.0, -q.x, q.y), P(max(pair) - 2.0, -lug.x, lug.y), 1.0 * IN, 2.0 * IN, up=(1, 0, 0))
    # Deck plate and UHMW chainways under the carrying run, side stringers on legs to the lower floor.
    xs = [x for pr in UNS_PAIRS for x in pr]
    xa, xb = min(xs) - 8.0, max(xs) + 8.0
    deck = offset_path(up_path, -0.9 - 0.6)
    under = offset_path(up_path, -0.9 - 1.1)
    for i in range(len(deck) - 1):
        a, b = deck[i], deck[i + 1]
        a2, b2 = under[i], under[i + 1]
        plate_yz(bm, [(a.x, a.y), (b.x, b.y), (b2.x, b2.y), (a2.x, a2.y)], xa, xb)
        for x in xs:
            w0, w1 = offset_path(up_path, -0.9)[i], offset_path(up_path, -0.9)[i + 1]
            plate_yz(bmw, [(w0.x, w0.y), (w1.x, w1.y), (b.x, b.y), (a.x, a.y)], x - 1.2, x + 1.2)
    side = offset_path(up_path, -1.5)
    side_lo = offset_path(up_path, -12.0)
    for x in (xa - 0.5, xb + 0.5):
        for i in range(len(side) - 1):
            plate_yz(bm, [(side[i].x, side[i].y), (side[i + 1].x, side[i + 1].y), (side_lo[i + 1].x, side_lo[i + 1].y), (side_lo[i].x, side_lo[i].y)],
                     x - 0.25, x + 0.25)
    for ye in (330.0, 360.0, 390.0, 420.0):
        z_top = None
        for i in range(len(side_lo) - 1):
            a, b = side_lo[i], side_lo[i + 1]
            if min(a.x, b.x) <= ye <= max(a.x, b.x):
                z_top = a.y + (b.y - a.y) * (ye - a.x) / (b.x - a.x)
        if z_top is not None and z_top > LOWER_Z + 6:
            legs(bm, [(xa - 0.5 - 1.5, -ye), (xb + 0.5 + 1.5, -ye)], z_top + 1.0, LOWER_Z, 3.0)
            span(bm, (xa - 3.5, -ye - 1.5, z_top - 4.0), (xb + 3.5, -ye + 1.5, z_top - 1.0))
    for c in (c_top, c_foot):
        cyl(bms, ((xa - 18.0 + xb + 3.0) / 2, -c.x, c.y), 1.4, xb - xa + 21.0, 'x', 0, 16)
        for x in (xa - 3.0, xb + 3.0):
            span(bm, (x - 1.75, -c.x - 2.5, c.y - 2.5), (x + 1.75, -c.x + 2.5, c.y + 2.5))   # bearing blocks
            span(bm, (x - 1.5, -c.x - 2.0, LOWER_Z if c is c_foot else 0.0), (x + 1.5, -c.x + 2.0, c.y - 2.5))
    # Pocket at the foot: sloped back plate the boards pile against.
    plate_yz(bm, [(c_foot.x + 9.0, LOWER_Z + 2.0), (c_foot.x + 12.0, LOWER_Z + 2.0), (c_foot.x + 30.0, -1.0), (c_foot.x + 27.0, -1.0)], xa, xb)
    span(bm, (xa, -(c_foot.x + 12.0), LOWER_Z), (xb, -(c_foot.x + 9.0), LOWER_Z + 2.0))
    bmm = bmesh.new()
    gearmotor(bmm, xa - 18.0, -c_top.x, c_top.y, 6.0)                                          # 25 hp unscrambler drive
    span(bm, (xa - 45.0, -c_top.x - 9.0, LOWER_Z), (xa - 19.0, -c_top.x + 9.0, c_top.y - 6.6))  # drive stand on the lower floor
    return [obj("Unscrambler_Frame", bm, coll, [M["green"]], bevel=0.002, segs=1, smooth=20),
            obj("Unscrambler_Shafts", bms, coll, [M["steel"]], bevel=0.0),
            obj("Unscrambler_Chainways", bmw, coll, [M["uhmw"]], bevel=0.0, smooth=20),
            obj("Unscrambler_ChainPlates", bmp, coll, [M["chain"]], bevel=0.0, smooth=10),
            obj("Unscrambler_ChainRollers", bmr, coll, [M["steel"]], bevel=0.0),
            obj("Unscrambler_CarrierBars", bmb, coll, [M["chain"]], bevel=0.0),
            obj("Unscrambler_Drive", bmm, coll, [M["motor"]], bevel=0.003, segs=1)], c_foot


def build_feed_chains(coll, M, c_foot):
    """Chains feeding boards into the unscrambler pocket: level at the raised-deck height, short slope down."""
    bm, bms, bmw, bmp, bmr = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    zc = -0.6
    y_end = c_foot.x + 32.0
    path = [Vector((y_end, zc - 6.0)), Vector((y_end + 10.0, zc)), Vector((y_end + 96.0, zc))]
    loop, c0, c1 = loop_from_path(path, 3.5)
    for x in FEED_CHAIN_X:
        Chain(bmp, bmr, yz(x), (1, 0, 0)).build(loop, 2.6)
        for c in (c0, c1):
            sprocket_x(bms, x, c.x, c.y, 3.7)
        span(bm, (x - 1.5, -(y_end + 92.0), zc - 1.2 - 4.4), (x + 1.5, -(y_end + 12.0), zc - 1.2))
        span(bmw, (x - 1.3, -(y_end + 92.0), zc - 1.2), (x + 1.3, -(y_end + 12.0), zc - 0.6))
    xa, xb = min(FEED_CHAIN_X) - 6.0, max(FEED_CHAIN_X) + 6.0
    for c in (c0, c1):
        cyl(bms, ((xa + xb) / 2, -c.x, c.y), 1.0, xb - xa, 'x', 0, 16)
        for x in (xa, xb):
            span(bm, (x - 1.5, -c.x - 2.0, LOWER_Z), (x + 1.5, -c.x + 2.0, c.y - 1.0))
            span(bm, (x - 2.0, -c.x - 2.0, c.y - 1.0), (x + 2.0, -c.x + 2.0, c.y + 1.0))
    beam_top = zc - 7.0 - 0.9
    for ye in (y_end + 30.0, y_end + 70.0):
        span(bm, (xa, -ye - 2.0, beam_top - 5.0), (xb, -ye + 2.0, beam_top))
        for x in FEED_CHAIN_X:
            span(bm, (x + 1.5, -ye - 1.0, beam_top), (x + 2.5, -ye + 1.0, zc - 1.2))
        legs(bm, [(xa + 2.0, -ye), (xb - 2.0, -ye), ((xa + xb) / 2, -ye)], beam_top - 5.0, LOWER_Z)
    bmm = bmesh.new()
    gearmotor(bmm, xa, -c0.x, c0.y, 3.0)
    return [obj("FeedChains_Frame", bm, coll, [M["green"]], bevel=0.003, segs=1),
            obj("FeedChains_Shafts", bms, coll, [M["steel"]], bevel=0.0),
            obj("FeedChains_WearStrips", bmw, coll, [M["uhmw"]], bevel=0.0),
            obj("FeedChains_ChainPlates", bmp, coll, [M["chain"]], bevel=0.0, smooth=10),
            obj("FeedChains_ChainRollers", bmr, coll, [M["steel"]], bevel=0.0),
            obj("FeedChains_Drive", bmm, coll, [M["motor"]], bevel=0.003, segs=1)]


# ---------------------------------------------------------------- outfeed

def build_picker_belt(coll, M):
    """20 ft belt outfeed behind the edger with two pendulum pickers swung by 18 in stroke cylinders."""
    bm, bms, bmb, bmo, bmc = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    x0, x1 = 112.0, 352.0
    zt = LL_Z - 0.3
    rp = 4.0
    loop = E.hull_of_circles([(x0, zt - rp, rp), (x1, zt - rp, rp)], 32)
    E.outline_band(bmb, loop, -12.0, 12.0, 0.3)
    for x in (x0, x1):
        cyl(bms, (x, 0, zt - rp - 0.3), rp - 0.3, 25.0, 'y', 0, 24)
        cyl(bms, (x, 0, zt - rp - 0.3), 1.0, 31.0, 'y', 0, 12)
    for sg in (-1, 1):
        span(bm, (x0 - 6.0, sg * 13.5 - 0.3, zt - 11.0), (x1 + 6.0, sg * 13.5 + 0.3, zt - 1.0))   # side channels
    span(bm, (x0 + 2.0, -12.5, zt - 9.5), (x1 - 2.0, 12.5, zt - 8.9))                            # slider bed
    for x in range(int(x0), int(x1) + 1, 48):
        legs(bm, [(x, -13.5), (x, 13.5)], zt - 11.0, 0.0, 2.5)
        span(bm, (x - 1.25, -13.5, zt - 11.0), (x + 1.25, 13.5, zt - 9.5))
    bmm = bmesh.new()
    E.motor(bmm, x1 + 2.0, zt - rp - 0.3, 16.0, 14.0, 5.0, zt - 11.0)                           # belt drive
    for xp in (190.0, 290.0):
        for sg in (-1, 1):
            span(bm, (xp - 2.0, sg * 30.0 - 2.0, 0.0), (xp + 2.0, sg * 30.0 + 2.0, 90.0))
        span(bm, (xp - 2.5, -32.0, 86.0), (xp + 2.5, 32.0, 90.0))
        rod(bms, (xp, -4.0, 84.0), (xp, 4.0, 84.0), 0.75, 0, 12)                                # pendulum pivot
        span(bm, (xp - 1.0, -3.0, 84.0), (xp + 1.0, 3.0, 86.0))
        span(bmo, (xp - 1.0, -0.75, LL_Z + 6.0), (xp + 1.0, 0.75, 84.0))                         # pendulum arm
        span(bmo, (xp - 1.0, -10.0, LL_Z + 3.0), (xp + 1.0, 10.0, LL_Z + 7.0))                   # picker paddle
        cyl(bmc, (xp, 18.0, 76.0), 1.75, 20.0, 'y', 0, 16)                                       # 18 in stroke cylinder
        span(bm, (xp - 1.5, 28.0, 74.0), (xp + 1.5, 30.0, 78.0))
        rod(bms, (xp, 8.0, 76.0), (xp, 0.75, 76.0), 0.5, 0, 10)
    return [obj("Outfeed_Frame", bm, coll, [M["green"]], bevel=0.003, segs=1),
            obj("Outfeed_Pulleys", bms, coll, [M["steel"]], bevel=0.0),
            obj("Outfeed_Belt", bmb, coll, [M["rubber"]], bevel=0.0),
            obj("Outfeed_Pickers", bmo, coll, [M["orange"]], bevel=0.002, segs=1),
            obj("Outfeed_PickerCyls", bmc, coll, [M["hydraulic"]], bevel=0.0),
            obj("Outfeed_Drive", bmm, coll, [M["motor"]], bevel=0.003, segs=1)]


# ---------------------------------------------------------------- floors and edger placement

def build_floors(coll, M):
    bm, bmw = bmesh.new(), bmesh.new()
    xa, xb = -340.0, 380.0
    span(bm, (xa, -WALL_YE, -8.0), (xb, 140.0, 0.0))                                            # raised floor
    span(bm, (xa, -620.0, LOWER_Z - 8.0), (xb, -WALL_YE, LOWER_Z))                              # lower floor
    span(bmw, (xa, -WALL_YE - 0.01, LOWER_Z), (xb, -WALL_YE + 10.0, -8.0))                      # retaining wall
    # Edger sub-steel under the jack pads: 12 1/2 in beams plus the levelling pads.
    for y in (-20.4, 20.4, 98.0):
        span(bmw, (-3.0, y - 4.0, 0.0), (108.5, y + 4.0, EDGER_Z))
    return [obj("Floor_Slabs", bm, coll, [M["concrete"]], bevel=0.0),
            obj("Floor_WallAndSubsteel", bmw, coll, [M["concrete"]], bevel=0.0)]


def place_edger(M):
    E.build(M)
    ec = bpy.data.collections[E.COLL]
    root = bpy.data.objects.new("Edger", None)
    ec.objects.link(root)
    root.location.z = EDGER_Z * IN
    for o in list(ec.objects):
        if o.parent is None and o is not root:
            o.parent = root
    return root


def build(M):
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    place_edger(M)
    build_floors(coll, M)
    build_infeed(coll, M)
    chain_module(coll, M, "ScannerChains", SCAN_X, *SCAN_YE, lug_every=10)
    build_scanner(coll, M)
    build_zero_rollers(coll, M)
    chain_module(coll, M, "LugLoader", LUG_X, *LUG_YE, rs=3.5, drive_at="tail")
    build_lug_loader_extras(coll, M)
    chain_module(coll, M, "TakeAway", TAKE_X, *TAKE_YE, rs=3.0, drive_at="tail", leg_ye=[(TAKE_YE[0] + TAKE_YE[1]) / 2])
    _, c_foot = build_unscrambler(coll, M)
    build_feed_chains(coll, M, c_foot)
    build_picker_belt(coll, M)
    return {"objects": len(coll.all_objects)}
