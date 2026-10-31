"""Procedural green stacker line after the bin sorter (run inside Blender after sorter_build).

Same frame as the sorter (Godot axes: +X travel, +Y up, +Z along the board length, origin
where the board incline hands over), so the line continues straight on from the sorter's
haul-out and the game places both machines with one transform.

Board path (every step is a physical part):
1. Sorter packs leave the haul-out head onto the surge chains, which hold several packs so
   the sorter never waits. Pop-up pack stops at the surge head let one pack go at a time.
2. The pack drops off the surge head into the unscrambler pocket. The unscrambler's lug chains
   climb out of the pocket at 35 deg; each lug lifts one board. Boards riding on top of
   another slide back into the pocket, because the slope is steeper than their friction angle.
3. Over the unscrambler head the board crosses a slotted dead plate onto the stacker infeed
   chains. Line-up rolls between the chains drive every board endwise against the line-up
   fence (the -Z side), so all the ends line up.
4. Boards gather against the layer stops into one package-wide layer. The forks, lying
   between the chains, lift the layer, carry it out over the package and the pull-back fence
   drops behind it; the forks pull back and the layer falls onto the package.
5. Stick magazines over the package lay a stick across the new layer at every stick line;
   the hoist lowers by one board plus one stick. A full package sets down on the outfeed
   chains and runs out to the landing stops.
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
import mesh_lib as L  # noqa: E402
import sorter_build as S  # noqa: E402

G, gbox, gbox_span, gcyl, grod, gbeam, ibeam, obj = S.G, S.gbox, S.gbox_span, S.gcyl, S.grod, S.gbeam, S.ibeam, S.obj

COLL = "GreenStacker"
INCH = 0.0254

# ---------------------------------------------------------------- surge chains
SURGE_Z = (-1.575, -0.525, 0.525, 1.575)        # between the sorter's haul strands
SURGE_PITCH = 0.10
SURGE_TEETH = 6
SURGE_SPR = SURGE_PITCH / (2 * math.sin(math.pi / SURGE_TEETH))
SURGE_TOP = S.HAUL_TOP                          # level with the haul-out
SURGE_SHAFT_Y = SURGE_TOP - 0.015 - SURGE_SPR
SURGE_TAIL = S.HAUL_X_HEAD - 0.10               # tail sprockets reach in between the haul strands
SURGE_HEAD = 21.30
SURGE_STOP_X = SURGE_HEAD - SURGE_SPR - 0.20    # pack stops, just short of the head
SURGE_STOP_Z = (-2.1, -1.05, 0.0, 1.05, 2.1)
SURGE_BEARING_Z = 2.0

# ---------------------------------------------------------------- unscrambler
UNS_Z = (-2.1, -1.05, 0.0, 1.05, 2.1)
UNS_ANGLE = math.radians(35.0)
UNS_PITCH = 0.10
UNS_TEETH = 8
UNS_SPR = UNS_PITCH / (2 * math.sin(math.pi / UNS_TEETH))
UNS_PLATE_H = 0.015                             # link plates reach this far over the pins
UNS_LUG_H = 0.045                               # lug face above the chain top: holds one board
UNS_LUG_EVERY = 6                               # one lug per 0.6 m
INFEED_TOP = 2.60                               # stacker infeed chain tops
UNS_HEAD = Vector((25.35, INFEED_TOP - UNS_SPR - UNS_PLATE_H + 0.015))
UNS_DIR = Vector((math.cos(UNS_ANGLE), math.sin(UNS_ANGLE)))
UNS_NORMAL = Vector((-UNS_DIR.y, UNS_DIR.x))
UNS_FOOT = UNS_HEAD - UNS_DIR * ((UNS_HEAD.y - 0.02) / UNS_DIR.y)
POCKET_LIP_X = SURGE_HEAD + SURGE_SPR + 0.05

# ---------------------------------------------------------------- stacker infeed
# Same heavy bar chain as the unscrambler (4 in pitch, 8-tooth sprockets) on every deck that
# carries lumber; light chain would not survive the load.
CHAIN_PITCH = 0.10
CHAIN_PLATE_H = 0.015                           # link plates reach this far over the pins
CHAIN_ROLLER_R = 0.02
INF_Z = (-1.575, -0.525, 0.525, 1.575)
INF_PITCH = CHAIN_PITCH
INF_TEETH = 8
INF_SPR = INF_PITCH / (2 * math.sin(math.pi / INF_TEETH))
INF_PIN_Y = INFEED_TOP - CHAIN_PLATE_H
INF_SHAFT_Y = INF_PIN_Y - INF_SPR
INF_TAIL = 25.58                                # stub sprockets, clear of the unscrambler head shaft
INF_HEAD = 29.15
INF_BEAM_TOP = 2.25                             # infeed cross beams sit under the chain return runs
INF_CROSS_X = (25.55, 25.85, 26.95, 29.05)
LINEUP_FENCE_Z = -2.48                          # board ends butt here
FLARE_X0, FLARE_OUT = 25.40, 0.12               # fence flare: a shallow (18 deg) lead-in, so a board end outside
                                                # the fence line is eased in, not braked end-on
ROLL_Z = (-2.1, -1.05, 0.0, 1.05, 2.1)
ROLL_R = 0.075                                  # drum rolls, one per line, a bearing at each end
ROLL_X0, ROLL_X1 = 25.92, 26.88
ROLL_BEARING_X = (25.85, 26.95)                 # on the cross beams
ROLL_XS = ((ROLL_X0 + ROLL_X1) / 2,)
ROLL_LEN = ROLL_X1 - ROLL_X0
LAYER_STOP_X = 28.99                            # front face of the layer stops

# ---------------------------------------------------------------- forks, fence, sticks, hoist
FORK_Z = (-2.1, -1.05, 0.0, 1.05, 2.1)
FORK_X0, FORK_LEN = 27.40, 1.55                 # home: upstream end, tine length
FORK_STROKE = 1.50
FORK_T = 0.05
FORK_HOME_TOP = INFEED_TOP - 0.010              # tucked just under the chain tops
FORK_LIFT = 0.035
FORK_TUBE_Y = 1.95                              # under the infeed cross beams
FRAME_Z = 2.85                                  # infeed frame side lines; the fork trolleys ride them
FRAME_BEAM_TOP = 2.45
TROLLEY_HALF = 0.10                             # trolley half length along X
TROLLEY_Y0 = FRAME_BEAM_TOP + 0.02              # trolley underside, on the rail
FENCE_POST_X = (26.0, 27.0, 29.12)
FENCE_X = 29.10
FENCE_Z = (-1.575, -0.525, 0.525, 1.575)
FENCE_DOWN = FORK_HOME_TOP + FORK_LIFT + 0.004
FENCE_RAISE = 0.20                             # fence stroke: up clears a 2x layer on the forks
STICK_T, STICK_W, STICK_LEN = 0.75 * INCH, 1.5 * INCH, 52 * INCH
STICK_X0 = 29.15
STICK_Z = tuple(-2.40 + k * (4.73 / 8) for k in range(9))
MAG_BOTTOM = 2.75
MAG_TOP = 3.40
HOIST_Z = (-1.575, -0.525, 0.525, 1.575)
HOIST_X0, HOIST_X1 = 29.15, 30.60
HOIST_TOP = FORK_HOME_TOP + FORK_LIFT - FORK_T - 0.010     # arm top when the first layer lands
OUT_Z = (-2.1, -1.05, 0.0, 1.05, 2.1)
OUT_PITCH = CHAIN_PITCH
OUT_TEETH = 6
OUT_SPR = OUT_PITCH / (2 * math.sin(math.pi / OUT_TEETH))
OUT_TOP = 0.45
OUT_SHAFT_Y = OUT_TOP - CHAIN_PLATE_H - OUT_SPR
OUT_TAIL = 28.95
OUT_HEAD = 36.60
HOIST_LOW = OUT_TOP - 0.05                      # arms drop below the outfeed chains
# Landing deck: lift rails between the chains raise a finished package off them, leaving fork
# pockets above the chains; a forklift picks it from the open end. The chains stop when the
# package breaks the end photo eye.
LAND_X0, LAND_X1 = 33.0, 36.45
LAND_Z = (-1.575, -0.525, 0.525, 1.575)
LAND_TOP_DOWN = OUT_TOP - 0.03
LAND_RISE = 0.18
LAND_CYL_X = (33.4, 34.7, 36.0)
LANDING_STOP_X = 36.45                          # package front edge at the end eye: close to the open end for the forks
LAND_RAIL_H = 0.12
LAND_BARREL = 0.25                              # cylinder barrel height off the floor
LAND_ROD = 0.26                                 # rod clears the base lowered, stays engaged raised


def build_landing_lift(coll, M):
    """Landing lift rails, lowered (moving part, rises LAND_RISE): a box rail between each pair
    of outfeed chains, on cylinder rods into the barrels on the floor."""
    bm, bmr = bmesh.new(), bmesh.new()
    for z in LAND_Z:
        gbox_span(bm, (LAND_X0, LAND_TOP_DOWN - LAND_RAIL_H, z - 0.05), (LAND_X1, LAND_TOP_DOWN, z + 0.05))
        for x in LAND_CYL_X:
            gcyl(bmr, (x, LAND_TOP_DOWN - LAND_RAIL_H - LAND_ROD / 2, z), 0.03, LAND_ROD, 'y', segs=12)
    lift = obj("LandingLift", bm, coll, [M["orange"]], bevel=0.003)
    rods = obj("LandingLiftRods", bmr, coll, [M["shaft"]], bevel=0.0)
    rods.parent = lift
    return lift
STICK_FRAME_X = (29.05, 30.75)
STICK_FRAME_Z = 2.95


# ---------------------------------------------------------------- helpers

def loop_path(a, b, r):
    """Chain loop round two equal sprockets (centres a, b in the XY plane): carrying run on
    top from a to b, wrap round b, return underneath, wrap round a. Returns (path, total)."""
    d = (b - a).normalized()
    n = Vector((-d.y, d.x))
    span = (b - a).length
    arc = math.pi * r
    phi0 = math.atan2(n.y, n.x)
    total = 2 * span + 2 * arc

    def path(s, _total=None):
        s %= total
        if s < span:
            return a + n * r + d * s
        s -= span
        if s < arc:
            phi = phi0 - s / r
            return b + Vector((math.cos(phi), math.sin(phi))) * r
        s -= arc
        if s < span:
            return b - n * r - d * s
        s -= span
        phi = phi0 + math.pi - s / r
        return a + Vector((math.cos(phi), math.sin(phi))) * r
    return path, total


def surge_loop():
    return loop_path(Vector((SURGE_TAIL, SURGE_SHAFT_Y)), Vector((SURGE_HEAD, SURGE_SHAFT_Y)), SURGE_SPR)


def uns_loop():
    return loop_path(UNS_FOOT, UNS_HEAD, UNS_SPR)


def infeed_loop():
    return loop_path(Vector((INF_TAIL, INF_SHAFT_Y)), Vector((INF_HEAD, INF_SHAFT_Y)), INF_SPR)


def outfeed_loop():
    return loop_path(Vector((OUT_TAIL, OUT_SHAFT_Y)), Vector((OUT_HEAD, OUT_SHAFT_Y)), OUT_SPR)


def shaft(coll, M, name, x, y, strands, spr, teeth, roller_r, length, shaft_r=0.05, hub_r=0.09):
    """Shaft and keyed sprockets, origin on the shaft axis (the game spins it about Z)."""
    bm = bmesh.new()
    gcyl(bm, (0, 0, 0), shaft_r, length, 'z', mi=0, segs=20)
    for z in strands:
        S.sprocket_ring(bm, teeth, spr, roller_r, 0.03, z, hub_r - 0.005, mi=1)
        gcyl(bm, (0, 0, z), hub_r, 0.09, 'z', mi=0, segs=16)
    return obj(name, bm, coll, [M["shaft"], M["chain"]], bevel=0.002, segs=1, loc=(x, y, 0))


def pillow(bm, x, y, z, s=1.0):
    gbox(bm, (x, y - 0.06 * s, z), (0.26 * s, 0.05 * s, 0.1 * s))
    gcyl(bm, (x, y, z), 0.085 * s, 0.09 * s, 'z', segs=20)


def drag_channels(bm, bmu, x0, x1, strands, top, ret_top, floor_y=0.0):
    """Chain channels on the floor: carrying run slides on the top strip, return on the lower."""
    for z in strands:
        gbox_span(bm, (x0, floor_y, z - 0.09), (x1, top + 0.02, z - 0.07))
        gbox_span(bm, (x0, floor_y, z + 0.07), (x1, top + 0.02, z + 0.09))
        gbox_span(bm, (x0, floor_y, z - 0.09), (x1, floor_y + 0.01, z + 0.09))
        gbox_span(bmu, (x0, top - 0.02, z - 0.07), (x1, top, z + 0.07))
        gbox_span(bmu, (x0, ret_top - 0.02, z - 0.07), (x1, ret_top, z + 0.07))
        gbox_span(bm, (x0, floor_y + 0.01, z - 0.02), (x1, ret_top - 0.02, z + 0.02))


def along(p, t, off=0.0):
    """Point on the unscrambler incline: p is a 2D point on the carrying line, t metres up it,
    off metres out along the normal."""
    q = p + UNS_DIR * t + UNS_NORMAL * off
    return q.x, q.y


def lumber_bmesh():
    bm = bmesh.new()
    bm.verts.layers.float_vector.new("board_off")
    bm.verts.layers.float.new("board_seed")
    return bm


def tag_board(bm, verts):
    """Give one board's vertices their own texture offset and seed (the lumber material reads
    'board_off' and 'board_seed'), so boards merged into one mesh still all look different."""
    off = bm.verts.layers.float_vector["board_off"]          # made by lumber_bmesh(): adding a layer here
    seed = bm.verts.layers.float["board_seed"]               # would invalidate the verts just passed in
    c = sum((v.co for v in verts), Vector()) / len(verts)
    h = math.sin(c.x * 12.9898 + c.y * 78.233 + c.z * 37.719) * 43758.5453
    s = h - math.floor(h)
    # Texture space centred on the board's own pith: a little to one side of the board and
    # 5-30 cm below its face (Blender X across, Z up), so the growth rings show as cathedral
    # arches on the face; a random shift along the length.
    o = Vector((-c.x + math.sin(h * 1.3) * 0.15, -c.y + math.sin(h * 2.1) * 40.0, -c.z + 0.05 + 0.25 * abs(math.sin(h * 3.7))))
    for v in verts:
        v[off] = o
        v[seed] = s
    return verts


def board(bm, x0, y0, t, w, z0=-2.44, length=4.877):
    """Board from its upstream-bottom corner, lying flat, length along Z from z0."""
    return tag_board(bm, gbox_span(bm, (x0, y0, z0), (x0 + w, y0 + t - 0.002, z0 + length)))


def stick(bm, x0, y0, z):
    """Kiln stick lying across the package (along X), material slot 1."""
    return tag_board(bm, gbox_span(bm, (x0, y0, z - STICK_W / 2), (x0 + STICK_LEN, y0 + STICK_T - 0.001, z + STICK_W / 2), 1))


# ---------------------------------------------------------------- surge

def build_surge(coll, M):
    bm, bmu, bmy = bmesh.new(), bmesh.new(), bmesh.new()
    c0, c1 = SURGE_TAIL + SURGE_SPR + 0.08, SURGE_HEAD - SURGE_SPR - 0.08
    drag_channels(bm, bmu, c0, c1, SURGE_Z, SURGE_TOP - CHAIN_PLATE_H - CHAIN_ROLLER_R, SURGE_SHAFT_Y - SURGE_SPR - CHAIN_ROLLER_R)
    for x in [c0 + k * 1.2 for k in range(int((c1 - c0) / 1.2) + 1)]:
        gbox_span(bm, (x - 0.05, 0.0, -1.8), (x + 0.05, 0.08, 1.8))          # floor ties
    for z in (-2.25, 2.25):                                                   # side guides
        gbox_span(bm, (c0, 0.0, z - 0.06), (SURGE_HEAD + 0.2, 0.25, z + 0.06))
    for x in (SURGE_TAIL, SURGE_HEAD):
        for z in (-SURGE_BEARING_Z, SURGE_BEARING_Z):
            pillow(bm, x, SURGE_SHAFT_Y, z)
            gbox_span(bm, (x - 0.15, 0.0, z - 0.08), (x + 0.15, SURGE_SHAFT_Y - 0.085, z + 0.08))
    # Head drive on the shaft end, -Z side.
    hz = -(SURGE_BEARING_Z + 0.35)
    gbox(bm, (SURGE_HEAD, SURGE_SHAFT_Y + 0.05, hz), (0.4, 0.5, 0.34))
    gcyl(bm, (SURGE_HEAD + 0.05, 0.16, hz - 0.37), 0.14, 0.4, 'z', segs=24)
    # Pack stop: a rocker shaft under the chains, fingers rise between the strands.
    for z in SURGE_STOP_Z:
        gbox(bmy, (SURGE_STOP_X + 0.05, 0.06, z), (0.16, 0.12, 0.12))
    obj("SurgeFrame", bm, coll, [M["green"]], bevel=0.004)
    obj("SurgeWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)
    obj("SurgeStopBases", bmy, coll, [M["grey"]], bevel=0.003, segs=1)
    return [shaft(coll, M, "SurgeHeadShaft", SURGE_HEAD, SURGE_SHAFT_Y, SURGE_Z, SURGE_SPR, SURGE_TEETH, CHAIN_ROLLER_R,
                  2 * SURGE_BEARING_Z + 0.3, hub_r=0.07),
            shaft(coll, M, "SurgeTailShaft", SURGE_TAIL, SURGE_SHAFT_Y, SURGE_Z, SURGE_SPR, SURGE_TEETH, CHAIN_ROLLER_R,
                  2 * SURGE_BEARING_Z + 0.3, hub_r=0.07)]


def build_surge_stop(coll, M):
    """Pack stop fingers on a rocker shaft, in stacker coordinates (shown raised)."""
    bm = bmesh.new()
    pivot = (SURGE_STOP_X + 0.10, 0.10)
    gcyl(bm, (*pivot, 0.0), 0.03, 4.4, 'z', segs=14)
    for z in SURGE_STOP_Z:
        gbox_span(bm, (SURGE_STOP_X, 0.06, z - 0.04), (SURGE_STOP_X + 0.06, SURGE_TOP + 0.18, z + 0.04))
        gbox_span(bm, (SURGE_STOP_X, 0.06, z - 0.04), (pivot[0] + 0.04, 0.14, z + 0.04))
    return obj("SurgeStop", bm, coll, [M["orange"]], bevel=0.004)


# ---------------------------------------------------------------- unscrambler

GUARD_H = 0.15                                  # incline side guards: top this far above the bed
GUARD_Z = ((-2.55, LINEUP_FENCE_Z - 0.015), (2.55, 2.55))   # each guard: z at the pocket cheek, z from GUARD_T_IN on
GUARD_T_IN = 2.0


def build_unscrambler(coll, M):
    bm, bmd, bmu, bmy = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    path_len = (UNS_HEAD - UNS_FOOT).length
    base = UNS_FOOT + UNS_NORMAL * UNS_SPR            # carrying run pin line at the foot
    bed_off = UNS_PLATE_H - 0.004                     # bed plate top, just under the chain tops
    # Bed plate strips between the strands, foot to head tangency.
    edges = [-2.45] + [e for z in UNS_Z for e in (z - 0.06, z + 0.06)] + [2.45]
    for za, zb in zip(edges[0::2], edges[1::2]):
        p0, p1 = along(base, 0.05, bed_off - 0.003), along(base, path_len - 0.02, bed_off - 0.003)
        gbeam(bmd, (*p0, (za + zb) / 2), (*p1, (za + zb) / 2), zb - za, 0.006)
    # Chain ways under each strand (carrying and return), and stringers under the bed.
    for z in UNS_Z:
        p0, p1 = along(base, 0.15, -0.020), along(base, path_len - 0.15, -0.020)
        gbeam(bmu, (*p0, z), (*p1, z), 0.05, 0.02)
        p0, p1 = along(base, 0.15, -2 * UNS_SPR - 0.02), along(base, path_len - 0.15, -2 * UNS_SPR - 0.02)
        gbeam(bmu, (*p0, z), (*p1, z), 0.05, 0.02)
        for side in (-1, 1):
            p0, p1 = along(base, 0.1, -0.09), along(base, path_len - 0.1, -0.09)
            gbeam(bm, (*p0, z + side * 0.08), (*p1, z + side * 0.08), 0.012, 0.16)
    # Side stringers and posts down to the floor.
    for z in (-2.6, 2.6):
        p0, p1 = along(base, -0.1, -0.08), along(base, path_len + 0.05, -0.08)
        ibeam_line(bm, p0, p1, z)
        for t in (0.6, 1.8, 3.0, path_len - 0.2):
            px, py = along(base, t, -0.25)
            ibeam(bm, 'y', (px, py / 2, z), py, h=0.2, w=0.2)
    # Cross ties under the strands.
    for t in (0.6, 1.8, 3.0, path_len - 0.2):
        px, py = along(base, t, -0.20)
        gbox(bm, (px, py, 0.0), (0.12, 0.12, 5.3))
    # Pocket: floor sloping from the surge head lip down to the foot of the incline, side
    # sheets, and a back wall so the pack cannot ride back onto the surge chains.
    lip = (POCKET_LIP_X, SURGE_TOP - 0.03)
    low = along(base, 0.05, bed_off - 0.003)
    for za, zb in zip(edges[0::2], edges[1::2]):
        gbeam(bmd, (*lip, (za + zb) / 2), (*low, (za + zb) / 2), zb - za, 0.008)
    for z in (-2.55, 2.55):                       # pocket cheeks: 0.3 m above the pocket floor and bed
        pts = [(lip[0] - 0.05, 0.0), (lip[0] - 0.05, SURGE_TOP + 0.30), along(base, 0.0, 0.30), along(base, 1.4, 0.30),
               along(base, 1.4, -0.12), (low[0] + 0.1, 0.0)]
        L.add_prism(bmd, pts, -(z + 0.006), -(z - 0.006))
    # Incline side guards bolted to the side stringers, on up from the pocket cheeks to short of
    # the head bearings: a short board lying skewed on the lugs slides along them instead of
    # hanging off the side of the bed and dropping to the floor.
    # The -Z guard angles in (about 6 deg) to just outside the line-up fence line, so a long
    # board comes over the crest already lined up instead of meeting the fence flare end-on.
    for z0, z1 in GUARD_Z:
        p0, pm, p1 = (along(base, t, GUARD_H / 2 - 0.08) for t in (1.4, GUARD_T_IN, path_len - 0.4))
        gbeam(bmd, (*p0, z0), (*pm, z1), 0.012, GUARD_H + 0.08)
        gbeam(bmd, (*pm, z1), (*p1, z1), 0.012, GUARD_H + 0.08)
    # Bearings and drive.
    for c, name in ((UNS_FOOT, "foot"), (UNS_HEAD, "head")):
        for z in (-2.45, 2.45):
            pillow(bmy, c.x, c.y, z)
            if name == "head":
                h = c.y - 0.085 - 0.03
                ibeam(bm, 'y', (c.x, h / 2, z), h, h=0.2, w=0.2)
                gbox_span(bm, (c.x - 0.15, h, z - 0.12), (c.x + 0.15, h + 0.03, z + 0.12))    # cap plate
    hz = -2.95
    gbox(bmy, (UNS_HEAD.x, UNS_HEAD.y, hz), (0.42, 0.5, 0.36))
    gcyl(bmy, (UNS_HEAD.x + 0.05, UNS_HEAD.y - 0.15, hz - 0.40), 0.16, 0.45, 'z', segs=24)
    gbox_span(bm, (UNS_HEAD.x - 0.3, 0.0, hz - 0.25), (UNS_HEAD.x + 0.3, UNS_HEAD.y - 0.25, hz + 0.25))
    obj("UnscramblerFrame", bm, coll, [M["green"]], bevel=0.004)
    obj("UnscramblerBed", bmd, coll, [M["deck"]], bevel=0.002, segs=1)
    obj("UnscramblerWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)
    obj("UnscramblerDrive", bmy, coll, [M["grey"]], bevel=0.003, segs=1)
    return [shaft(coll, M, "UnscramblerHeadShaft", UNS_HEAD.x, UNS_HEAD.y, UNS_Z, UNS_SPR, UNS_TEETH, 0.02, 5.2, hub_r=0.08),
            shaft(coll, M, "UnscramblerFootShaft", UNS_FOOT.x, UNS_FOOT.y, UNS_Z, UNS_SPR, UNS_TEETH, 0.02, 5.2, hub_r=0.08)]


# Pocket adjusters: tapered UHMW plates between the unscrambler strands over the upper part of
# the incline, each raised by hydraulic cylinders square to the bed. Set for the board
# thickness so the lugs stand only about three quarters of a board above them: the bottom
# board rides up on the plates pushed by its lug, and a board lying on top of it has nothing
# behind it and slides back into the pocket.
ADJ_Z = (-1.575, -0.525, 0.525, 1.575)          # midway between the strands
ADJ_W = 0.10
ADJ_T0, ADJ_TAPER = 0.9, 0.35                   # start just above the pocket pile (up the incline from the foot pin line), taper length
ADJ_T1 = 2.7                                    # end: low on the incline, so a shed board drops straight back into the pocket
ADJ_DEPTH = 0.05
ADJ_CYL_T = (1.5, 2.4)                          # cylinder positions up the incline


def build_pocket_adjusters(coll, M):
    """Modelled lowered (plate tops flush with the bed); the game raises them along the
    incline's normal."""
    plates, rods, barrels = bmesh.new(), bmesh.new(), bmesh.new()
    path_len = (UNS_HEAD - UNS_FOOT).length
    base = UNS_FOOT + UNS_NORMAL * UNS_SPR
    top = UNS_PLATE_H - 0.004
    t1 = ADJ_T1
    for z in ADJ_Z:
        prof = [along(base, ADJ_T0, top - 0.03), along(base, ADJ_T0 + ADJ_TAPER, top), along(base, t1, top),
                along(base, t1, top - ADJ_DEPTH), along(base, ADJ_T0 + 0.05, top - ADJ_DEPTH)]
        L.add_prism(plates, prof, -(z + ADJ_W / 2), -(z - ADJ_W / 2))
        for t in ADJ_CYL_T:
            a, b = along(base, t, top - ADJ_DEPTH), along(base, t, top - ADJ_DEPTH - 0.16)
            gbeam(rods, (*a, z), (*b, z), 0.024, 0.024)                                   # rod
            c, d = along(base, t, top - ADJ_DEPTH - 0.12), along(base, t, top - ADJ_DEPTH - 0.34)
            gbeam(barrels, (*c, z), (*d, z), 0.06, 0.06)                                   # barrel
            gbox(barrels, (d[0], d[1], z), (0.10, 0.04, 0.12))                            # base clevis
    for t in ADJ_CYL_T:                                                                    # cylinder cross channels, side stringer to side stringer
        a, b = along(base, t, top - ADJ_DEPTH - 0.36), along(base, t, top - ADJ_DEPTH - 0.36)
        gbox(barrels, (a[0], a[1] - 0.01, 0.0), (0.12, 0.08, 5.2))
    obj("PocketAdjusterCylinders", barrels, coll, [M["grey"]], bevel=0.003, segs=1)
    root = obj("PocketAdjusters", plates, coll, [M["uhmw"]], bevel=0.003)
    r = obj("PocketAdjusterRods", rods, coll, [M["shaft"]], bevel=0.0)
    r.parent = root
    return root


def ibeam_line(bm, p0, p1, z, h=0.25, w=0.12):
    """Sloped wide-flange beam in the XY plane at z (web vertical)."""
    gbeam(bm, (p0[0], p0[1], z), (p1[0], p1[1], z), w, 0.014)
    a = Vector(p0) + Vector((0, -h))
    b = Vector(p1) + Vector((0, -h))
    gbeam(bm, (a.x, a.y, z), (b.x, b.y, z), w, 0.014)
    for k in range(9):
        t = k / 8
        q = Vector(p0).lerp(Vector(p1), t)
        gbox(bm, (q.x, q.y - h / 2, z), (0.012, h, 0.012))
    gbeam(bm, (p0[0], p0[1] - h / 2, z), (p1[0], p1[1] - h / 2, z), 0.010, h)


# ---------------------------------------------------------------- stacker infeed

def build_infeed(coll, M):
    bm, bmd, bmu, bmy = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    top = INFEED_TOP
    beam_top = FRAME_BEAM_TOP
    for x in (25.55, 26.95, 29.05):                                   # columns carry the side beams
        for z in (-FRAME_Z, FRAME_Z):
            ibeam(bm, 'y', (x, beam_top / 2, z), beam_top, h=0.2, w=0.2)
    for x in INF_CROSS_X:                                             # cross beams hung under the side beams
        ibeam(bm, 'z', (x, INF_BEAM_TOP - 0.1, 0.0), 2 * FRAME_Z + 0.2, h=0.2, w=0.15)   # top meets the side beams' underside
    for z in (-FRAME_Z, FRAME_Z):
        ibeam(bm, 'x', (27.4, beam_top - 0.1, z), 4.1, h=0.2, w=0.15)
    # Chain ways: a box per strand on the cross beams. The carrying run slides on the UHMW strip
    # on top; the return run rides inside on the lower strip.
    ret_pin = INF_SHAFT_Y - INF_SPR
    w0, w1 = INF_TAIL + INF_SPR + 0.05, 29.0
    for z in INF_Z:
        for side in (-1, 1):
            gbox_span(bm, (w0, INF_BEAM_TOP, z + side * 0.045), (w1, INF_PIN_Y - CHAIN_ROLLER_R - 0.012, z + side * 0.055))
        gbox_span(bm, (w0, INF_BEAM_TOP, z - 0.045), (w1, INF_BEAM_TOP + 0.02, z + 0.045))
        gbox_span(bmu, (w0, INF_PIN_Y - CHAIN_ROLLER_R - 0.012, z - 0.055), (w1, INF_PIN_Y - CHAIN_ROLLER_R, z + 0.055))
        gbox_span(bmu, (w0, INF_BEAM_TOP + 0.02, z - 0.045), (w1, ret_pin - CHAIN_ROLLER_R, z + 0.045))
    # Dead plate from the unscrambler head to the infeed chains, slotted for the unscrambler lugs
    # and the infeed tail sprockets.
    holes = [(25.0, 25.62, z - 0.05, z + 0.05) for z in UNS_Z] + [(INF_TAIL - 0.2, INF_TAIL + 0.2, z - 0.04, z + 0.04) for z in INF_Z]
    S.slotted_plate(bmd, UNS_HEAD.x + 0.015, INF_TAIL + 0.02, -2.45, 2.45, top - 0.012, top - 0.004, holes)
    # Tail stub sprockets: a short stub shaft per strand in two bearings hanging from the plate.
    for z in INF_Z:
        for side in (-1, 1):
            gbox_span(bmy, (INF_TAIL - 0.035, INF_SHAFT_Y - 0.04, z + side * 0.05 - 0.012), (INF_TAIL + 0.035, top - 0.012, z + side * 0.05 + 0.012))
    # Line-up fence on the -Z side with a flared lead-in, on brackets off the side beam.
    gbox_span(bmd, (25.75, top - 0.03, LINEUP_FENCE_Z - 0.012), (LAYER_STOP_X, top + 0.20, LINEUP_FENCE_Z))
    gbeam(bmd, (FLARE_X0, top + 0.085, LINEUP_FENCE_Z - FLARE_OUT), (25.75, top + 0.085, LINEUP_FENCE_Z - 0.006), 0.012, 0.23)
    # Fence posts stand on the side beam's inboard flange, clear of the fork trolley's path
    # (x 27.3 - 29.05) and the trolley cylinder on the beam centreline.
    gbox_span(bmd, (LAYER_STOP_X, top - 0.03, LINEUP_FENCE_Z - 0.012), (FENCE_POST_X[-1] + 0.03, top + 0.20, LINEUP_FENCE_Z))
    for x in FENCE_POST_X:
        gbox_span(bm, (x - 0.03, beam_top, -FRAME_Z + 0.06), (x + 0.03, top + 0.18, -FRAME_Z + 0.12))
        gbox_span(bm, (x - 0.03, top + 0.12, -FRAME_Z + 0.06), (x + 0.03, top + 0.18, LINEUP_FENCE_Z - 0.012))
    # Line-up drums: a pillow-block bearing at each end on a pedestal off a cross beam, and a
    # shaft-mounted gear reducer with its motor hanging below on the downstream end.
    axle_y = INFEED_TOP - ROLL_R
    for z in ROLL_Z:
        for x in ROLL_BEARING_X:
            gbox_span(bm, (x - 0.06, INF_BEAM_TOP, z - 0.09), (x + 0.06, axle_y - 0.075, z + 0.09))
            gbox_span(bmy, (x - 0.05, axle_y - 0.075, z - 0.08), (x + 0.05, axle_y - 0.05, z + 0.08))         # base
            gcyl(bmy, (x, axle_y, z), 0.045, 0.07, 'x', segs=16)                                                # housing
            for dz in (-0.055, 0.055):
                gcyl(bmy, (x, axle_y - 0.06, z + dz), 0.01, 0.04, 'y', segs=6)                                  # bolts
        rx = ROLL_BEARING_X[1] + 0.13
        gbox(bmy, (rx, axle_y, z), (0.12, 0.15, 0.14))
        gcyl(bmy, (rx, axle_y - 0.21, z), 0.055, 0.27, 'y', segs=16)
        gbox_span(bmy, (rx - 0.07, INF_BEAM_TOP, z - 0.012), (rx - 0.05, axle_y - 0.05, z + 0.012))              # torque arm
    # Head bearings on pedestals off the head cross beam, and the head drive.
    for z in (-2.6, 2.6):
        pillow(bmy, INF_HEAD, INF_SHAFT_Y, z, 0.6)
        gbox_span(bm, (INF_HEAD - 0.08, INF_BEAM_TOP, z - 0.05), (INF_HEAD + 0.08, INF_SHAFT_Y - 0.05, z + 0.05))
    gbox(bmy, (INF_HEAD, INF_SHAFT_Y, -2.85), (0.32, 0.36, 0.26))
    gcyl(bmy, (INF_HEAD + 0.25, INF_SHAFT_Y, -2.85), 0.11, 0.35, 'x', segs=20)
    obj("InfeedFrame", bm, coll, [M["green"]], bevel=0.004)
    obj("InfeedPlates", bmd, coll, [M["deck"]], bevel=0.002, segs=1)
    obj("InfeedWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)
    obj("InfeedDrive", bmy, coll, [M["grey"]], bevel=0.003, segs=1)
    # Head shaft sits low enough that the extended forks pass over it.
    head = shaft(coll, M, "InfeedHeadShaft", INF_HEAD, INF_SHAFT_Y, INF_Z, INF_SPR, INF_TEETH, CHAIN_ROLLER_R, 5.3,
                 shaft_r=0.04, hub_r=0.08)
    bm = bmesh.new()
    for z in INF_Z:
        S.sprocket_ring(bm, INF_TEETH, INF_SPR, CHAIN_ROLLER_R, 0.03, z, 0.035, mi=1)
        gcyl(bm, (0, 0, z), 0.035, 0.09, 'z', mi=0, segs=12)
        gcyl(bm, (0, 0, z), 0.02, 0.124, 'z', mi=0, segs=10)                  # stub shaft into the bearings
    tail = obj("InfeedTailSprockets", bm, coll, [M["shaft"], M["chain"]], bevel=0.0, loc=(INF_TAIL, INF_SHAFT_Y, 0))
    return [head, tail]


def build_pop_stops(coll, M, name, x_face, zs=None):
    """Pop-up stop fingers (moving part, shown raised; they drop STOP_DROP). Each short finger
    is lifted by a small air cylinder just upstream of it, through a lug on the rod end; the
    cylinder hangs from a bracket bolted to the side of the nearest chain way. No cross shaft
    (it would pass through the chain ways) and nothing below 2.45 m (the frame cross beam at
    the head end)."""
    top = INFEED_TOP
    cx = x_face - 0.055
    bm, bmg = bmesh.new(), bmesh.new()
    for z in (STOP_Z if zs is None else zs):
        gbox_span(bm, (x_face, top - 0.02, z - 0.025), (x_face + 0.035, top + STOP_RISE, z + 0.025))          # finger
        gbox_span(bm, (cx - 0.02, top - 0.02, z - 0.02), (x_face, top + 0.01, z + 0.02))                       # rod-end lug
        gcyl(bm, (cx, top - 0.10, z), 0.01, 0.16, 'y', segs=8)                                                  # rod
        gcyl(bmg, (cx, top - 0.23, z), 0.022, 0.14, 'y', segs=12)                                               # barrel
        way = min(INF_Z, key=lambda c: abs(c - z))
        toward = math.copysign(1.0, way - z)
        za, zb = z + toward * 0.022, way - toward * 0.055                  # to the way's side plate
        gbox_span(bmg, (cx - 0.03, top - 0.20, z - 0.03), (cx + 0.03, top - 0.16, z + 0.03))                    # clamp on the barrel
        gbox_span(bmg, (cx - 0.03, top - 0.19, min(za, zb)), (cx + 0.03, top - 0.15, max(za, zb)))              # bracket up under the way
    obj(name + "Guides", bmg, coll, [M["grey"]], bevel=0.002, segs=1)
    return obj(name, bm, coll, [M["orange"]], bevel=0.003)


STOP_Z = (-1.31, -0.26, 0.26, 1.31)             # between the chain ways and the forks
# Layer stop fingers: each one between a chain way and the next fork tine out, so every board from
# 6 ft up, even-ended at either fence, bears on two fingers either side of its chain strand.
LAYER_STOP_Z = (-1.84, -0.79, 0.79, 1.84)
STOP_RISE = 0.12
STOP_DROP = 0.13                                # down: finger top 1 cm under the chain tops
HOLD_STOP_X = 27.33                             # course divider face: keeps the next layer off the forks

# ---------------------------------------------------------------- overhead course divider
DIV_X = HOLD_STOP_X                             # upstream face of the fingers
DIV_FINGER_D = 0.035                            # finger thickness along X
DIV_DOWN = 0.03                                 # down: tips this far under the chain tops, between the strands
DIV_TIP_Y = INFEED_TOP - DIV_DOWN
DIV_FINGER_H = 0.21
DIV_POST_X = 27.15                              # gantry posts on the side beams, upstream of the fork trolleys
DIV_BEAM_Y = (3.25, 3.45)
DIV_BARREL_Y = (2.98, 3.25)

# ---------------------------------------------------------------- holdover rack
# Arms off the +Z catwalk's outer rail: the catwalk worker lays a layer that can't be
# completed here instead of letting it be stacked.
RACK_ARM_X = (25.9, 27.6, 29.3)
RACK_Y = FRAME_BEAM_TOP + 0.80                    # arm tops, a little under the top rail (walkway is at FRAME_BEAM_TOP)
RACK_Z = (3.97, 4.42)
RACK_PIN_H = 0.30


def build_course_divider(coll, M):
    """Overhead course divider: a gantry over the infeed at the hold line, with an air cylinder
    over each finger. Fingers hang between the chain strands. In the gauge position their tips
    sit one and a half boards over the chains, so a single board passes under and a board
    riding on another is held back; in the divide position they drop into the gap behind the
    last board of a layer and hold the rest. Modelled down; the game lifts them."""
    frame, moving, rods = bmesh.new(), bmesh.new(), bmesh.new()
    cx = DIV_X + DIV_FINGER_D / 2
    for z in (-FRAME_Z, FRAME_Z):
        gbox_span(frame, (DIV_POST_X - 0.05, FRAME_BEAM_TOP, z - 0.05), (DIV_POST_X + 0.05, DIV_BEAM_Y[0], z + 0.05))
        gbox_span(frame, (DIV_POST_X - 0.09, FRAME_BEAM_TOP, z - 0.09), (DIV_POST_X + 0.09, FRAME_BEAM_TOP + 0.015, z + 0.09))   # base plate
        gbeam(frame, (DIV_POST_X, DIV_BEAM_Y[0] - 0.25, z), (DIV_POST_X + 0.2, DIV_BEAM_Y[0], z), 0.04, 0.04)               # knee brace
    gbox_span(frame, (DIV_POST_X - 0.06, DIV_BEAM_Y[0], -FRAME_Z - 0.08), (cx + 0.08, DIV_BEAM_Y[1], FRAME_Z + 0.08))         # box beam
    for z in STOP_Z:
        gbox_span(frame, (cx - 0.05, DIV_BARREL_Y[1] - 0.012, z - 0.05), (cx + 0.05, DIV_BARREL_Y[1], z + 0.05))             # mounting flange
        gcyl(frame, (cx, (DIV_BARREL_Y[0] + DIV_BARREL_Y[1]) / 2, z), 0.032, DIV_BARREL_Y[1] - DIV_BARREL_Y[0], 'y', segs=16)
        gcyl(frame, (cx, DIV_BARREL_Y[0] + 0.01, z), 0.036, 0.02, 'y', segs=16)                                                 # rod gland
        # Finger: a flat plate, square-faced on the upstream side, with a rod clevis on top.
        tip = DIV_TIP_Y
        gbox_span(moving, (DIV_X, tip, z - 0.025), (DIV_X + DIV_FINGER_D, tip + DIV_FINGER_H, z + 0.025))
        gbox_span(moving, (DIV_X + 0.005, tip + DIV_FINGER_H, z - 0.018), (DIV_X + DIV_FINGER_D - 0.005, tip + DIV_FINGER_H + 0.04, z + 0.018))
        gcyl(rods, (cx, (tip + DIV_FINGER_H + 0.04 + DIV_BARREL_Y[0] + 0.12) / 2, z), 0.013,
             DIV_BARREL_Y[0] + 0.12 - (tip + DIV_FINGER_H + 0.04), 'y', segs=10)
    obj("CourseDividerFrame", frame, coll, [M["green"]], bevel=0.003, segs=1)
    root = obj("CourseDivider", moving, coll, [M["orange"]], bevel=0.003)
    r = obj("CourseDividerRods", rods, coll, [M["shaft"]], bevel=0.0)
    r.parent = root
    return root


def build_holdover_rack(coll, M):
    """Three arms bolted to the +Z catwalk's outer rail posts, each with a pin at both ends, for
    a short layer the catwalk worker takes off the line (two boards across, about eight high).
    The game gives the arms and pins the same collision (green_stacker.gd)."""
    bm = bmesh.new()
    for x in RACK_ARM_X:
        gbox_span(bm, (x - 0.03, FRAME_BEAM_TOP, RACK_Z[0] - 0.03), (x + 0.03, RACK_Y, RACK_Z[0] + 0.01))                 # upright on the rail line
        gbox_span(bm, (x - 0.03, RACK_Y - 0.06, RACK_Z[0]), (x + 0.03, RACK_Y, RACK_Z[1]))                         # arm
        for z0 in (RACK_Z[0], RACK_Z[1] - 0.03):
            gbox_span(bm, (x - 0.02, RACK_Y, z0), (x + 0.02, RACK_Y + RACK_PIN_H, z0 + 0.03))                     # end pins
        gbeam(bm, (x, FRAME_BEAM_TOP + 0.25, RACK_Z[0]), (x, RACK_Y - 0.06, RACK_Z[1] - 0.05), 0.03, 0.03)                 # brace
    return obj("HoldoverRack", bm, coll, [M["yellow"]], bevel=0.003, segs=1)


def build_roll(coll, M):
    """Line-up drum: steel shell with end discs, shaft through to both bearings and out to the
    reducer on the downstream end. Origin on the axis at the drum's middle (spun about X)."""
    bm = bmesh.new()
    gcyl(bm, (0, 0, 0), ROLL_R, ROLL_LEN, 'x', mi=0, segs=28)
    for e in (-1, 1):
        gcyl(bm, (e * (ROLL_LEN / 2 - 0.004), 0, 0), ROLL_R + 0.003, 0.008, 'x', mi=0, segs=28)
    xa, xb = ROLL_BEARING_X[0] - 0.05, ROLL_BEARING_X[1] + 0.13
    mid = (ROLL_X0 + ROLL_X1) / 2
    gcyl(bm, ((xa + xb) / 2 - mid, 0, 0), 0.03, xb - xa, 'x', mi=1, segs=12)
    return obj("LineupRoll", bm, coll, [M["drum"], M["shaft"]], bevel=0.003, segs=1)


# ---------------------------------------------------------------- far-end ending rolls and fence
# The line-up rolls even-end every board at the -Z fence. A package of mixed lengths built
# that way has all its short boards at the -Z end and holes all along the +Z face, so every
# other layer is even-ended at the +Z end instead: a fence at the 16 ft board's far end, and
# pop-up drum rolls between the forming chains that rise under the gathered layer and drive
# it endwise (+Z) against that fence, then drop back under the chains before the forks lift it.
FAR_FENCE_Z = LINEUP_FENCE_Z + 16 * 0.3048 + 0.005
END_Z = (-2.32, -1.31, -0.26, 0.26, 1.31, 2.32)     # between the chain ways and the fork tines
END_X0 = 27.45                                       # just downstream of the course divider fingers
END_X1 = 28.98
END_TOP = INFEED_TOP + 0.018                         # raised drum tops: boards lifted clear of the chains
END_DROP = 0.05                                      # lowered: tops 3.2 cm under the chain tops
END_AXLE_Y = END_TOP - ROLL_R
END_CH_Y = END_AXLE_Y - 0.075                        # lift channel top (the bearing bases sit on it)
END_CYL_X = (26.95, 29.05)                           # upstream / downstream cylinders, on the cross beams
END_BARREL_TOP = END_CH_Y - 0.045 - END_DROP - 0.012  # just under the lowered channel
END_POST_X = (27.0, 29.12)
# Short packs (12 ft and under) are even-ended at the 12 ft mark instead of the 16 ft fence: a
# pop-up gate plate between the +Z fork tine and the ending drums, its face 12 ft from the line-up
# fence, raised only while a short layer is driven endwise. It lifts on two air cylinders hung on
# brackets under the +Z chain way, inside the forks' sweep only where the fork cross tube passes
# well below.
GATE_Z = LINEUP_FENCE_Z + 12 * 0.3048 + 0.005
GATE_X = (27.40, 29.00)
GATE_TOP = INFEED_TOP + 0.10                         # raised (home): over a layer the drums have lifted
GATE_H = 0.25
GATE_DROP = 0.16                                     # lowered: top 6 cm under the chain tops
GATE_CYL_X = (27.70, 28.65)
GATE_BRACKET_Y = 2.05
# Short-board idler rails: a 6 ft board even-ended at either fence has its middle over a single
# chain strand (+-1.575) and would seesaw on it, so a rail of small free-spinning idler rollers
# (axles across the line) between the outer fork tine and the outer ending drum carries its short
# end. The rollers turn as the board rides over them, so they don't drag that end and skew it. The
# rail lies in the pocket the fork risers and trolley guides sweep, so it spans from cross beam to
# cross beam, clear of the line-up drum pedestals.
SKID_Z = 2.21
SKID_HALF = 0.017
SKID_X = (26.99, 29.10)
SKID_TOP = INFEED_TOP - 0.002                   # roller tops, level with the chain tops
IDLER_R, IDLER_PITCH = 0.0125, 0.08
# The surge chains have the same gap: an idler rail on each side guide (z +-2.25), from the tail
# to short of the pack stop.
SURGE_SKID_Z = 2.25
SURGE_SKID_X = (SURGE_TAIL + SURGE_SPR + 0.08, SURGE_STOP_X - 0.05)
SURGE_SKID_TOP = SURGE_TOP - 0.002


def idler_rail(bm, bmr, x0, x1, z, base_y, top):
    """Channel from base_y up past the roller axles, and a row of idler rollers on axles across
    the line (along Z), their tops at `top`."""
    axle = top - IDLER_R
    gbox_span(bm, (x0, base_y, z - SKID_HALF), (x1, axle - 0.02, z + SKID_HALF))                          # web
    for side in (-1, 1):
        gbox_span(bm, (x0, axle - 0.02, z + side * SKID_HALF - 0.003), (x1, axle + 0.004, z + side * SKID_HALF))   # cheeks
    n = int((x1 - x0 - 0.04) / IDLER_PITCH)
    for k in range(n + 1):
        x = x0 + 0.02 + k * IDLER_PITCH
        gcyl(bmr, (x, axle, z), IDLER_R, 2 * SKID_HALF - 0.008, 'z', segs=12)
        gcyl(bmr, (x, axle, z), 0.004, 2 * SKID_HALF, 'z', segs=6)


def build_far_fence(coll, M):
    """Static: the far-end fence with its flared lead-in and posts off the +Z side beam, and the
    barrels of the ending-roll lift cylinders, standing on the infeed cross beams."""
    bm, bmd, bmg = bmesh.new(), bmesh.new(), bmesh.new()
    top = INFEED_TOP
    z = FAR_FENCE_Z
    gbox_span(bmd, (END_POST_X[0] - 0.05, top - 0.03, z), (END_POST_X[1] + 0.03, top + 0.20, z + 0.012))
    gbeam(bmd, (END_POST_X[0] - 0.25, top + 0.085, z + 0.25), (END_POST_X[0] - 0.05, top + 0.085, z + 0.006), 0.012, 0.23)
    for x in END_POST_X:
        gbox_span(bm, (x - 0.03, FRAME_BEAM_TOP, FRAME_Z - 0.12), (x + 0.03, top + 0.18, FRAME_Z - 0.06))
        gbox_span(bm, (x - 0.03, top + 0.12, z + 0.012), (x + 0.03, top + 0.18, FRAME_Z - 0.06))
    for z in END_Z:
        for x in END_CYL_X:
            y0 = INF_BEAM_TOP
            gbox_span(bmg, (x - 0.05, y0, z - 0.05), (x + 0.05, y0 + 0.012, z + 0.05))                  # base plate
            gcyl(bmg, (x, (y0 + END_BARREL_TOP) / 2, z), 0.028, END_BARREL_TOP - y0, 'y', segs=14)
            gcyl(bmg, (x, END_BARREL_TOP - 0.007, z), 0.032, 0.014, 'y', segs=14)                       # gland
    # 12 ft gate cylinders: a strap down from the +Z inner chain way and a bracket under the drum
    # lift channel out to the gate line, a barrel standing on it.
    way = INF_Z[-1] - 0.055
    for x in GATE_CYL_X:
        gbox_span(bm, (x - 0.03, GATE_BRACKET_Y, way - 0.012), (x + 0.03, INF_BEAM_TOP, way))
        gbox_span(bm, (x - 0.03, GATE_BRACKET_Y - 0.04, GATE_Z - 0.035), (x + 0.03, GATE_BRACKET_Y, way))
        gcyl(bmg, (x, GATE_BRACKET_Y + 0.085, GATE_Z + 0.006), 0.026, 0.17, 'y', segs=14)
        gcyl(bmg, (x, GATE_BRACKET_Y + 0.17, GATE_Z + 0.006), 0.03, 0.012, 'y', segs=14)                  # gland
    bmu = bmesh.new()
    for s in (-1, 1):
        idler_rail(bm, bmu, SKID_X[0], SKID_X[1], s * SKID_Z, INF_BEAM_TOP, SKID_TOP)
        idler_rail(bm, bmu, SURGE_SKID_X[0], SURGE_SKID_X[1], s * SURGE_SKID_Z, 0.25, SURGE_SKID_TOP)   # on the side guide
    obj("ShortBoardSkids", bmu, coll, [M["shaft"]], bevel=0.0)
    obj("FarFencePosts", bm, coll, [M["green"]], bevel=0.003, segs=1)
    obj("FarFenceCylinders", bmg, coll, [M["grey"]], bevel=0.002, segs=1)
    return obj("FarFence", bmd, coll, [M["deck"]], bevel=0.002, segs=1)


def build_ending_lift(coll, M):
    """Moving part, shown raised: under each ending drum a lift channel carrying the drum's two
    pillow-block bearings, on two air cylinder rods. The drums are drum motors (the motor is
    inside the shell), so the only drive gear is a terminal box and cable on each one."""
    bm, bmy, rods = bmesh.new(), bmesh.new(), bmesh.new()
    for z in END_Z:
        x1 = END_X1
        cyl = END_CYL_X
        gbox_span(bm, (cyl[0] - 0.04, END_CH_Y - 0.045, z - 0.04), (cyl[1] + 0.04, END_CH_Y, z + 0.04))
        for x in (END_X0 - 0.04, x1 + 0.035):
            gbox_span(bmy, (x - 0.04, END_CH_Y, z - 0.07), (x + 0.04, END_AXLE_Y - 0.05, z + 0.07))   # base
            gcyl(bmy, (x, END_AXLE_Y, z), 0.045, 0.06, 'x', segs=16)                                    # housing
            for dz in (-0.05, 0.05):
                gcyl(bmy, (x, END_AXLE_Y - 0.06, z + dz), 0.009, 0.03, 'y', segs=6)                     # bolts
        gbox(bmy, (END_X0 - 0.04, END_AXLE_Y - 0.08, z + 0.055), (0.05, 0.04, 0.03))                     # terminal box
        lo = END_BARREL_TOP - 0.03                        # rod end, inside the barrel
        for x in cyl:
            gcyl(rods, (x, (lo + END_CH_Y - 0.045) / 2, z), 0.012, END_CH_Y - 0.045 - lo, 'y', segs=10)
    root = obj("EndingLift", bm, coll, [M["orange"]], bevel=0.003)
    gear = obj("EndingLiftBearings", bmy, coll, [M["grey"]], bevel=0.002, segs=1)
    gear.parent = root
    r = obj("EndingLiftRods", rods, coll, [M["shaft"]], bevel=0.0)
    r.parent = root
    return root


def build_ending_gate(coll, M):
    """Moving part, shown raised: the 12 ft gate plate (its -Z face is the fence face) with a
    stiffening flange along the bottom and the two cylinder rods hanging from it."""
    bm, rods = bmesh.new(), bmesh.new()
    x0, x1 = GATE_X
    gbox_span(bm, (x0, GATE_TOP - GATE_H, GATE_Z), (x1, GATE_TOP, GATE_Z + 0.012))
    gbox_span(bm, (x0, GATE_TOP - GATE_H, GATE_Z + 0.012), (x1, GATE_TOP - GATE_H + 0.012, GATE_Z + 0.05))
    for x in GATE_CYL_X:
        lo = GATE_BRACKET_Y + 0.165                    # inside the barrel, also when lowered
        hi = GATE_TOP - GATE_H
        gcyl(rods, (x, (lo + hi) / 2, GATE_Z + 0.006), 0.011, hi - lo, 'y', segs=10)
    root = obj("EndingGate", bm, coll, [M["orange"]], bevel=0.002, segs=1)
    r = obj("EndingGateRods", rods, coll, [M["shaft"]], bevel=0.0)
    r.parent = root
    return root


def build_ending_rolls(coll, M):
    """Ending drum: shell, end discs and the stub shafts into the bearings. Origin on the axis
    at the drum's middle (spun about X)."""
    out = []
    for name, x1 in (("EndingRoll", END_X1),):
        bm = bmesh.new()
        length = x1 - END_X0
        gcyl(bm, (0, 0, 0), ROLL_R, length, 'x', mi=0, segs=28)
        for e in (-1, 1):
            gcyl(bm, (e * (length / 2 - 0.004), 0, 0), ROLL_R + 0.003, 0.008, 'x', mi=0, segs=28)
            gcyl(bm, (e * (length / 2 + 0.03), 0, 0), 0.03, 0.06, 'x', mi=1, segs=12)
        for k in range(6):                                 # weld beads, so the spin shows
            a = k * math.pi / 3
            gbox(bm, (0, math.sin(a) * ROLL_R, math.cos(a) * ROLL_R), (length - 0.02, 0.006, 0.006), mi=1)
        out.append(obj(name, bm, coll, [M["drum"], M["shaft"]], bevel=0.002, segs=1))
    return out


# ---------------------------------------------------------------- forks, fence, sticks, hoist

TROLLEY_X = FORK_X0 + 0.03                     # trolley centre at home, over the fork cross tube
GUIDE_Z = FRAME_Z - 0.13                        # lift guides hang inboard of the side beams


def build_forks(coll, M):
    """Fork frame at home (moves along X with the trolleys and lifts FORK_LIFT in their
    guides): tines between the infeed chains, risers down to a cross tube whose ends ride
    in the trolley lift guides."""
    bm, bmu = bmesh.new(), bmesh.new()
    for z in FORK_Z:
        gbox_span(bm, (FORK_X0, FORK_HOME_TOP - FORK_T, z - 0.03), (FORK_X0 + FORK_LEN, FORK_HOME_TOP - 0.006, z + 0.03))
        gbox_span(bmu, (FORK_X0 + 0.05, FORK_HOME_TOP - 0.006, z - 0.03), (FORK_X0 + FORK_LEN, FORK_HOME_TOP, z + 0.03))
        gbox_span(bm, (FORK_X0, FORK_TUBE_Y, z - 0.03), (FORK_X0 + 0.06, FORK_HOME_TOP - FORK_T, z + 0.03))
    gcyl(bm, (TROLLEY_X, FORK_TUBE_Y, 0.0), 0.045, 2 * GUIDE_Z - 0.04, 'z', segs=16)
    for z in (-GUIDE_Z, GUIDE_Z):                                   # guide shoes on the tube ends
        gbox(bm, (TROLLEY_X, FORK_TUBE_Y, z - math.copysign(0.03, z)), (0.12, 0.14, 0.04))
    return obj("Forks", bm, coll, [M["orange"]], bevel=0.003), obj("ForkWear", bmu, coll, [M["uhmw"]], bevel=0.0)


def build_fork_trolley(coll, M):
    """Fork trolleys at home (move along X only): a wheeled box on each side beam's rail,
    a lift guide hanging inboard down past the beam to the fork cross tube, a short lift
    cylinder in the guide, and the carriage cylinder's rod running back into its barrel."""
    bm, bmg = bmesh.new(), bmesh.new()
    for z in (-FRAME_Z, FRAME_Z):
        inward = -math.copysign(1.0, z)
        gbox_span(bm, (TROLLEY_X - TROLLEY_HALF, TROLLEY_Y0 + 0.03, z - 0.09), (TROLLEY_X + TROLLEY_HALF, TROLLEY_Y0 + 0.16, z + 0.09))
        for dx in (-0.06, 0.06):                                    # wheels on the rail
            gcyl(bmg, (TROLLEY_X + dx, TROLLEY_Y0 + 0.03, z), 0.03, 0.05, 'z', segs=14)
        gz = z + inward * 0.13                                      # lift guide channel
        gbox_span(bm, (TROLLEY_X - 0.08, FORK_TUBE_Y - 0.12, gz - 0.01), (TROLLEY_X + 0.08, TROLLEY_Y0 + 0.16, gz + 0.01))
        gbox_span(bm, (TROLLEY_X - 0.08, TROLLEY_Y0 + 0.10, min(gz, z) - 0.01), (TROLLEY_X + 0.08, TROLLEY_Y0 + 0.16, max(gz, z) + 0.01))
        gcyl(bmg, (TROLLEY_X + 0.11, FORK_TUBE_Y + 0.16, gz), 0.025, 0.26, 'y', segs=12)   # lift cylinder
        grod(bmg, (TROLLEY_X - TROLLEY_HALF - FORK_STROKE - 0.12, TROLLEY_Y0 + 0.08, z),
             (TROLLEY_X - TROLLEY_HALF, TROLLEY_Y0 + 0.08, z), 0.022, segs=12)                 # cylinder rod
    obj("ForkTrolley", bm, coll, [M["orange"]], bevel=0.003)
    return obj("ForkTrolleyGear", bmg, coll, [M["shaft"]], bevel=0.002, segs=1)


def build_fork_drive(coll, M):
    """Static: a rail on top of each side beam, and the carriage cylinder barrel on the beam
    behind the trolley, anchored to a clevis at the infeed end."""
    bm, bmr = bmesh.new(), bmesh.new()
    x_rod_end = TROLLEY_X - TROLLEY_HALF - FORK_STROKE - 0.12      # rod end at home
    for z in (-FRAME_Z, FRAME_Z):
        gbox_span(bmr, (TROLLEY_X - TROLLEY_HALF - 0.05, FRAME_BEAM_TOP, z - 0.012), (29.05, TROLLEY_Y0, z + 0.012))
        gcyl(bm, ((x_rod_end - 0.05 + TROLLEY_X - TROLLEY_HALF - 0.08) / 2, TROLLEY_Y0 + 0.08, z), 0.05,
             TROLLEY_X - TROLLEY_HALF - 0.08 - (x_rod_end - 0.05), 'x', segs=16)
        gbox_span(bm, (x_rod_end - 0.15, FRAME_BEAM_TOP, z - 0.06), (x_rod_end - 0.05, TROLLEY_Y0 + 0.14, z + 0.06))   # clevis
        gbox_span(bm, (26.9, FRAME_BEAM_TOP, z - 0.06), (27.0, TROLLEY_Y0 + 0.04, z + 0.06))                          # saddle
    obj("ForkRails", bmr, coll, [M["shaft"]], bevel=0.001, segs=1)
    return obj("ForkDrive", bm, coll, [M["grey"]], bevel=0.003, segs=1)


def build_stick_frame(coll, M):
    bm, bmd = bmesh.new(), bmesh.new()
    top = MAG_TOP + 0.25
    for x in STICK_FRAME_X:
        for z in (-STICK_FRAME_Z, STICK_FRAME_Z):
            ibeam(bm, 'y', (x, top / 2, z), top, h=0.2, w=0.2)
        ibeam(bm, 'z', (x, top - 0.1, 0.0), 2 * STICK_FRAME_Z + 0.2, h=0.2, w=0.15)
    for z in (-STICK_FRAME_Z, STICK_FRAME_Z):
        ibeam(bm, 'x', ((STICK_FRAME_X[0] + STICK_FRAME_X[1]) / 2, top - 0.1, z), STICK_FRAME_X[1] - STICK_FRAME_X[0], h=0.2, w=0.15)
    # Magazine hanger beams across the frame, at the magazine ends.
    for x in (STICK_X0 + 0.10, STICK_X0 + STICK_LEN - 0.10):
        gbox(bm, (x, MAG_TOP + 0.05, 0.0), (0.1, 0.1, 2 * STICK_FRAME_Z))
        for z in (-STICK_FRAME_Z + 0.05, STICK_FRAME_Z - 0.05):
            gbox_span(bm, (x - 0.05, MAG_TOP, z - 0.05), (x + 0.05, top - 0.2, z + 0.05))
    # Magazines: an open hopper per stick line, so the stacked sticks show: four corner
    # angles, a top band, side guide bars, and end stops; open bottom with release fingers
    # (the moving StickGates part).
    hz = STICK_W / 2 + 0.008
    for z in STICK_Z:
        for x in (STICK_X0 - 0.01, STICK_X0 + 0.45, STICK_X0 + STICK_LEN - 0.45, STICK_X0 + STICK_LEN + 0.01):
            for side in (-1, 1):
                gbox_span(bmd, (x - 0.02, MAG_BOTTOM, z + side * hz - 0.003), (x + 0.02, MAG_TOP + 0.05, z + side * hz + 0.003))
        for y in (MAG_BOTTOM + 0.12, MAG_TOP - 0.02):
            for side in (-1, 1):
                gbox_span(bmd, (STICK_X0 - 0.03, y - 0.02, z + side * hz - 0.003), (STICK_X0 + STICK_LEN + 0.03, y, z + side * hz + 0.003))
        for x in (STICK_X0 - 0.018, STICK_X0 + STICK_LEN + 0.018):
            gbox_span(bmd, (x - 0.004, MAG_BOTTOM, z - hz), (x + 0.004, MAG_TOP, z + hz))
        # Hangers from the magazine ends up to the hanger beams.
        for x in (STICK_X0 + 0.10, STICK_X0 + STICK_LEN - 0.10):
            gbox_span(bm, (x - 0.02, MAG_TOP, z - hz - 0.004), (x + 0.02, MAG_TOP + 0.03, z + hz + 0.004))
    # Stick placer cylinders: a barrel over each lift beam end, on a bracket off the side beams.
    for x in (STICK_X0 + 0.25, STICK_X0 + STICK_LEN - 0.25):
        for z in (-2.62, 2.62):
            gcyl(bm, (x, MAG_TOP + 0.20 + 0.20 + 0.16, z), 0.035, 0.32, 'y', segs=14)
            gbox_span(bm, (x - 0.05, MAG_TOP + 0.70, min(z, math.copysign(STICK_FRAME_Z, z))),
                      (x + 0.05, MAG_TOP + 0.74, max(z, math.copysign(STICK_FRAME_Z, z))))
            zb = math.copysign(STICK_FRAME_Z, z)
            gbox_span(bm, (x - 0.04, top, zb - 0.04), (x + 0.04, MAG_TOP + 0.74, zb + 0.04))   # post off the side beam
    # Pull-back fence cylinders hang from the upstream portal.
    for z in (-2.6, 2.6):
        gcyl(bm, (FENCE_X, 3.25, z), 0.05, 0.5, 'y', segs=16)
    obj("StickFrame", bm, coll, [M["green"]], bevel=0.004)
    obj("StickMagazines", bmd, coll, [M["galv"]], bevel=0.001, segs=1)


PLACER_X = (STICK_X0 + 0.25, STICK_X0 + STICK_LEN - 0.25)     # lift rod rows
PLACER_BEAM_Y = MAG_TOP + 0.20                                  # lift beams, above the magazines
PLACER_ROD_DZ = STICK_W / 2 + 0.008 + 0.018                     # rods just outside each magazine's sides
STICK_HOLD_Y = MAG_BOTTOM - STICK_T / 2 - 0.004                 # held stick's centre, at home


def build_stick_gates(coll, M):
    """Stick placer (moving part, shown at home): under every magazine a pair of jaws grips
    the bottom stick by its sides. The jaws hang on rods that run up beside the magazine to two
    lift beams above the magazines. Each cycle the placer travels down until the sticks sit on
    the layer just put out, the jaws open and it goes back up. Air cylinders on the frame
    (static, built with it) drive the lift beams."""
    bm, bmr = bmesh.new(), bmesh.new()
    jy = STICK_HOLD_Y
    for x in PLACER_X:
        gbox_span(bm, (x - 0.04, PLACER_BEAM_Y, -2.62), (x + 0.04, PLACER_BEAM_Y + 0.07, 2.62))      # lift beam
    for z in STICK_Z:
        for side in (-1, 1):
            zj = z + side * (STICK_W / 2 + 0.006)
            gbox_span(bm, (STICK_X0 + 0.05, jy - 0.008, zj - 0.004), (STICK_X0 + STICK_LEN - 0.05, jy + 0.008, zj + 0.004))  # jaw
            for x in PLACER_X:
                zr = z + side * PLACER_ROD_DZ
                grod(bmr, (x, jy, zr), (x, PLACER_BEAM_Y, zr), 0.007, segs=8)                                      # hanger rod
                gbox_span(bm, (x - 0.015, jy - 0.008, min(zj, zr) - 0.004), (x + 0.015, jy + 0.008, max(zj, zr) + 0.004))  # foot
    for x in PLACER_X:
        for z in (-2.62, 2.62):
            grod(bmr, (x, PLACER_BEAM_Y + 0.07, z), (x, PLACER_BEAM_Y + 0.20, z), 0.015, segs=10)                 # cylinder rod
    placer = obj("StickGates", bm, coll, [M["orange"]], bevel=0.002)
    obj("StickGateRods", bmr, coll, [M["shaft"]], bevel=0.0).parent = placer
    return placer


GUIDE_FRONT_X = STICK_X0 + STICK_LEN            # package front stops' face: the package's far side
GUIDE_FRONT_Z = (-1.95, -0.92, 0.26, 1.44, 2.03)  # clear of the stick lines, hoist arms and forks
GUIDE_END_Z = (LINEUP_FENCE_Z - 0.01, LINEUP_FENCE_Z + 4.877 + 0.01)   # board-end plates (16 ft)
GUIDE_BOTTOM = 2.30                              # over the top few layers only: a full package
                                                 # (top about 2.22 on the outfeed) runs out under them


def build_package_guides(coll, M):
    """Package squaring guides hanging from the stick frame, so no board can slide off the
    package while a layer drops onto it: front stop bars along the package's far side (the
    pull-back fence holds the near side) and end plates at both board ends, each flared at the
    bottom as a lead-in."""
    bm, bmy = bmesh.new(), bmesh.new()
    top = MAG_TOP - 0.05
    bx = GUIDE_FRONT_X + 0.12
    gbox_span(bm, (bx - 0.05, top - 0.10, -STICK_FRAME_Z), (bx + 0.05, top, STICK_FRAME_Z))      # hanger beam
    for z in (-STICK_FRAME_Z, STICK_FRAME_Z):
        gbox_span(bm, (bx - 0.05, top - 0.10, z - 0.05), (STICK_FRAME_X[1] - 0.1, top, z + 0.05))
    for z in GUIDE_FRONT_Z:
        gbox_span(bmy, (GUIDE_FRONT_X, GUIDE_BOTTOM + 0.08, z - 0.04), (GUIDE_FRONT_X + 0.05, top - 0.10, z + 0.04))
        gbeam(bmy, (GUIDE_FRONT_X + 0.025, GUIDE_BOTTOM + 0.08, z), (GUIDE_FRONT_X + 0.10, GUIDE_BOTTOM, z), 0.08, 0.05)
        gbox_span(bm, (GUIDE_FRONT_X + 0.05, top - 0.25, z - 0.03), (bx - 0.05, top - 0.10, z + 0.03))
    for i, z in enumerate(GUIDE_END_Z):
        s = -1 if i == 0 else 1
        za, zb = sorted((z, z + s * 0.012))
        gbox_span(bmy, (STICK_X0 + 0.05, GUIDE_BOTTOM + 0.08, za), (GUIDE_FRONT_X - 0.05, MAG_BOTTOM - 0.02, zb))
        gbeam(bmy, (STICK_X0 + 0.05, GUIDE_BOTTOM + 0.08, z + s * 0.006), (STICK_X0 + 0.05, GUIDE_BOTTOM, z + s * 0.07), 0.012, 0.012)
        for x in (STICK_X0 + 0.25, GUIDE_FRONT_X - 0.25):
            gbox_span(bm, (x - 0.03, MAG_BOTTOM - 0.02, min(z + s * 0.012, s * STICK_FRAME_Z)), (x + 0.03, top - 0.10, max(z + s * 0.012, s * STICK_FRAME_Z)))
        gbox_span(bmy, (STICK_X0 + 0.05, GUIDE_BOTTOM, min(z + s * 0.012, z + s * 0.07)), (GUIDE_FRONT_X - 0.05, GUIDE_BOTTOM + 0.08, max(z + s * 0.012, z + s * 0.07)))
    obj("PackageGuideHangers", bm, coll, [M["green"]], bevel=0.003)
    return obj("PackageGuides", bmy, coll, [M["orange"]], bevel=0.003)


def build_fence(coll, M):
    """Pull-back fence (shown down): bars between the forks off a cross beam."""
    bm = bmesh.new()
    gbox(bm, (FENCE_X, 3.0, 0.0), (0.08, 0.12, 5.3))
    for z in FENCE_Z:
        gbox_span(bm, (FENCE_X - 0.02, FENCE_DOWN, z - 0.03), (FENCE_X + 0.02, 3.0, z + 0.03))
    for z in (-2.6, 2.6):
        gcyl(bm, (FENCE_X, 3.05, z), 0.02, 0.4, 'y', segs=10)
    return obj("PullbackFence", bm, coll, [M["orange"]], bevel=0.003)


HOIST_CYL_X = (29.45, 30.30)
PIT_X0, PIT_X1, PIT_Z = 29.0, 30.75, 2.0
PIT_FLOOR = -2.55
HOIST_ROD_LEN = 2.6                             # stroke ~2.2 m plus engagement in the barrel


def build_hoist(coll, M):
    """Hoist arms at the top position (moving part): an arm between each pair of outfeed
    chains, each on two cylinder rods that slide into barrels standing in the hoist pit.
    The rods are long enough to stay engaged at the top of the stroke."""
    bm, bmr = bmesh.new(), bmesh.new()
    arm_bottom = HOIST_TOP - 0.10
    for z in HOIST_Z:
        gbox_span(bm, (HOIST_X0, arm_bottom, z - 0.04), (HOIST_X1, HOIST_TOP, z + 0.04))
        for x in HOIST_CYL_X:
            gbox(bm, (x, arm_bottom - 0.03, z), (0.14, 0.06, 0.14))                  # rod-end clevis
            gcyl(bmr, (x, arm_bottom - 0.06 - HOIST_ROD_LEN / 2, z), 0.04, HOIST_ROD_LEN, 'y', segs=14)
    hoist = obj("Hoist", bm, coll, [M["orange"]], bevel=0.003)
    rods = obj("HoistRods", bmr, coll, [M["shaft"]], bevel=0.0)
    rods.parent = hoist
    bm, bmc = bmesh.new(), bmesh.new()
    for z in HOIST_Z:
        for x in HOIST_CYL_X:
            gcyl(bm, (x, (PIT_FLOOR + 0.1 - 0.02) / 2, z), 0.065, -PIT_FLOOR - 0.12, 'y', segs=16)   # barrels
            gcyl(bm, (x, -0.03, z), 0.08, 0.06, 'y', segs=16)                                          # gland
            gbox(bm, (x, PIT_FLOOR + 0.05, z), (0.25, 0.1, 0.25))                                       # base
        gbox_span(bm, (HOIST_CYL_X[0], -0.32, z - 0.03), (HOIST_CYL_X[1], -0.26, z + 0.03))          # barrel tie
    # Pit: concrete walls and floor, a steel curb angle round the opening.
    t = 0.2
    for x0, x1, z0, z1 in ((PIT_X0 - t, PIT_X0, -PIT_Z - t, PIT_Z + t), (PIT_X1, PIT_X1 + t, -PIT_Z - t, PIT_Z + t),
                           (PIT_X0, PIT_X1, -PIT_Z - t, -PIT_Z), (PIT_X0, PIT_X1, PIT_Z, PIT_Z + t)):
        gbox_span(bmc, (x0, PIT_FLOOR, z0), (x1, 0.0, z1))
    gbox_span(bmc, (PIT_X0 - t, PIT_FLOOR - t, -PIT_Z - t), (PIT_X1 + t, PIT_FLOOR, PIT_Z + t))
    for x0, x1, z0, z1 in ((PIT_X0 - 0.06, PIT_X0, -PIT_Z - 0.06, PIT_Z + 0.06), (PIT_X1, PIT_X1 + 0.06, -PIT_Z - 0.06, PIT_Z + 0.06),
                           (PIT_X0, PIT_X1, -PIT_Z - 0.06, -PIT_Z), (PIT_X0, PIT_X1, PIT_Z, PIT_Z + 0.06)):
        gbox_span(bm, (x0, -0.06, z0), (x1, 0.006, z1))
    obj("HoistBase", bm, coll, [M["grey"]], bevel=0.002, segs=1)
    obj("HoistPit", bmc, coll, [M["concrete"]], bevel=0.0)
    return hoist


def floor_with_pit(coll, M):
    """Preview floor with the hoist pit opening (replaces the sorter preview's plain slab)."""
    old = bpy.data.objects.get("Floor")
    if old is not None:
        bpy.data.objects.remove(old)
    s = 60.0
    xs, zs = (-s, PIT_X0, PIT_X1, s), (-s, -PIT_Z, PIT_Z, s)
    bm = bmesh.new()
    for i in range(3):
        for j in range(3):
            if i == 1 and j == 1:
                continue
            gbox_span(bm, (xs[i], -0.001, zs[j]), (xs[i + 1], 0.0, zs[j + 1]))
    o = L.make_object("Floor", bm, coll, [M["concrete"]], weighted=False)
    o.data.polygons.foreach_set("use_smooth", [False] * len(o.data.polygons))


def build_outfeed(coll, M):
    bm, bmu = bmesh.new(), bmesh.new()
    c0, c1 = OUT_TAIL + OUT_SPR + 0.08, OUT_HEAD - OUT_SPR - 0.08
    drag_channels(bm, bmu, c0, c1, OUT_Z, OUT_TOP - CHAIN_PLATE_H - CHAIN_ROLLER_R, OUT_SHAFT_Y - OUT_SPR - CHAIN_ROLLER_R)
    for x in [c0 + k * 1.2 for k in range(int((c1 - c0) / 1.2) + 1)]:
        if not (HOIST_X0 - 0.1 < x < HOIST_X1 + 0.1):
            gbox_span(bm, (x - 0.05, 0.0, -2.3), (x + 0.05, 0.08, 2.3))
    for x in (OUT_TAIL, OUT_HEAD):
        for z in (-2.45, 2.45):
            pillow(bm, x, OUT_SHAFT_Y, z)
            gbox_span(bm, (x - 0.15, 0.0, z - 0.08), (x + 0.15, OUT_SHAFT_Y - 0.085, z + 0.08))
    hz = 2.8
    gbox(bm, (OUT_HEAD, OUT_SHAFT_Y + 0.05, hz), (0.4, 0.5, 0.34))
    gcyl(bm, (OUT_HEAD + 0.05, 0.2, hz + 0.37), 0.14, 0.4, 'z', segs=24)
    # Landing deck: lift cylinder barrels standing between the chains under the lift rails, and
    # the end photo eye (sensor on a post beyond the board ends, reflector opposite).
    bmy = bmesh.new()
    for z in LAND_Z:
        for x in LAND_CYL_X:
            gbox_span(bmy, (x - 0.08, 0.0, z - 0.08), (x + 0.08, 0.02, z + 0.08))
            gcyl(bmy, (x, 0.02 + LAND_BARREL / 2, z), 0.05, LAND_BARREL, 'y', segs=14)
    eye_y = LAND_TOP_DOWN + LAND_RISE + 0.10
    for z, sensor in ((-2.75, True), (2.75, False)):
        gbox_span(bm, (LANDING_STOP_X - 0.03, 0.0, z - 0.03), (LANDING_STOP_X + 0.03, eye_y + 0.1, z + 0.03))
        gbox(bmy, (LANDING_STOP_X, eye_y, z + (0.06 if z < 0 else -0.06)), (0.06, 0.08, 0.06))
    obj("LandingBase", bmy, coll, [M["grey"]], bevel=0.003, segs=1)
    obj("OutfeedFrame", bm, coll, [M["green"]], bevel=0.004)
    obj("OutfeedWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)
    return [shaft(coll, M, "OutfeedHeadShaft", OUT_HEAD, OUT_SHAFT_Y, OUT_Z, OUT_SPR, OUT_TEETH, CHAIN_ROLLER_R, 5.2, hub_r=0.07),
            shaft(coll, M, "OutfeedTailShaft", OUT_TAIL, OUT_SHAFT_Y, OUT_Z, OUT_SPR, OUT_TEETH, CHAIN_ROLLER_R, 5.2, hub_r=0.07)]


# ---------------------------------------------------------------- catwalks

WALK_Y = FRAME_BEAM_TOP                         # grating level with the infeed frame beams
WALK_Z0, WALK_Z1 = 3.05, 3.95                   # both sides, outboard of the frame and stick-frame columns
WALK_PLUS_X = (25.0, 31.0)                      # +Z side: stair down toward the unscrambler
WALK_MINUS_X = (25.75, 31.0)                    # -Z side: starts past the unscrambler head drive; stair down past the stick frame


def build_catwalks(coll, M):
    """Walkways along both sides of the stacker at the infeed deck level, so the line-up rolls,
    fence, layer stops, fork trolleys, unscrambler head and stick magazines can be reached; a
    stair from each down to the floor. Inner edges are railed too: the fork trolleys run there."""
    grate, rails, frame = bmesh.new(), bmesh.new(), bmesh.new()
    for side, (x0, x1), stair_x, dirx in ((1, WALK_PLUS_X, WALK_PLUS_X[0], -1.0), (-1, WALK_MINUS_X, WALK_MINUS_X[1], 1.0)):
        z0, z1 = sorted((side * WALK_Z0, side * WALK_Z1))
        closed_end = x1 if dirx < 0 else x0
        S.walkway(grate, rails, x0, x1, WALK_Y, z0, z1, (z0 + 0.02, z1 - 0.02), end_rails=(closed_end + (-0.03 if dirx < 0 else 0.03),))
        # Brackets off every column on that side, and posts at the outer corners of the ends.
        col_xs = [x for x in (25.55, 26.95, 29.05, STICK_FRAME_X[1]) if x0 < x < x1]
        for x in col_xs:
            gbeam(frame, (x, WALK_Y - 0.15, side * 2.95), (x, WALK_Y - 0.15, side * WALK_Z1), 0.08, 0.1)
            gbeam(frame, (x, WALK_Y - 0.85, side * 2.95), (x, WALK_Y - 0.2, side * (WALK_Z1 - 0.1)), 0.05, 0.05)
        for x in (x0 + 0.05, x1 - 0.05):
            for z in (z0 + 0.04, z1 - 0.04):
                gbox_span(frame, (x - 0.04, 0.0, z - 0.04), (x + 0.04, WALK_Y - 0.1, z + 0.04))
        S.stair(grate, rails, frame, stair_x, WALK_Y, z0, z1, dirx)
    obj("CatwalkFrame", frame, coll, [M["green"]], bevel=0.003, segs=1)
    obj("CatwalkGrating", grate, coll, [M["galv"]], bevel=0.0)
    return obj("CatwalkRails", rails, coll, [M["yellow"]], bevel=0.003, segs=1)


# ---------------------------------------------------------------- chain parts and preview

def build_chain_parts(coll, M):
    parts = {}
    bm = bmesh.new()                                  # drag chain (surge, outfeed)
    # Heavy 4 in bar chain, used on every lumber deck (surge, unscrambler, infeed, outfeed);
    # the unscrambler's lug links add a pusher lug.
    for name, lug in (("BarChainLink", False), ("UnscramblerLug", True)):
        bm = bmesh.new()
        p = CHAIN_PITCH
        for side in (-1, 1):
            z = side * 0.024
            L.add_prism(bm, [(-0.015, -0.015), (p + 0.015, -0.015), (p + 0.015, CHAIN_PLATE_H), (-0.015, CHAIN_PLATE_H)],
                        -(z + 0.005), -(z - 0.005))
        gcyl(bm, (0, 0, 0), CHAIN_ROLLER_R, 0.038, 'z', segs=10)
        if lug:
            gbox_span(bm, (p * 0.35, CHAIN_PLATE_H, -0.035), (p * 0.62, CHAIN_PLATE_H + UNS_LUG_H, 0.035))
        parts[name] = obj(name, bm, coll, [M["orange"] if lug else M["chain"]], bevel=0.0)
    bm = bmesh.new()
    gbox(bm, (STICK_LEN / 2, STICK_T / 2, 0.0), (STICK_LEN, STICK_T, STICK_W))
    parts["Stick"] = obj("Stick", bm, coll, [M["sticks"]], bevel=0.001, segs=1)
    return parts


def build_chain_preview(coll, M, parts):
    def place(src, mats, loop, pitch, strands, every=None, name="Chains", phase=0.0):
        path, total = loop
        count = int(round(total / pitch))
        pitch = total / count
        bm = bmesh.new()
        for k in range(count):
            if every and k % every:
                continue
            s = phase + k * pitch
            p1, p2 = path(s), path(s + pitch)
            for z in strands:
                m = S.link_matrix(p1, p2, z)
                start = len(bm.verts)
                bm.from_mesh(src.data)
                bm.verts.ensure_lookup_table()
                for v in bm.verts[start:]:
                    v.co = m @ v.co
        return L.make_object(name, bm, coll, mats, weighted=False)

    link = parts["BarChainLink"]
    place(link, [M["chain"]], surge_loop(), SURGE_PITCH, SURGE_Z, name="PreviewSurgeChain")
    place(link, [M["chain"]], outfeed_loop(), OUT_PITCH, OUT_Z, name="PreviewOutfeedChain")
    place(link, [M["chain"]], uns_loop(), UNS_PITCH, UNS_Z, name="PreviewUnscramblerChain")
    place(parts["UnscramblerLug"], [M["orange"]], uns_loop(), UNS_PITCH, UNS_Z, every=UNS_LUG_EVERY, name="PreviewUnscramblerLugs")
    place(link, [M["chain"]], infeed_loop(), INF_PITCH, INF_Z, name="PreviewInfeedChain")
    for src in parts.values():
        src.hide_render = True
        src.location = G(0, -5, 0)


def build_rolls_preview(coll, roll):
    for i, z in enumerate(ROLL_Z):
        L.link_copy(roll, "LineupRoll_%d" % i, coll, G(ROLL_XS[0], INFEED_TOP - ROLL_R, z))
    roll.hide_render = True
    roll.location = G(0, -5, 0)


def build_ending_preview(coll, rolls):
    for i, z in enumerate(END_Z):
        L.link_copy(rolls[0], "EndingRoll_%d" % i, coll, G((END_X0 + END_X1) / 2, END_AXLE_Y, z))
    for r in rolls:
        r.hide_render = True
        r.location = G(0, -5, 0)


PREVIEW_LAYERS = 9


PREVIEW_T, PREVIEW_W = 1.5 * INCH, 7.25 * INCH     # preview lumber: 2x8s
PREVIEW_PER_LAYER = int(52 * INCH // PREVIEW_W)


def incline_board(bm, s, t, w, z0):
    """Board lying on the unscrambler chains, trailing edge s metres up the carrying run."""
    p0 = UNS_FOOT + UNS_NORMAL * (UNS_SPR + UNS_PLATE_H) + UNS_DIR * s
    m = S.gmat(p0.x, p0.y, z0, (0, -math.degrees(UNS_ANGLE), 0))
    return tag_board(bm, L.add_box(bm, (w, 4.877, t), m @ L.mat((w / 2, -4.877 / 2, t / 2))))


def package(bm, x0, y0, layers, t, w, n):
    """Stickered package: n boards a layer, a stick on every stick line between layers. Board
    ends sit within a few mm of the line-up and boards a few mm apart, as the stacker leaves them."""
    for j in range(layers):
        y = y0 + j * (t + STICK_T)
        for k in range(n):
            jit = math.sin((j * 13 + k) * 12.9898) * 43758.5453
            jit -= math.floor(jit)
            board(bm, x0 + k * (w + 0.003) + 0.002 * jit, y, t, w, z0=LINEUP_FENCE_Z + 0.006 * jit)
        for z in STICK_Z:
            stick(bm, x0, y + t, z)


def build_preview_lumber(coll, M, animated=False):
    """Review lumber, one object per group so the animation can drive or hide them: a pack on
    the surge, a pile in the pocket, boards on the lugs and infeed, a layer forming, a package
    on the hoist, sticks in the magazines and a finished package at the landing stops.
    animated=True leaves out the groups the animation moves board by board."""
    t, w, n = PREVIEW_T, PREVIEW_W, PREVIEW_PER_LAYER
    groups = {}

    def group(name):
        if name not in groups:
            groups[name] = lumber_bmesh()
        return groups[name]

    for k in range(10):                                   # sorter pack on the surge chains
        board(group("PreviewSurgePack"), 18.4 + 0.004 * math.sin(k * 2.3), SURGE_TOP + k * t, t, w, z0=-2.40 + 0.01 * math.sin(k))
    for k in range(4):                                    # pile in the pocket, leaning on the incline
        p0 = UNS_FOOT + UNS_NORMAL * (UNS_SPR + UNS_PLATE_H + k * t) + UNS_DIR * (0.05 + k * 0.03)
        m = S.gmat(p0.x, p0.y, -2.42 + 0.02 * k, (0, -math.degrees(UNS_ANGLE), 0))
        tag_board(group("PreviewPocket"), L.add_box(group("PreviewPocket"), (w, 4.877, t), m @ L.mat((w / 2, -4.877 / 2, t / 2))))
    if not animated:
        for s in (0.9, 1.5, 2.1, 2.7, 3.3):               # one board ahead of each lug on the incline
            incline_board(group("PreviewIncline"), s, t, w, -2.39)
        for x in (25.7, 26.25, 26.8):                     # on the infeed, ends lining up
            board(group("PreviewInfeed"), x, INFEED_TOP, t, w, z0=LINEUP_FENCE_Z + (0.0 if x > 26.5 else 0.05))
        for k in range(n - 2):                            # layer forming against the stops
            board(group("PreviewForming"), LAYER_STOP_X - (k + 1) * (w + 0.002), INFEED_TOP, t, w, z0=LINEUP_FENCE_Z)
    # Package part-built on the hoist; sticks waiting in the magazines; a finished package lifted
    # on the landing rails, its last layer stickered too (the stacker sticks every layer).
    package(group("PreviewPackage"), STICK_X0, HOIST_TOP - PREVIEW_LAYERS * (t + STICK_T), PREVIEW_LAYERS, t, w, n)
    for z in STICK_Z:
        for k in range(12):
            stick(group("PreviewMagSticks"), STICK_X0, MAG_BOTTOM + k * STICK_T, z)
    package(group("PreviewLanding"), LANDING_STOP_X - n * (w + 0.003), LAND_TOP_DOWN + LAND_RISE, 31, t, w, n)
    for name, b in groups.items():
        o = L.make_object(name, b, coll, [M["lumber"], M["sticks"]], bevel=0.002, bevel_segments=1, weighted=False)
        o.data.polygons.foreach_set("use_smooth", [False] * len(o.data.polygons))


# ---------------------------------------------------------------- assembly

def build(materials, preview_lumber=True, animated=False):
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    parts_coll = L.collection("StackerParts", coll)
    shafts = build_surge(coll, materials) + build_unscrambler(coll, materials) + build_infeed(coll, materials)
    adjusters = build_pocket_adjusters(coll, materials)
    shafts += build_outfeed(coll, materials)
    build_fork_drive(coll, materials)
    build_stick_frame(coll, materials)
    build_package_guides(coll, materials)
    build_holdover_rack(coll, materials)
    hoist = build_hoist(coll, materials)
    build_catwalks(coll, materials)
    moving = [adjusters, build_surge_stop(coll, materials), build_pop_stops(coll, materials, "LayerStops", LAYER_STOP_X, LAYER_STOP_Z),
              build_course_divider(coll, materials), *build_forks(coll, materials),
              build_fork_trolley(coll, materials), build_fence(coll, materials), build_stick_gates(coll, materials), hoist,
              build_landing_lift(coll, materials), build_ending_lift(coll, materials), build_ending_gate(coll, materials)]
    build_far_fence(coll, materials)
    roll = build_roll(parts_coll, materials)
    build_ending_preview(coll, build_ending_rolls(parts_coll, materials))
    chain_parts = build_chain_parts(parts_coll, materials)
    build_chain_preview(coll, materials, chain_parts)
    build_rolls_preview(coll, roll)
    if preview_lumber:
        build_preview_lumber(coll, materials, animated)
        hoist.location = G(0, -PREVIEW_LAYERS * (1.5 * INCH + STICK_T), 0)     # arms under the part-built package
        bpy.data.objects["PullbackFence"].location = G(0, FENCE_RAISE, 0)       # idle: raised while the layer forms
        bpy.data.objects["LandingLift"].location = G(0, LAND_RISE, 0)           # holding the finished package for pickup
        floor_with_pit(coll, materials)
    return {"objects": len(coll.all_objects), "shafts": [s.name for s in shafts], "moving": [m.name for m in moving],
            "uns_foot": tuple(round(v, 3) for v in UNS_FOOT), "uns_head": tuple(round(v, 3) for v in UNS_HEAD)}
