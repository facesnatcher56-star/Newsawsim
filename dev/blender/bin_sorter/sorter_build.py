"""Procedural 10-bay lumber drop sorter (run inside Blender).

All dimensions are written in the game's sorter-local frame (Godot axes):
+X board travel, +Y up, +Z along the board length, origin on the floor where
the board lug incline hands over. ``G()`` converts to Blender axes (x, -z, y),
which is exactly what the glTF exporter undoes, so exported pieces land in
Godot with these coordinates unchanged.

Board path (every step is a physical part):
1. The incline's lugs push a board off its crest (local x = -0.58) onto the
   infeed roll case; the powered rolls carry it to the pop-up stop.
2. The overhead lug chain's tail sprocket sits above the waiting board's
   trailing side, so each lug comes down behind a board, never on top of one.
   The stop drops and the lug pushes the board along the deck (DECK_Y).
3. The deck is not plate: the board slides on UHMW-capped wear rails, and over
   its bay it rides that bay's gate arms, all keyed to one cross shaft. Two air
   cylinders rotate the shaft, every arm drops together, and the board slides off
   onto that bay's fork carriage; the bay front bars stop it overshooting.
4. Each carriage hangs from two cables on its own hoist (cross shaft, drums,
   gearmotor) and steps down by one board thickness per board.
5. A full bay lowers its tines below the haul-out chains, leaving the stack on
   them; the chains carry it on to the green stacker's surge chains.

Support: every part rests on, hangs from, or is bolted to something that
traces back to the column base plates (checked with common/support_check.py).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
import mesh_lib as L  # noqa: E402

COLL = "BinSorter10"

# ---------------------------------------------------------------- layout
NB = 10                     # bays
BAY = 1.0                   # bay pitch along X
BX0 = 1.0                   # upstream edge of bay 0; the infeed section sits in front of it
DECK_Y = 4.30               # board carrying plane (matches the incline crest)
DECK_T = 0.03
DECK_HALF = 2.8             # deck half length along Z
COL_Z = 3.05                # column lines
TOP_BEAM_Y = 5.95           # centre of the top beams (return-run lugs point up and must clear them)
CROSS_BOTTOM = TOP_BEAM_Y - 0.125

GATE_X0 = 0.1               # gate shaft axis offset inside each bay
GATE_W = 0.8                # arm length from the shaft axis
GATE_AXIS_DY = -0.06        # gate shaft axis below the deck plane
GATE_SHAFT_HALF = 2.76      # inside the hoist cables at +/-END_BLOCK_Z
GATE_ARM_Z = (-2.40, -1.75, -1.05, -0.35, 0.35, 1.05, 1.75, 2.40)   # arm and wear-rail lines; 8 ft boards span four
GATE_BEARING_Z = (-2.08, -0.70, 0.70, 2.08)                          # between the arms
GATE_CYL_Z = 2.70           # gate cylinders sit outside the board ends (16 ft board = +/-2.44)
RAIL_W = 0.05               # wear rail / arm top flange width
WEAR_T = 0.008              # UHMW cap on rails and arms
RAIL_GAP = 0.05             # fixed rails stop this far upstream of a gate shaft
FRONT_X = 0.985             # bay front bars, from the bay's upstream edge: past the tine tips, short of the next carriage
FRONT_BOTTOM = 1.2          # nearly down to the haul-out: a pile stays boxed in as the forks lower it,
                            # and stacks riding out on the haul chains still pass beneath
FRONT_Z = (-2.4, -1.7, -1.0, -0.3, 0.3, 1.0, 1.7, 2.4)
CATCH_Y = 3.20              # carriage tine top at the catch position
CARRIAGE_X = 0.20           # carriage origin offset inside each bay (clear of the deck supports)
END_BLOCK_Z = COL_Z - 0.20  # carriage end blocks and hoist drums
HANG_H = 0.70               # carriage tine top to hanger beam

TOP_STRANDS = (-2.25, -1.375, 0.0, 1.375)   # boards come even-ended at -z: a 6 ft board gets two lugs
TOP_PITCH = 0.20
TOP_TEETH = 10
TOP_SPR = TOP_PITCH / (2 * math.sin(math.pi / TOP_TEETH))
TOP_SHAFT_Y = 5.00
TOP_X_TAIL = BX0 - 0.70     # lugs reach the deck here, behind the waiting board
TOP_X_HEAD = BX0 + NB + 0.30
Y_LOW = TOP_SHAFT_Y - TOP_SPR        # working (lower) run pin line
Y_RET = TOP_SHAFT_Y + TOP_SPR        # return run pin line
LUG_EVERY = 5               # one lug every 5 links = 1.0 m
LUG_LEN = Y_LOW - DECK_Y - 0.01      # pin line down to just above the deck
GUARD_R = TOP_SPR + LUG_LEN + 0.12   # sprocket guards clear the lug sweep
ROLLER_R = 0.018            # link roller
OUT_ROLLER_Z, OUT_ROLLER_R = 0.046, 0.012   # outboard pin rollers that ride the lower track

X_START = TOP_X_TAIL - 0.30          # frame extents along X
X_END = TOP_X_HEAD + 0.30

CREST_X = -0.58             # the incline's lugs push boards off its crest here
DEAD_X0 = 0.55              # end of the old roll case; the stop's frame starts here
STOP_X = BX0 - 0.15         # board leading edge waits here
PLATE_TOP = DECK_Y - 0.004  # infeed dead plate: just under the transfer chain tops

# Live chain transfer: smooth-top chains carry a board from the crest to the stop and slide
# under it while it waits. Lanes clear the incline's lug lanes and the stop fingers.
XFER_Z = (-1.35, -0.3, 0.3, 1.35)
XFER_TAIL = -0.52           # tail sprockets right at the crest, just above the incline's head bearing block
XFER_HEAD = 0.70            # head shaft, upstream of the stop rocker
XFER_PITCH = 0.0508
XFER_TEETH = 6              # small enough to clear the incline's head bearing block (top DECK_Y - 0.12)
XFER_SPR = XFER_PITCH / (2 * math.sin(math.pi / XFER_TEETH))
XFER_PIN_Y = DECK_Y - 0.010                 # link plates reach 8 mm above the pins: 2 mm under the deck line
XFER_TOOTH_R = 0.004                        # sprocket tooth form: tips stay under the chain's top
XFER_SHAFT_Y = XFER_PIN_Y - XFER_SPR
XFER_ROLLER_R = 0.0075
INCLINE_LANES = (-2.0625, -0.6875, 0.6875, 2.0625)
INCLINE_SWEEP_X = -0.15     # the incline's lugs swing through the plate up to here as they go round its head
STOP_ZS = (-2.05, -0.95, 0.6, 2.0)   # stop fingers, clear of the lug lanes; an even-ended 6 ft board meets the first two

HAUL_STRANDS = (-2.25, -1.375, 0.0, 1.375)    # boards come even-ended at -z: a 6 ft board rides on the first two
HAUL_PITCH = 0.10
HAUL_TEETH = 6
HAUL_SPR = HAUL_PITCH / (2 * math.sin(math.pi / HAUL_TEETH))
HAUL_SHAFT_Y = 0.22
HAUL_X_TAIL = BX0 - 0.40
HAUL_X_HEAD = BX0 + NB + 4.40
HAUL_TOP = HAUL_SHAFT_Y + HAUL_SPR + 0.012   # top of the carrying chain: stacks rest here
HAUL_HALF = 2.6
TABLE_X0 = BX0 + NB + 0.6
STACK_STOP_X = HAUL_X_HEAD - HAUL_SPR - 0.25    # stacks stop before the chains wrap the head sprocket
END_STOP_Z = (-1.9, -0.65, 0.65, 1.9)           # end stop posts, between the haul strands

TINE_Z = (-2.05, -0.65, 0.65, 2.05)
CATWALK_Z0, CATWALK_Z1 = 3.25, 4.15
CATWALK_Y = 4.10


def bay_x(i):
    return BX0 + i * BAY


def G(x, y, z):
    return Vector((x, -z, y))


def gmat(x, y, z, rot=(0, 0, 0)):
    return L.mat(G(x, y, z), rot)


def gbox(bm, c, size, mi=0, rot=(0, 0, 0)):
    """Box from a Godot centre and Godot (sx, sy, sz) size."""
    return L.add_box(bm, (size[0], size[2], size[1]), gmat(*c, rot), mi)


def gbox_span(bm, p0, p1, mi=0):
    """Axis-aligned box between two Godot corners."""
    c = [(a + b) / 2 for a, b in zip(p0, p1)]
    s = [abs(b - a) for a, b in zip(p0, p1)]
    return gbox(bm, c, s, mi)


def gcyl(bm, c, r, length, axis='z', mi=0, segs=16):
    rot = {'x': (0, 90, 0), 'y': (0, 0, 0), 'z': (90, 0, 0)}[axis]
    return L.add_cyl(bm, r, length, gmat(*c, rot), segs=segs, mat_index=mi)


def grod(bm, p0, p1, r, segs=12, mi=0):
    return L.add_rod(bm, G(*p0), G(*p1), r, segs=segs, mat_index=mi)


def gbeam(bm, p0, p1, w, h, mi=0):
    return L.add_beam(bm, G(*p0), G(*p1), w, h, mat_index=mi)


def ibeam(bm, axis, c, length, h=0.30, w=0.15, tf=0.016, tw=0.010, mi=0):
    """Wide-flange beam. axis 'x'/'z' horizontal (web vertical), 'y' column (flanges facing +/-Z)."""
    x, y, z = c
    if axis == 'x':
        gbox(bm, (x, y + h / 2 - tf / 2, z), (length, tf, w), mi)
        gbox(bm, (x, y - h / 2 + tf / 2, z), (length, tf, w), mi)
        gbox(bm, (x, y, z), (length, h - 2 * tf, tw), mi)
    elif axis == 'z':
        gbox(bm, (x, y + h / 2 - tf / 2, z), (w, tf, length), mi)
        gbox(bm, (x, y - h / 2 + tf / 2, z), (w, tf, length), mi)
        gbox(bm, (x, y, z), (tw, h - 2 * tf, length), mi)
    else:
        gbox(bm, (x, y, z + h / 2 - tf / 2), (w, length, tf), mi)
        gbox(bm, (x, y, z - h / 2 + tf / 2), (w, length, tf), mi)
        gbox(bm, (x, y, z), (tw, length, h - 2 * tf), mi)


def obj(name, bm, coll, mats, bevel=0.004, segs=2, parent=None, loc=(0, 0, 0)):
    o = L.make_object(name, bm, coll, mats, bevel=bevel, bevel_segments=segs)
    o.location = G(*loc)
    if parent is not None:
        o.parent = parent
    return o


# ---------------------------------------------------------------- frame

def column_xs():
    # A column line at every bay boundary, plus end columns outboard of the overhead shafts.
    return [bay_x(i) for i in range(NB + 1)] + [X_START + 0.05, X_END - 0.05]


def build_frame(coll, M):
    bm = bmesh.new()
    top = TOP_BEAM_Y + 0.15
    for x in column_xs():
        for z in (-COL_Z, COL_Z):
            ibeam(bm, 'y', (x, top / 2, z), top, h=0.2, w=0.2, tf=0.014, tw=0.009)
            gbox(bm, (x, 0.012, z), (0.36, 0.024, 0.36))                        # base plate
            for dx in (-0.13, 0.13):
                for dz in (-0.13, 0.13):
                    gcyl(bm, (x + dx, 0.035, z + dz), 0.012, 0.03, 'y', segs=6)  # anchor bolts
    for z in (-COL_Z, COL_Z):
        ibeam(bm, 'x', ((X_START + X_END) / 2, TOP_BEAM_Y, z), X_END - X_START + 0.2, h=0.36, w=0.17)
    for x in column_xs():
        ibeam(bm, 'z', (x, TOP_BEAM_Y, 0.0), 2 * COL_Z + 0.2, h=0.25, w=0.13)
        # Deck support under each fixed strip (the end columns carry no deck).
        if BX0 <= x <= BX0 + NB:
            ibeam(bm, 'z', (x, DECK_Y - DECK_T - 0.09, 0.0), 2 * COL_Z, h=0.18, w=0.10)
    # Knee braces between columns and the top longitudinal beams.
    for x in column_xs():
        for z in (-COL_Z, COL_Z):
            for sgn in (-1, 1):
                if not (X_START < x + sgn * 0.6 < X_END):
                    continue
                gbeam(bm, (x, TOP_BEAM_Y - 0.75, z), (x + sgn * 0.55, TOP_BEAM_Y - 0.2, z), 0.07, 0.07)
    # Long-run bracing at mid height on the outer lines.
    for z in (-COL_Z, COL_Z):
        gbox(bm, ((X_START + X_END) / 2, 2.2, z), (X_END - X_START - 0.1, 0.12, 0.08))
    return obj("Frame", bm, coll, [M["green"]], bevel=0.006)


def build_deck(coll, M):
    bm = bmesh.new()      # steel: dead plate, rail bars, brackets
    bmh = bmesh.new()     # gate shaft bearings
    bmu = bmesh.new()     # UHMW wear caps
    y = DECK_Y - DECK_T / 2
    # Fixed wear rails between gates, in line with the gate arms, lying on the deck support beams.
    spans = [(bay_x(i) - (BAY - GATE_X0 - GATE_W) + 0.005, bay_x(i) + GATE_X0 - RAIL_GAP) for i in range(1, NB)]
    spans.append((BX0 + NB - (BAY - GATE_X0 - GATE_W) + 0.005, TOP_X_HEAD - 0.03))   # stops short of the head guard
    for x0, x1 in spans:
        for z in GATE_ARM_Z:
            gbox_span(bm, (x0, DECK_Y - DECK_T, z - RAIL_W / 2), (x1, DECK_Y - WEAR_T, z + RAIL_W / 2))
            gbox_span(bmu, (x0, DECK_Y - WEAR_T, z - RAIL_W / 2), (x1, DECK_Y, z + RAIL_W / 2))
    # Infeed dead plate from the incline crest to bay 0's gate, slotted for the transfer
    # chains, the stop fingers and the incline's lugs as they swing round its head sprocket.
    holes = [(XFER_TAIL - 0.1, XFER_HEAD + 0.1, z - 0.025, z + 0.025) for z in XFER_Z]
    holes += [(STOP_X - 0.11, STOP_X + 0.15, z - 0.04, z + 0.04) for z in STOP_ZS]
    holes += [(CREST_X - 0.01, INCLINE_SWEEP_X, z - 0.08, z + 0.08) for z in INCLINE_LANES]
    slotted_plate(bm, CREST_X, BX0 + GATE_X0 - RAIL_GAP, -DECK_HALF, DECK_HALF, PLATE_TOP - DECK_T, PLATE_TOP, holes)
    # Gate shaft bearings on brackets bolted to the deck support beam web, between the arms.
    for i in range(NB):
        ax, ay = bay_x(i) + GATE_X0, DECK_Y + GATE_AXIS_DY
        for z in GATE_BEARING_Z:
            gcyl(bmh, (ax, ay, z), 0.045, 0.07, 'z', segs=16)
            gbox_span(bm, (bay_x(i) + 0.005, ay - 0.035, z - 0.03), (ax - 0.04, ay + 0.01, z + 0.03))
    # Clevis brackets on the deck support webs that anchor the gate cylinders.
    for i in range(NB):
        x = bay_x(i + 1)
        for z in (-GATE_CYL_Z, GATE_CYL_Z):
            gbox_span(bm, (x - 0.06, DECK_Y - 0.19, z - 0.04), (x - 0.005, DECK_Y - 0.11, z + 0.04))
    deck = obj("DeckFixed", bm, coll, [M["deck"]], bevel=0.003, segs=1)
    hinges = obj("DeckHinges", bmh, coll, [M["shaft"]], bevel=0.002, segs=1)
    obj("DeckWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)
    build_bay_fronts(coll, M)
    return deck, hinges


def slotted_plate(bm, x0, x1, z0, z1, y0, y1, holes, mi=0):
    """Plate from (x0, z0) to (x1, z1) with rectangular holes (hx0, hx1, hz0, hz1) left out,
    built from the grid cells that fall outside every hole."""
    xs = sorted({x0, x1, *[min(max(h[0], x0), x1) for h in holes], *[min(max(h[1], x0), x1) for h in holes]})
    zs = sorted({z0, z1, *[min(max(h[2], z0), z1) for h in holes], *[min(max(h[3], z0), z1) for h in holes]})
    for a, b in zip(xs, xs[1:]):
        for c, d in zip(zs, zs[1:]):
            mx, mz = (a + b) / 2, (c + d) / 2
            if b - a < 1e-4 or d - c < 1e-4:
                continue
            if any(h[0] < mx < h[1] and h[2] < mz < h[3] for h in holes):
                continue
            gbox_span(bm, (a, y0, c), (b, y1, d), mi)


def build_bay_fronts(coll, M):
    """Bin front at the downstream side of every bay: flat bars hung from an angle bolted
    under the next deck support beam. A board coming off the gate arms fast hits them
    and drops onto the tines instead of carrying on into the next bay."""
    bm = bmesh.new()
    beam_bottom = DECK_Y - DECK_T - 0.18
    for i in range(NB):
        x = bay_x(i) + FRONT_X
        gbox_span(bm, (x - 0.01, beam_bottom - 0.05, -2.6), (bay_x(i + 1) + 0.04, beam_bottom, 2.6))   # angle under the beam
        for z in FRONT_Z:
            gbox_span(bm, (x - 0.01, FRONT_BOTTOM, z - 0.025), (x + 0.01, beam_bottom - 0.05, z + 0.025))
    return obj("BayFronts", bm, coll, [M["green"]], bevel=0.003, segs=1)


def build_infeed(coll, M):
    """Live chain transfer and pop-up stop between the incline and bay 0.

    Four smooth-top chains run in slots in the dead plate, their tops flush with the deck:
    they carry a board off the incline crest up to the stop and slide on under it while it
    waits. Tail sprockets sit on stub shafts hung below the incline's lug sweep; the head
    shaft carries the drive."""
    bmg = bmesh.new()     # stand (green)
    bmo = bmesh.new()     # stop and actuators (orange)
    bmm = bmesh.new()     # bearings and drive (grey)
    bmu = bmesh.new()     # chain wear strips (UHMW)
    plate_bottom = PLATE_TOP - DECK_T
    rail_x0 = -0.46       # clear of the incline's head bearing block
    rail_bottom = plate_bottom - 0.12
    for z in (-2.75, 2.75):
        gbox_span(bmg, (rail_x0, rail_bottom, z - 0.04), (DEAD_X0 + 0.07, plate_bottom, z + 0.04))   # side rail
        for x in (-0.40, DEAD_X0):
            gbox_span(bmg, (x - 0.05, 0.0, z - 0.05), (x + 0.05, rail_bottom, z + 0.05))           # leg
            gbox(bmg, (x, 0.012, z), (0.22, 0.024, 0.22))
        gbeam(bmg, (-0.40, 0.3, z), (DEAD_X0, rail_bottom - 0.4, z), 0.06, 0.06)                   # sway brace
    for x in (-0.40, DEAD_X0):
        gbox_span(bmg, (x - 0.04, 1.0, -2.75), (x + 0.04, 1.08, 2.75))                             # floor-level tie
    # Plate stiffeners between the chain slots (and the incline lug slots), resting on the rails.
    for x in (-0.20, 0.25, DEAD_X0 + 0.05):
        cuts = sorted([z for lane in XFER_Z for z in (lane - 0.03, lane + 0.03)]
                      + ([z for lane in INCLINE_LANES for z in (lane - 0.09, lane + 0.09)] if x < INCLINE_SWEEP_X else []))
        edges = [-2.78] + cuts + [2.78]
        for k in range(0, len(edges), 2):
            gbox_span(bmg, (x - 0.025, plate_bottom - 0.04, edges[k]), (x + 0.025, plate_bottom, edges[k + 1]))
    # Chain channels: a UHMW strip for the top run's rollers in a U channel under each lane,
    # each carried on posts beside the return run from cross beams bolted under the rails.
    strip_top = XFER_PIN_Y - XFER_ROLLER_R
    ret_bottom = XFER_SHAFT_Y - XFER_SPR - 0.008
    for lane in XFER_Z:
        x0, x1 = XFER_TAIL + XFER_SPR + 0.03, XFER_HEAD - XFER_SPR - 0.03     # where the chain leaves the sprockets
        gbox_span(bmu, (x0, strip_top - 0.01, lane - 0.015), (x1, strip_top, lane + 0.015))
        gbox_span(bmg, (x0, strip_top - 0.016, lane - 0.022), (x1, strip_top - 0.01, lane + 0.022))
        for side in (-1, 1):
            gbox_span(bmg, (x0, strip_top - 0.016, min(lane + side * 0.016, lane + side * 0.022)),
                      (x1, strip_top + 0.004, max(lane + side * 0.016, lane + side * 0.022)))
        for x in (0.0, 0.45):
            gbox_span(bmg, (x - 0.02, rail_bottom - 0.06 + 0.06, lane + 0.03), (x + 0.02, strip_top - 0.016, lane + 0.04))   # post
            gbox_span(bmg, (x - 0.02, strip_top - 0.022, lane + 0.016), (x + 0.02, strip_top - 0.016, lane + 0.04))       # gusset
    for x in (0.0, 0.45):
        gbox_span(bmg, (x - 0.03, rail_bottom - 0.06, -2.78), (x + 0.03, rail_bottom, 2.78))       # cross beam under the rails
    assert rail_bottom < ret_bottom, "return run must clear the cross beams"
    # Tail: stub shafts on bearing blocks either side of each sprocket, hung from the plate's
    # underside (the incline's head bearing block fills the space below).
    for lane in XFER_Z:
        for side in (-1, 1):
            z = lane + side * 0.032
            gbox(bmm, (XFER_TAIL, XFER_SHAFT_Y, z), (0.05, 0.04, 0.02))                           # bearing block
            gbox_span(bmg, (XFER_TAIL - 0.02, XFER_SHAFT_Y + 0.02, z - 0.008), (XFER_TAIL + 0.02, plate_bottom, z + 0.008))
    # Head: pillow blocks hung from the plate's underside, gearmotor on the far end.
    for z in (-2.75, 2.75):
        pillow_block(bmm, XFER_HEAD, XFER_SHAFT_Y, z, base_down=False)
        gbox_span(bmg, (XFER_HEAD - 0.13, XFER_SHAFT_Y + 0.085, z - 0.05), (XFER_HEAD + 0.13, plate_bottom, z + 0.05))
    gbox(bmm, (XFER_HEAD, XFER_SHAFT_Y - 0.03, -2.98), (0.28, 0.3, 0.2))
    gcyl(bmm, (XFER_HEAD - 0.26, XFER_SHAFT_Y - 0.08, -2.98), 0.08, 0.26, 'x', segs=18)
    gbox_span(bmg, (XFER_HEAD - 0.4, XFER_SHAFT_Y - 0.18, -3.08), (XFER_HEAD + 0.14, XFER_SHAFT_Y - 0.165, -2.88))   # motor shelf
    gbox_span(bmg, (XFER_HEAD - 0.4, XFER_SHAFT_Y - 0.165, -2.80), (XFER_HEAD - 0.1, plate_bottom, -2.79))           # shelf hanger, upstream of the shaft
    # Pop-up stop: a rocker shaft under the dead plate whose arms rise through the slots.
    sy = DECK_Y - DECK_T - 0.08
    gcyl(bmo, (STOP_X - 0.03, sy, 0.0), 0.03, 4.9, 'z', segs=14)
    for z in (-2.45, 2.45):
        gbox_span(bmg, (STOP_X - 0.09, sy - 0.05, z - 0.05), (STOP_X + 0.03, plate_bottom, z + 0.05))   # bearing hanger
    for z in STOP_ZS:
        gbox_span(bmo, (STOP_X - 0.05, sy, z - 0.025), (STOP_X, DECK_Y + 0.06, z + 0.025))                # finger
    gbox_span(bmo, (STOP_X - 0.05, sy - 0.06, 2.3 - 0.03), (STOP_X - 0.01, sy, 2.3 + 0.03))              # lever
    grod(bmo, (STOP_X - 0.03, sy - 0.04, 2.3), (BX0 - 0.005, sy - 0.04, 2.3), 0.025)                       # cylinder to the beam web
    obj("InfeedStand", bmg, coll, [M["green"]], bevel=0.003, segs=1)
    obj("InfeedDrive", bmm, coll, [M["grey"]], bevel=0.003, segs=1)
    obj("TransferWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)
    obj("InfeedStop", bmo, coll, [M["orange"]], bevel=0.003, segs=1)
    # Rotating parts, origins on their axes so the game can spin them about Z.
    bmh = bmesh.new()
    gcyl(bmh, (0, 0, 0), 0.025, 2 * 2.98, 'z', mi=0, segs=16)
    for lane in XFER_Z:
        sprocket_ring(bmh, XFER_TEETH, XFER_SPR, XFER_TOOTH_R, 0.008, lane, 0.032, mi=1)
        gcyl(bmh, (0, 0, lane), 0.035, 0.04, 'z', mi=0, segs=14)
    obj("TransferHeadShaft", bmh, coll, [M["shaft"], M["chain"]], bevel=0.0, loc=(XFER_HEAD, XFER_SHAFT_Y, 0))
    bmt = bmesh.new()
    for lane in XFER_Z:
        gcyl(bmt, (0, 0, lane), 0.018, 0.1, 'z', mi=0, segs=12)
        sprocket_ring(bmt, XFER_TEETH, XFER_SPR, XFER_TOOTH_R, 0.008, lane, 0.022, mi=1)
        gcyl(bmt, (0, 0, lane), 0.026, 0.03, 'z', mi=0, segs=12)
    obj("TransferTailSprockets", bmt, coll, [M["shaft"], M["chain"]], bevel=0.0, loc=(XFER_TAIL, XFER_SHAFT_Y, 0))


def build_chain_supports(coll, M):
    """Return-run race above, lipped working-run track below, both hung from the cross beams."""
    bm = bmesh.new()
    bmu = bmesh.new()
    x0, x1 = TOP_X_TAIL + 0.45, TOP_X_HEAD - 0.45
    for z in TOP_STRANDS:
        # Race: the return run's rollers rest on the UHMW strip; the walls keep it in line.
        strip_top = Y_RET - ROLLER_R
        gbox_span(bmu, (x0, strip_top - 0.015, z - 0.016), (x1, strip_top, z + 0.016))
        gbox_span(bm, (x0, strip_top - 0.03, z - 0.076), (x1, strip_top - 0.015, z + 0.076))
        for side in (-1, 1):
            gbox_span(bm, (x0, strip_top - 0.03, z + side * 0.064), (x1, Y_RET + 0.03, z + side * 0.076))
        # Working-run track: two lips under the outboard pin rollers, a gap between them for the lugs.
        lip_top = Y_LOW - OUT_ROLLER_R
        for side in (-1, 1):
            zi, zo = z + side * 0.036, z + side * 0.075
            gbox_span(bm, (x0, lip_top - 0.008, min(zi, zo)), (x1, lip_top, max(zi, zo)))                 # lip
            zw0, zw1 = z + side * 0.075, z + side * 0.083
            gbox_span(bm, (x0, lip_top - 0.008, min(zw0, zw1)), (x1, Y_LOW + 0.06, max(zw0, zw1)))        # web
            zf0, zf1 = z + side * 0.06, z + side * 0.083
            gbox_span(bm, (x0, Y_LOW + 0.05, min(zf0, zf1)), (x1, Y_LOW + 0.06, max(zf0, zf1)))           # hold-down flange
        # Hangers at every cross beam: straps on both sides tie track and race to the beam.
        for x in column_xs():
            if x0 + 0.05 < x < x1 - 0.05:
                for side in (-1, 1):
                    za, zb = z + side * 0.076, z + side * 0.086
                    gbox_span(bm, (x - 0.03, lip_top - 0.008, min(za, zb)), (x + 0.03, CROSS_BOTTOM, max(za, zb)))
    return obj("ChainSupports", bm, coll, [M["green"]], bevel=0.002, segs=1), obj("RaceWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)


STAIR_Z0 = 3.38             # sorter stair inner stringer: clear of the haul-out drive motor (z <= 3.33)
STAIR_GOING = 0.26
STAIR_MAX_RISE = 0.19
STAIR_LANDING = 1.0
RAIL_H, MID_H = 1.07, 0.55


def stair(grate, rails, frame, x_top, y_top, z0, z1, dirx):
    """Straight stair from a walkway edge at (x_top, y_top) down to the floor, running along
    dirx (+1/-1). Grating treads, channel stringers, handrails both sides; a landing halfway
    when the rise is over 3.6 m. Returns the floor x of the bottom step."""
    n = math.ceil(y_top / STAIR_MAX_RISE)
    r = y_top / n
    flights = [n] if y_top <= 3.6 else [n // 2, n - n // 2]
    x, y = x_top, y_top
    for f, m in enumerate(flights):
        for k in range(1, m):                                   # treads (the last step is the landing/floor)
            ty = y - k * r
            xa, xb = x + dirx * (k - 1) * STAIR_GOING, x + dirx * k * STAIR_GOING
            gbox_span(grate, (min(xa, xb), ty - 0.03, z0), (max(xa, xb), ty, z1))
            gbox_span(grate, (min(xa, xb), ty - 0.05, z0), (min(xa, xb) + 0.02, ty, z1))       # nosing bar
        x_end, y_end = x + dirx * (m - 1) * STAIR_GOING, y - m * r
        for z in (z0, z1):                                      # stringers and rails along the nosing line
            gbeam(frame, (x, y - 0.12, z), (x_end + dirx * 0.1, y_end + 0.05, z), 0.012, 0.22)
            for h in (RAIL_H, MID_H):
                grod(rails, (x, y + h, z), (x_end, y_end + r + h, z), 0.021 if h == RAIL_H else 0.017, segs=10)
            for xx, yy in ((x, y), (x_end, y_end + r)):
                grod(rails, (xx, yy, z), (xx, yy + RAIL_H, z), 0.021, segs=10)
        x, y = x_end, y_end
        if f < len(flights) - 1:                                # landing on four posts
            xl = x + dirx * STAIR_LANDING
            gbox_span(grate, (min(x, xl), y - 0.03, z0), (max(x, xl), y, z1))
            for xx in (x, xl):
                for z in (z0, z1):
                    gbox_span(frame, (xx - 0.04, 0.0, z - 0.04), (xx + 0.04, y - 0.03, z + 0.04))
            for z in (z0, z1):
                for h in (RAIL_H, MID_H):
                    grod(rails, (x, y + h, z), (xl, y + h, z), 0.021 if h == RAIL_H else 0.017, segs=10)
                grod(rails, (xl, y, z), (xl, y + RAIL_H, z), 0.021, segs=10)
            x = xl
    return x


def walkway(grate, rails, x0, x1, y, z0, z1, rail_zs, end_rails=()):
    """Bar-grating walkway between x0 and x1, with kick plates, posts, top and mid rails
    along each z in rail_zs and across each x in end_rails."""
    n = int((x1 - x0) / 0.04)
    for k in range(n + 1):
        gbox(grate, (x0 + k * (x1 - x0) / n, y - 0.015, (z0 + z1) / 2), (0.005, 0.03, z1 - z0))
    for k in range(int((x1 - x0) / 0.1) + 1):
        gbox(grate, (x0 + k * 0.1, y - 0.01, (z0 + z1) / 2), (0.004, 0.02, z1 - z0))
    for z in (z0, z1):
        gbox_span(grate, (x0, y - 0.1, z - 0.02), (x1, y, z + 0.02))
    for z in rail_zs:
        posts = [x0 + 0.05 + k * 1.5 for k in range(int((x1 - x0 - 0.1) / 1.5) + 1)] + [x1 - 0.05]
        for x in posts:
            grod(rails, (x, y, z), (x, y + RAIL_H, z), 0.021, segs=10)
        for h in (RAIL_H, MID_H):
            grod(rails, (x0 + 0.05, y + h, z), (x1 - 0.05, y + h, z), 0.021 if h == RAIL_H else 0.017, segs=10)
        gbox_span(rails, (x0 + 0.05, y, z - 0.005), (x1 - 0.05, y + 0.1, z + 0.005))
    for x in end_rails:
        for h in (RAIL_H, MID_H):
            grod(rails, (x, y + h, z0), (x, y + h, z1), 0.021 if h == RAIL_H else 0.017, segs=10)
        gbox_span(rails, (x - 0.005, y, z0), (x + 0.005, y + 0.1, z1))


def build_catwalk(coll, M):
    grate = bmesh.new()
    rails = bmesh.new()
    brackets = bmesh.new()
    z0, z1 = CATWALK_Z0, CATWALK_Z1
    y = CATWALK_Y
    x0, x1 = X_START - 0.4, X_END
    n = int((x1 - x0) / 0.04)
    for k in range(n + 1):
        x = x0 + k * (x1 - x0) / n
        gbox(grate, (x, y - 0.015, (z0 + z1) / 2), (0.005, 0.03, z1 - z0))
    for z in (z0, z1):
        gbox_span(grate, (x0, y - 0.1, z - 0.04), (x1, y, z + 0.04))
    for k in range(0, int((x1 - x0) / 0.1) + 1):
        x = x0 + k * 0.1
        gbox(grate, (x, y - 0.01, (z0 + z1) / 2), (0.004, 0.02, z1 - z0))
    for x in column_xs():
        if x0 < x < x1:
            gbeam(brackets, (x, y - 0.1, COL_Z + 0.1), (x, y - 0.1, z1), 0.08, 0.1)
            gbeam(brackets, (x, y - 0.75, COL_Z + 0.1), (x, y - 0.12, z1 - 0.1), 0.05, 0.05)
    posts = [x for x in (x0 + 0.05 + k * 1.5 for k in range(int((x1 - x0) / 1.5) + 1)) if x < x1 - 0.3] + [x1 - 0.05]
    for x in posts:
        grod(rails, (x, y, z1 - 0.03), (x, y + 1.07, z1 - 0.03), 0.021, segs=10)
    grod(rails, (x0 + 0.05, y + 1.07, z1 - 0.03), (x1 - 0.05, y + 1.07, z1 - 0.03), 0.021, segs=10)
    grod(rails, (x0 + 0.05, y + 0.55, z1 - 0.03), (x1 - 0.05, y + 0.55, z1 - 0.03), 0.017, segs=10)
    gbox_span(rails, (x0 + 0.05, y, z1 - 0.04), (x1 - 0.05, y + 0.1, z1 - 0.03))
    # Rail across the closed infeed end; a stair down from the head end (in the outer part of
    # the walkway, clear of the haul-out drive motor).
    grod(rails, (x0 + 0.05, y + 1.07, z0 + 0.05), (x0 + 0.05, y + 1.07, z1 - 0.03), 0.021, segs=10)
    grod(rails, (x0 + 0.05, y + 0.55, z0 + 0.05), (x0 + 0.05, y + 0.55, z1 - 0.03), 0.017, segs=10)
    grod(rails, (x0 + 0.05, y, z0 + 0.05), (x0 + 0.05, y + 1.07, z0 + 0.05), 0.021, segs=10)
    stair(grate, rails, brackets, x1, y, STAIR_Z0, z1, 1.0)
    obj("CatwalkBrackets", brackets, coll, [M["green"]], bevel=0.003, segs=1)
    return obj("CatwalkGrating", grate, coll, [M["galv"]], bevel=0.0), obj("CatwalkRails", rails, coll, [M["yellow"]], bevel=0.003, segs=1)


# ---------------------------------------------------------------- drives

def sprocket_ring(bm, teeth, r_pitch, roller_r, thickness, z, inner, mi=0):
    """Toothed plate in the Godot XY plane, centred on the local origin."""
    outline = []
    r_root = r_pitch - roller_r * 0.9
    r_tip = r_pitch + roller_r * 1.4
    for k in range(teeth):
        a0 = 2 * math.pi * k / teeth
        half = math.pi / teeth
        for frac, r in ((-0.6, r_root), (-0.25, r_pitch), (-0.1, r_tip), (0.1, r_tip), (0.25, r_pitch), (0.6, r_root)):
            outline.append((a0 + frac * half, r))
    ring = []
    for a, r in outline:
        c, s = math.cos(a), math.sin(a)
        ring.append([bm.verts.new(G(r * c, r * s, z - thickness / 2)), bm.verts.new(G(r * c, r * s, z + thickness / 2)),
                     bm.verts.new(G(inner * c, inner * s, z + thickness / 2)), bm.verts.new(G(inner * c, inner * s, z - thickness / 2))])
    faces = []
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        for i in range(4):
            j = (i + 1) % 4
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mi
            faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)


def shaft_assembly(coll, M, name, x, y, strands, spr, teeth, roller_r, length, hub_r=0.09):
    """Shaft + keyed sprockets, origin on the shaft axis so the game can spin it about Z."""
    bm = bmesh.new()
    gcyl(bm, (0, 0, 0), 0.05, length, 'z', mi=0, segs=20)
    for z in strands:
        sprocket_ring(bm, teeth, spr, roller_r, 0.03, z, hub_r - 0.005, mi=1)   # bore sits on the hub
        gcyl(bm, (0, 0, z), hub_r, 0.09, 'z', mi=0, segs=16)
    return obj(name, bm, coll, [M["shaft"], M["chain"]], bevel=0.002, segs=1, loc=(x, y, 0))


def pillow_block(bm, x, y, z, base_down=True):
    """Bearing housing on a base, bolted. Base underneath the shaft when base_down."""
    sgn = -1 if base_down else 1
    gbox(bm, (x, y + sgn * 0.06, z), (0.26, 0.05, 0.1))
    gcyl(bm, (x, y, z), 0.085, 0.09, 'z', segs=20)
    for dx in (-0.1, 0.1):
        gcyl(bm, (x + dx, y + sgn * 0.04, z), 0.012, 0.11, 'z', segs=6)


def build_drives(coll, M):
    parts = [
        shaft_assembly(coll, M, "TopDriveShaft", TOP_X_HEAD, TOP_SHAFT_Y, TOP_STRANDS, TOP_SPR, TOP_TEETH, 0.022, 2 * COL_Z + 0.3),
        shaft_assembly(coll, M, "TopTailShaft", TOP_X_TAIL, TOP_SHAFT_Y, TOP_STRANDS, TOP_SPR, TOP_TEETH, 0.022, 2 * COL_Z + 0.3),
        shaft_assembly(coll, M, "HaulDriveShaft", HAUL_X_HEAD, HAUL_SHAFT_Y, HAUL_STRANDS, HAUL_SPR, HAUL_TEETH, 0.015, 2 * HAUL_HALF, 0.07),
        shaft_assembly(coll, M, "HaulTailShaft", HAUL_X_TAIL, HAUL_SHAFT_Y, HAUL_STRANDS, HAUL_SPR, HAUL_TEETH, 0.015, 2 * HAUL_HALF, 0.07),
    ]
    bm = bmesh.new()      # grey machinery
    bmy = bmesh.new()     # yellow guards
    bmg = bmesh.new()     # green brackets
    # Overhead shafts: pillow blocks on brackets cantilevered off the end columns.
    bz = COL_Z - 0.1
    for x, col_x in ((TOP_X_HEAD, X_END - 0.05), (TOP_X_TAIL, X_START + 0.05)):
        toward = 1 if col_x < x else -1
        face = col_x + toward * 0.1
        far = x + toward * 0.15
        for z in (-bz, bz):
            pillow_block(bm, x, TOP_SHAFT_Y, z)
            base_bottom = TOP_SHAFT_Y - 0.085
            gbox_span(bmg, (min(face, far), base_bottom - 0.05, z - 0.08), (max(face, far), base_bottom, z + 0.08))
            gbeam(bmg, (face, base_bottom - 0.4, z), (far, base_bottom - 0.05, z), 0.06, 0.06)            # gusset
    # Haul shafts: pillow blocks on floor pedestals.
    for x in (HAUL_X_HEAD, HAUL_X_TAIL):
        for z in (-(HAUL_HALF - 0.2), HAUL_HALF - 0.2):
            pillow_block(bm, x, HAUL_SHAFT_Y, z)
            gbox_span(bmg, (x - 0.15, 0.0, z - 0.08), (x + 0.15, HAUL_SHAFT_Y - 0.085, z + 0.08))
    # Overhead head drive: shaft-mounted gearbox and motor on a braced bracket off the end
    # column, on the side away from the catwalk.
    gx, gz = TOP_X_HEAD, -(COL_Z + 0.45)
    plate_top = TOP_SHAFT_Y - 0.4
    gbox_span(bmg, (gx - 0.35, plate_top - 0.05, -(COL_Z + 1.05)), (X_END + 0.05, plate_top, -(COL_Z + 0.1)))
    gbeam(bmg, (X_END - 0.05, plate_top - 0.9, -(COL_Z + 0.1)), (X_END - 0.05, plate_top - 0.05, -(COL_Z + 0.95)), 0.07, 0.07)
    gbox(bm, (gx, plate_top + 0.275, gz), (0.42, 0.55, 0.36))
    gcyl(bm, (gx, TOP_SHAFT_Y, gz + 0.24), 0.11, 0.16, 'z', segs=20)                                     # coupling to shaft end
    gcyl(bm, (gx + 0.05, plate_top + 0.16, gz - 0.40), 0.16, 0.45, 'z', segs=24)                         # motor body
    for k in range(10):
        a = 2 * math.pi * k / 10
        gbox(bm, (gx + 0.05 + 0.165 * math.cos(a), plate_top + 0.16 + 0.165 * math.sin(a), gz - 0.40), (0.02, 0.02, 0.4))
    gbox(bm, (gx + 0.05, plate_top + 0.355, gz - 0.40), (0.14, 0.1, 0.16))
    # Haul-out drive on the shaft end, on its own floor plate.
    hx, hz = HAUL_X_HEAD, HAUL_HALF + 0.16
    gbox(bm, (hx, HAUL_SHAFT_Y + 0.05, hz), (0.4, 0.5, 0.34))
    gcyl(bm, (hx + 0.05, 0.16, hz + 0.37), 0.14, 0.4, 'z', segs=24)
    gbox_span(bmg, (hx - 0.3, 0.0, hz - 0.25), (hx + 0.3, HAUL_SHAFT_Y + 0.05 - 0.25, hz + 0.65))
    # Sprocket guards: outer side of each overhead sprocket, strapped to the end column's cross beam.
    # At the tail the guard stops above the board path so boards pass beneath it.
    for x, outward, col_x, sweep in ((TOP_X_HEAD, 1.0, X_END - 0.05, 180), (TOP_X_TAIL, -1.0, X_START + 0.05, 125)):
        for z in TOP_STRANDS:
            r = GUARD_R
            arc = [(x + outward * r * math.sin(math.radians(a)), TOP_SHAFT_Y + r * math.cos(math.radians(a))) for a in range(0, sweep + 1, 5)]
            for side in (-1, 1):
                zz = z + side * 0.1
                L.add_prism(bmy, [(x, TOP_SHAFT_Y)] + arc, -(zz + 0.004), -(zz - 0.004))
            for k in range(len(arc) - 1):
                a, b = Vector(arc[k]), Vector(arc[k + 1])
                mid, d = (a + b) / 2, (b - a) * 0.56
                gbeam(bmy, (*(mid - d), z), (*(mid + d), z), 0.208, 0.006)
            band_y = TOP_SHAFT_Y + math.sqrt(max(r * r - (col_x - x) ** 2, 0.0))
            gbox_span(bmy, (col_x - 0.03, band_y - 0.01, z - 0.104), (col_x + 0.03, CROSS_BOTTOM, z + 0.104))
    obj("Drives", bm, coll, [M["grey"]], bevel=0.004)
    guards = L.make_object("ChainGuards", bmy, coll, [M["yellow"]], weighted=False)
    guards.data.shade_flat()
    obj("DriveBrackets", bmg, coll, [M["green"]], bevel=0.003, segs=1)
    return parts


def hoist_x(i):
    """Each bay's hoist hangs under the cross beam at its upstream boundary, just
    downstream of the chain-track hangers."""
    return bay_x(i) + 0.06


HOIST_Y = 5.75
DRUM_R = 0.065


def build_hoists(coll, M):
    """One hoist per bay so every carriage indexes independently."""
    bm = bmesh.new()
    for i in range(NB):
        x = hoist_x(i)
        gcyl(bm, (x, HOIST_Y, 0.0), 0.025, 2 * END_BLOCK_Z + 0.16, 'z', segs=12)                 # cross shaft
        for z in (-END_BLOCK_Z, END_BLOCK_Z):
            gcyl(bm, (x, HOIST_Y, z), DRUM_R, 0.12, 'z', segs=20)                                 # cable drum
            for dz in (-0.07, 0.07):
                gcyl(bm, (x, HOIST_Y, z + dz), DRUM_R + 0.008, 0.012, 'z', segs=20)                # drum flanges
        for z in (-2.6, -0.7, 0.7, 2.6):                                                          # hanger bearings
            gbox(bm, (x, HOIST_Y + 0.02, z), (0.09, 0.07, 0.09))
            gbox_span(bm, (x - 0.08, HOIST_Y + 0.055, z - 0.06), (x + 0.08, CROSS_BOTTOM, z + 0.06))
        gz = -2.2                                                                                 # gearmotor
        gbox(bm, (x, HOIST_Y - 0.05, gz), (0.18, 0.2, 0.16))
        gcyl(bm, (x + 0.2, HOIST_Y - 0.08, gz), 0.07, 0.22, 'x', segs=16)
        gbox_span(bm, (x - 0.03, HOIST_Y + 0.05, gz - 0.03), (x + 0.03, CROSS_BOTTOM, gz + 0.03))    # torque arm
    return obj("Hoists", bm, coll, [M["grey"]], bevel=0.003, segs=1)


def build_end_table(coll, M):
    bm = bmesh.new()
    bmu = bmesh.new()
    x0, x1 = TABLE_X0, HAUL_X_HEAD + 0.3
    # Drag-chain channels: the carrying run slides on the top strip, the return run on the lower one.
    c0, c1 = HAUL_X_TAIL + HAUL_SPR + 0.08, HAUL_X_HEAD - HAUL_SPR - 0.08
    strip_top = HAUL_TOP - 0.024
    ret_top = HAUL_SHAFT_Y - HAUL_SPR - 0.012
    for z in HAUL_STRANDS:
        gbox_span(bm, (c0, 0.0, z - 0.09), (c1, strip_top + 0.02, z - 0.07))
        gbox_span(bm, (c0, 0.0, z + 0.07), (c1, strip_top + 0.02, z + 0.09))
        gbox_span(bm, (c0, 0.0, z - 0.09), (c1, 0.01, z + 0.09))
        gbox_span(bmu, (c0, strip_top - 0.02, z - 0.07), (c1, strip_top, z + 0.07))
        gbox_span(bmu, (c0, ret_top - 0.02, z - 0.07), (c1, ret_top, z + 0.07))
        gbox_span(bm, (c0, 0.01, z - 0.02), (c1, ret_top - 0.02, z + 0.02))                       # return strip web
    for x in [x0 + k * 1.2 for k in range(int((x1 - x0) / 1.2) + 1)]:
        if x < c1:
            gbox_span(bm, (x - 0.05, 0.0, -2.0), (x + 0.05, 0.08, 2.0))
    for z in (-2.55, 2.55):
        gbox_span(bm, (x0, 0.0, z - 0.06), (HAUL_X_HEAD - 0.35, 0.25, z + 0.06))
    # No end stops: stacks run on over the head sprocket onto the green stacker's surge chains
    # (dev/blender/green_stacker), whose tail sprockets reach in between the haul strands.
    obj("EndTable", bm, coll, [M["green"]], bevel=0.004)
    obj("HaulWearStrips", bmu, coll, [M["uhmw"]], bevel=0.0)


# ---------------------------------------------------------------- moving parts

def build_gate(coll, M):
    """One drop gate: tapered arms keyed to a cross shaft, levers at the cylinder lines.

    Origin on the shaft axis, arms extending +X. The arm tops sit -GATE_AXIS_DY above
    the axis, so as the gate drops nothing rises above the deck plane.
    """
    bm = bmesh.new()
    top = -GATE_AXIS_DY
    flange = top - WEAR_T
    gcyl(bm, (0.0, 0.0, 0.0), 0.03, 2 * GATE_SHAFT_HALF, 'z', mi=2, segs=16)
    for z in GATE_ARM_Z:
        # Web plate deep at the hub, tapering to the tip; flat bar flange on top under the UHMW cap.
        L.add_prism(bm, [(0.0, flange - 0.01), (GATE_W, flange - 0.01), (GATE_W, top - 0.045), (0.25, -0.03), (0.0, -0.03)],
                    -z - 0.01, -z + 0.01)
        gbox_span(bm, (0.0, flange - 0.01, z - RAIL_W / 2), (GATE_W, flange, z + RAIL_W / 2))
        gbox_span(bm, (0.0, flange, z - RAIL_W / 2), (GATE_W, top, z + RAIL_W / 2), mi=1)
        gcyl(bm, (0.0, 0.0, z), 0.045, 0.06, 'z', segs=16)                                         # hub, keyed to the shaft
    for z in (-GATE_CYL_Z, GATE_CYL_Z):
        gcyl(bm, (0.0, 0.0, z), 0.045, 0.06, 'z', segs=16)
        gbeam(bm, (0.0, 0.0, z), GATE_LEVER_PIN + (z,), 0.02, 0.05)                                # lever
        gcyl(bm, GATE_LEVER_PIN + (z,), 0.015, 0.06, 'z', mi=2, segs=8)
    return obj("Gate", bm, coll, [M["orange"], M["uhmw"], M["shaft"]], bevel=0.003, segs=1)


GATE_LEVER_PIN = (0.095, -0.07)      # cylinder rod pin on the gate lever, gate-local (x, y)


def gate_pin_world(i, angle_deg):
    """Lever pin position with the gate swung down by angle_deg."""
    a = math.radians(angle_deg)
    lx, ly = GATE_LEVER_PIN
    x = lx * math.cos(a) + ly * math.sin(a)
    y = -lx * math.sin(a) + ly * math.cos(a)
    return bay_x(i) + GATE_X0 + x, DECK_Y + GATE_AXIS_DY + y


def gate_anchor_world(i):
    return bay_x(i + 1) - 0.035, DECK_Y - 0.15


def build_carriage(coll, M):
    """Fork carriage. Origin at the tine tops, upstream end of the tines (bay x + CARRIAGE_X)."""
    bm = bmesh.new()
    bms = bmesh.new()
    for z in TINE_Z:
        L.add_prism(bm, [(0.0, -0.07), (0.72, -0.03), (0.77, 0.0), (0.0, 0.0)], -z - 0.04, -z + 0.04)
        gbox_span(bm, (-0.08, -0.07, z - 0.045), (0.0, HANG_H, z + 0.045))
        gbeam(bm, (0.0, HANG_H - 0.25, z), (-0.06, 0.08, z), 0.04, 0.03)
    gbox_span(bm, (-0.09, HANG_H, -END_BLOCK_Z), (0.03, HANG_H + 0.14, END_BLOCK_Z))
    for sgn in (-1, 1):
        z = sgn * END_BLOCK_Z
        gbox_span(bm, (-0.12, HANG_H - 0.2, z - 0.07), (0.06, HANG_H + 0.24, z + 0.07))
        # Guide rollers (axles along X) run on the inner face of the column flange; the upper
        # one stays under the deck supports even at the catch height.
        roll_z = sgn * (COL_Z - 0.100 - 0.041)      # flange inner face at COL_Z - 0.1, 1 mm running clearance
        for dy in (HANG_H - 0.12, HANG_H + 0.10):
            gcyl(bms, (-0.15, dy, roll_z), 0.04, 0.05, 'x', segs=14)
            gbox_span(bms, (-0.19, dy - 0.015, min(z, roll_z)), (-0.11, dy + 0.015, max(z, roll_z)))
        # Cable shackle directly under the drum's cable line.
        sx = hoist_x(0) + DRUM_R - bay_x(0) - CARRIAGE_X
        gbox_span(bms, (sx - 0.025, HANG_H + 0.24, z - 0.03), (sx + 0.025, HANG_H + 0.30, z + 0.03))
    return obj("Carriage", bm, coll, [M["orange"]], bevel=0.004), obj("CarriageRollers", bms, coll, [M["shaft"]], bevel=0.0)


def cable_x(i):
    return hoist_x(i) + DRUM_R


def add_chain_link(bm, mi=0, lug=False):
    """Roller chain link, game convention: origin on pin 1, +X to pin 2, +Z along the pin.

    The extended pins carry outboard rollers that ride the working-run track lips.
    """
    p = TOP_PITCH
    for side in (-1, 1):
        z = side * 0.022
        L.add_prism(bm, [(-0.02, -0.015), (p + 0.02, -0.015), (p + 0.02, 0.015), (-0.02, 0.015)],
                    -(z + 0.004), -(z - 0.004), mat_index=mi)
    gcyl(bm, (0.0, 0.0, 0.0), ROLLER_R, 0.036, 'z', mi=mi, segs=10)
    gcyl(bm, (0.0, 0.0, 0.0), 0.007, 2 * (OUT_ROLLER_Z + 0.01), 'z', mi=mi, segs=6)
    for side in (-1, 1):
        gcyl(bm, (0.0, 0.0, side * OUT_ROLLER_Z), OUT_ROLLER_R, 0.014, 'z', mi=mi, segs=10)
    if lug:
        # Pusher lug hanging toward the deck on the working run (local -Y), hung from
        # extended side plates outside the tooth plane, clear of the track lips.
        for side in (-1, 1):
            gbox_span(bm, (p * 0.2, -0.065, side * 0.028 - 0.003), (p * 0.6, -0.008, side * 0.028 + 0.003), mi)
        gbox_span(bm, (p * 0.25, -LUG_LEN, -0.026), (p * 0.55, -0.058, 0.026), mi)   # welded between the plates
        gbox_span(bm, (p * 0.25, -LUG_LEN, -0.05), (p * 0.6, -LUG_LEN + 0.12, 0.05), mi)


def build_chain_parts(coll, M):
    parts = {}
    for name, lug in (("TopChainLink", False), ("TopChainLug", True)):
        bm = bmesh.new()
        add_chain_link(bm, 0, lug)
        parts[name] = obj(name, bm, coll, [M["chain"] if not lug else M["orange"]], bevel=0.0)
    bm = bmesh.new()
    p = HAUL_PITCH
    for side in (-1, 1):
        z = side * 0.016
        L.add_prism(bm, [(-0.012, -0.012), (p + 0.012, -0.012), (p + 0.012, 0.012), (-0.012, 0.012)], -(z + 0.003), -(z - 0.003))
    gcyl(bm, (0, 0, 0), 0.012, 0.026, 'z', segs=8)
    parts["HaulChainLink"] = obj("HaulChainLink", bm, coll, [M["chain"]], bevel=0.0)
    # Transfer chain: smooth-top roller chain, plates reach 8 mm above the pins.
    bm = bmesh.new()
    p = XFER_PITCH
    for side in (-1, 1):
        z = side * 0.0095
        L.add_prism(bm, [(-0.006, -0.008), (p + 0.006, -0.008), (p + 0.006, 0.008), (-0.006, 0.008)], -(z + 0.0015), -(z - 0.0015))
    gcyl(bm, (0, 0, 0), XFER_ROLLER_R, 0.016, 'z', segs=8)
    parts["TransferChainLink"] = obj("TransferChainLink", bm, coll, [M["chain"]], bevel=0.0)
    return parts


# ---------------------------------------------------------------- chain paths

def top_path(s, total):
    span = TOP_X_HEAD - TOP_X_TAIL
    arc = math.pi * TOP_SPR
    s %= total
    if s < span:
        return Vector((TOP_X_TAIL + s, Y_LOW))
    s -= span
    if s < arc:
        phi = -math.pi / 2 + s / TOP_SPR
        return Vector((TOP_X_HEAD + TOP_SPR * math.cos(phi), TOP_SHAFT_Y + TOP_SPR * math.sin(phi)))
    s -= arc
    if s < span:
        return Vector((TOP_X_HEAD - s, Y_RET))
    s -= span
    phi = math.pi / 2 + s / TOP_SPR
    return Vector((TOP_X_TAIL + TOP_SPR * math.cos(phi), TOP_SHAFT_Y + TOP_SPR * math.sin(phi)))


def haul_path(s, total):
    span = HAUL_X_HEAD - HAUL_X_TAIL
    arc = math.pi * HAUL_SPR
    s %= total
    if s < span:
        return Vector((HAUL_X_TAIL + s, HAUL_SHAFT_Y + HAUL_SPR))
    s -= span
    if s < arc:
        phi = math.pi / 2 - s / HAUL_SPR
        return Vector((HAUL_X_HEAD + HAUL_SPR * math.cos(phi), HAUL_SHAFT_Y + HAUL_SPR * math.sin(phi)))
    s -= arc
    if s < span:
        return Vector((HAUL_X_HEAD - s, HAUL_SHAFT_Y - HAUL_SPR))
    s -= span
    phi = -math.pi / 2 - s / HAUL_SPR
    return Vector((HAUL_X_TAIL + HAUL_SPR * math.cos(phi), HAUL_SHAFT_Y + HAUL_SPR * math.sin(phi)))


def xfer_path(s, total):
    """Transfer chain loop from the tail's top tangent: carrying run +X, head wrap, return
    run -X underneath, tail wrap."""
    span = XFER_HEAD - XFER_TAIL
    arc = math.pi * XFER_SPR
    s %= total
    if s < span:
        return Vector((XFER_TAIL + s, XFER_PIN_Y))
    s -= span
    if s < arc:
        phi = math.pi / 2 - s / XFER_SPR
        return Vector((XFER_HEAD + XFER_SPR * math.cos(phi), XFER_SHAFT_Y + XFER_SPR * math.sin(phi)))
    s -= arc
    if s < span:
        return Vector((XFER_HEAD - s, XFER_SHAFT_Y - XFER_SPR))
    s -= span
    phi = -math.pi / 2 - s / XFER_SPR
    return Vector((XFER_TAIL + XFER_SPR * math.cos(phi), XFER_SHAFT_Y + XFER_SPR * math.sin(phi)))


TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Godot (x, y, z) -> Blender (x, -z, y)


def link_matrix(p1, p2, z):
    """Godot link frame (X along chord, Z along pin), expressed for Blender-space link meshes."""
    d = (p2 - p1).normalized()
    gx = Vector((d.x, d.y, 0.0))
    gz = Vector((0.0, 0.0, 1.0))
    gy = gz.cross(gx)
    basis = Matrix((gx, gy, gz)).transposed()
    m = (TO_BLENDER @ basis @ TO_BLENDER.inverted()).to_4x4()
    m.translation = G(p1.x, p1.y, z)
    return m


def build_chain_preview(coll, M, parts, top_phase=0.0):
    """Place every link and lug along both loops so the renders show the real chains."""
    def place(src, mats, path, total, pitch, strands, every=None, name="Chains", phase=0.0):
        count = int(round(total / pitch))
        pitch = total / count
        bm = bmesh.new()
        me = src.data
        for k in range(count):
            if every and k % every:
                continue
            s = phase + k * pitch
            p1, p2 = path(s, total), path(s + pitch, total)
            for z in strands:
                m = link_matrix(p1, p2, z)
                start = len(bm.verts)
                bm.from_mesh(me)
                bm.verts.ensure_lookup_table()
                for v in bm.verts[start:]:
                    v.co = m @ v.co
        return L.make_object(name, bm, coll, mats, weighted=False)

    top_total = 2 * (TOP_X_HEAD - TOP_X_TAIL) + 2 * math.pi * TOP_SPR
    haul_total = 2 * (HAUL_X_HEAD - HAUL_X_TAIL) + 2 * math.pi * HAUL_SPR
    place(parts["TopChainLink"], [M["chain"]], top_path, top_total, TOP_PITCH, TOP_STRANDS, name="PreviewTopChain", phase=top_phase)
    place(parts["TopChainLug"], [M["orange"]], top_path, top_total, TOP_PITCH, TOP_STRANDS, every=LUG_EVERY, name="PreviewTopLugs", phase=top_phase)
    place(parts["HaulChainLink"], [M["chain"]], haul_path, haul_total, HAUL_PITCH, HAUL_STRANDS, name="PreviewHaulChain")
    xfer_total = 2 * (XFER_HEAD - XFER_TAIL) + 2 * math.pi * XFER_SPR
    place(parts["TransferChainLink"], [M["chain"]], xfer_path, xfer_total, XFER_PITCH, XFER_Z, name="PreviewTransferChain")
    for src in parts.values():
        src.hide_render = True
        src.location = G(0, -5, 0)


# ---------------------------------------------------------------- assembly

def build(materials, top_phase=0.0):
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    parts_coll = L.collection("SorterParts", coll)
    build_frame(coll, materials)
    build_deck(coll, materials)
    build_infeed(coll, materials)
    build_chain_supports(coll, materials)
    build_catwalk(coll, materials)
    build_drives(coll, materials)
    build_hoists(coll, materials)
    build_end_table(coll, materials)
    gate = build_gate(parts_coll, materials)
    carriage, rollers = build_carriage(parts_coll, materials)
    chain_parts = build_chain_parts(parts_coll, materials)
    build_chain_preview(coll, materials, chain_parts, top_phase)
    for src in (gate, carriage, rollers):
        src.hide_render = True
        src.location = G(0, -5, 0)
    return {"objects": len(coll.all_objects)}
