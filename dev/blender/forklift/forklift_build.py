"""The mill's big forklift, modelled after the user's photos of the yard truck (a Hyster 230,
unit 4). Run inside Blender. Clean paint: the photos' dust, rust and peeling are left out.

Sized from the side photo against the 2.85 m wheelbase: 3.9 m from the counterweight to the
fork faces, 2.3 m over the body, 2.9 m to the cab roof, a 3.45 m lowered mast.

What the photos show, and this builds:
- big single drive tyres (0.55 m radius) and smaller steer tyres (0.50 m) with slanted lugs on
  light grey disc rims; the steer tyres stick out behind the counterweight;
- yellow body: a wide counterweight / engine hood behind the cab whose outer corners arch over
  the steer tyres (the lower counterweight between them is narrower), rounded rear corners,
  lamp clusters at the top rear corners, a dark recess and a tow-pin slot in the rear face; a
  dark grey vented hood hump behind the cab, an intake pipe behind the cab and an exhaust stack
  at its right rear corner;
- flat yellow fender decks over the drive tyres joined by the deck in front of the cab, slanted
  fender wings behind the drive tyres and in front of the steer tyres, and between them on both
  sides a step well with three silver treads (the middle one on a yellow box);
- a charcoal enclosed cab with a raked windshield, doors with an upper and a lower window, slim
  rear side windows, a flat roof and work lights at its rear corners;
- a dark grey two-stage mast: outer channels with a top header carrying the work lights, the
  lift cylinders behind them, inner channels with a crosshead and the two chains near the
  middle, tilt cylinders from the deck beside the cab up to the mast;
- a full-width dark carriage (no backrest) with the fork positioner cylinders on top and long
  dark steel hook-on forks.

Forklift-local frame, Godot axes: +X forward (toward the forks), +Y up, +Z to the left;
origin on the ground under the middle of the drive axle. Moving parts are separate objects:
ForkliftMastInner (+ ForkliftMastInnerParts), ForkliftCarriage (ForkliftForkL/R children,
spread in Z), ForkliftDriveWheelL/R, ForkliftSteerWheelL/R (origin on the axle, spin about Z).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "bin_sorter"))
import mesh_lib as L  # noqa: E402
import sorter_build as S  # noqa: E402

G, gbox, gbox_span, gcyl, grod, gbeam, obj = S.G, S.gbox, S.gbox_span, S.gcyl, S.grod, S.gbeam, S.obj

COLL = "Forklift"
CUTTERS = "ForkliftCutters"
STUDIO = "ForkliftStudio"             # the forklift's own scene, apart from the mill scene
INCH = 0.0254

WHEELBASE = 2.85
TYRE_R = 0.55                         # drive tyres; forklift.gd uses the same radius
STEER_R = 0.50
TYRE_W = 0.34
DRIVE_Z = 0.96                        # tyre centre lines
STEER_Z = 0.90
BODY_HALF = 1.13
FORK_FACE_X = 0.70
REAR_X = -3.20
DECK_Y0, DECK_Y1 = 1.16, 1.24         # fender decks and the deck in front of the cab
HOOD_TOP = 1.64
CAB_X0, CAB_XF, CAB_XF_TOP = -1.74, -0.52, -0.80
CAB_HALF = 0.68
CAB_TOP = 2.92
BELT = 1.72                           # cab window line
MAST_X = 0.42
MAST_HALF = 0.50                      # outer channel centres
INNER_HALF = 0.37
MAST_LOW_TOP = 3.45
FORK_LEN = 72 * INCH
FORK_T = 0.08
FORK_W = 0.20
FORK_SHANK_H = 1.10
FORK_SPREAD = 1.05
CARRIAGE_HALF = 1.20
CARRIAGE_X = FORK_FACE_X - 0.10
STEER_ARCH_R = STEER_R + 0.10


# ---------------------------------------------------------------- materials

def _principled(name, base, rough, metal=0.0, coat=0.0, alpha=1.0, emission=None, bump=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    b.inputs["Base Color"].default_value = (*base, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.08
    b.inputs["Alpha"].default_value = alpha
    if emission is not None:
        b.inputs["Emission Color"].default_value = (*emission, 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    if bump > 0:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 180.0
        bn = nt.nodes.new("ShaderNodeBump")
        bn.inputs["Strength"].default_value = bump
        nt.links.new(tex.outputs["Fac"], bn.inputs["Height"])
        nt.links.new(bn.outputs["Normal"], b.inputs["Normal"])
    m.diffuse_color = (*base, alpha)
    m.metallic = metal
    m.roughness = rough
    if alpha < 1.0:
        m.surface_render_method = 'BLENDED'
    return m


def materials(M):
    M["yellow"] = _principled("Forklift_Yellow", (0.78, 0.58, 0.035), 0.38, coat=0.25)
    M["cab"] = _principled("Forklift_Charcoal", (0.030, 0.032, 0.035), 0.5, coat=0.15)
    M["mast"] = _principled("Forklift_MastGrey", (0.045, 0.045, 0.047), 0.55)
    M["fork"] = _principled("Forklift_ForkSteel", (0.07, 0.07, 0.07), 0.5, metal=0.3)
    M["tyre"] = _principled("Forklift_Tyre", (0.010, 0.010, 0.010), 0.85, bump=0.15)
    M["rim"] = _principled("Forklift_Rim", (0.36, 0.36, 0.34), 0.5, metal=0.2)
    M["tread"] = _principled("Forklift_Tread", (0.40, 0.40, 0.40), 0.4, metal=0.6, bump=0.3)
    M["glass"] = _principled("Forklift_Glass", (0.10, 0.13, 0.14), 0.05, alpha=0.35)
    M["lamp"] = _principled("Forklift_Lamp", (0.95, 0.95, 0.92), 0.05, emission=(1.0, 0.97, 0.9))
    M["amber"] = _principled("Forklift_Amber", (1.0, 0.45, 0.02), 0.1, emission=(1.0, 0.4, 0.02))
    M["red_lamp"] = _principled("Forklift_RedLamp", (0.7, 0.02, 0.01), 0.1, emission=(0.6, 0.0, 0.0))
    M["chain"] = _principled("Forklift_Chain", (0.10, 0.09, 0.08), 0.5, metal=0.5)
    M["rod"] = _principled("Forklift_Rod", (0.70, 0.70, 0.70), 0.15, metal=0.9)
    M["black"] = _principled("Forklift_Black", (0.006, 0.006, 0.006), 0.6)
    M["navy"] = _principled("Forklift_Navy", (0.010, 0.014, 0.035), 0.4)
    M["decal_red"] = _principled("Forklift_DecalRed", (0.45, 0.015, 0.02), 0.4)
    return M


# ---------------------------------------------------------------- shape helpers

def _finish(o, bevel_w, segs=8):
    md = o.modifiers.new("Bevel", 'BEVEL')
    md.width = bevel_w
    md.segments = segs
    md.limit_method = 'WEIGHT'
    md.harden_normals = True
    md.use_clamp_overlap = True
    md.miter_outer = 'MITER_ARC'
    return md


def rbox(name, coll, mat, x0, x1, y0, y1, z0, z1, rv_back=0.0, rv_front=0.0, r_top=0.0,
         r_top_back=None, r_top_front=None, r_bot=0.0, segs=8):
    """Block from (x0,y0,z0) to (x1,y1,z1) whose edges carry their own radius: vertical edges
    at the back (rv_back) and front (rv_front), top edges along X (r_top), top edges across
    at the back/front, bottom edges (r_bot)."""
    r_top_back = r_top if r_top_back is None else r_top_back
    r_top_front = r_top if r_top_front is None else r_top_front
    me = bpy.data.meshes.new(name)
    vs, idx = [], {}
    for ix, x in ((0, x0), (1, x1)):
        for iy, y in ((0, y0), (1, y1)):
            for iz, z in ((0, z0), (1, z1)):
                idx[(ix, iy, iz)] = len(vs)
                vs.append(G(x, y, z))
    q = lambda a, b, c, d: (idx[a], idx[b], idx[c], idx[d])  # noqa: E731
    faces = [q((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)), q((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)),
             q((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)), q((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)),
             q((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)), q((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))]
    me.from_pydata(vs, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    inv = {v: k for k, v in idx.items()}
    radii = []
    for e in me.edges:
        a, b = inv[e.vertices[0]], inv[e.vertices[1]]
        if a[1] != b[1]:
            r = rv_back if a[0] == 0 else rv_front
        elif a[0] != b[0]:
            r = r_top if a[1] == 1 else r_bot
        else:
            r = (r_top_back if a[0] == 0 else r_top_front) if a[1] == 1 else r_bot
        radii.append(r)
    rmax = max(max(radii), 1e-4)
    att = me.attributes.get("bevel_weight_edge") or me.attributes.new("bevel_weight_edge", 'FLOAT', 'EDGE')
    for i, r in enumerate(radii):
        att.data[i].value = r / rmax
    me.materials.append(mat)
    me.shade_smooth()
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    _finish(o, rmax, segs)
    return o


def side_prism(bm, pts, za, zb):
    """Polygon in the side view (Godot x, y) extruded across Godot z from za to zb."""
    L.add_prism(bm, pts, -max(za, zb), -min(za, zb))


def both_sides(bm, pts, za, zb):
    side_prism(bm, pts, za, zb)
    side_prism(bm, pts, -za, -zb)


def cutter_cyl(name, x, y, z0, z1, r):
    coll = L.collection(CUTTERS, bpy.data.collections[COLL])
    bm = bmesh.new()
    gcyl(bm, (x, y, (z0 + z1) / 2), r, abs(z1 - z0), 'z', segs=64)
    o = L.make_object(name, bm, coll, [], weighted=False)
    o.hide_render = True
    o.display_type = 'WIRE'
    return o


def cutter_box(name, p0, p1):
    coll = L.collection(CUTTERS, bpy.data.collections[COLL])
    bm = bmesh.new()
    gbox_span(bm, p0, p1)
    o = L.make_object(name, bm, coll, [], weighted=False)
    o.hide_render = True
    o.display_type = 'WIRE'
    return o


def cut(o, cutter):
    md = o.modifiers.new("Cut_" + cutter.name, 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.solver = 'EXACT'
    md.object = cutter
    # Boolean before the bevel, so the arch edge is rounded too.
    o.modifiers.move(len(o.modifiers) - 1, 0)


def text(name, coll, mat, body, loc, rot, size, extrude=0.003, align='CENTER'):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = 'CENTER'
    font = bpy.data.fonts.get("Arial Black") or _font()
    if font is not None:
        cu.font = font
    o = bpy.data.objects.new(name, cu)
    coll.objects.link(o)
    o.data.materials.append(mat)
    o.location = G(*loc)
    o.rotation_euler = [math.radians(a) for a in rot]
    return o


def _font():
    for path in ("C:/Windows/Fonts/ariblk.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(path):
            return bpy.data.fonts.load(path, check_existing=True)
    return None


def side_text(name, coll, mat, body, x, y, size, side):
    """Lettering on a body side (side +1 = left, +Z), reading front-to-back like the real decals
    on the left and back-to-front on the right, i.e. upright and readable from outside."""
    z = side * (BODY_HALF + 0.002)
    rot = (90, 0, 0) if side > 0 else (90, 0, 180)
    return text(name, coll, mat, body, (x, y, z), rot, size)


# ---------------------------------------------------------------- body

def build_body(coll, M):
    y_mat, c_mat = M["yellow"], M["cab"]
    sx = -WHEELBASE
    # Counterweight / engine hood: full width above the steer tyres, arched over them, big
    # rounded rear corners; it runs forward to the cab's back wall.
    cw = rbox("ForkliftCounterweight", coll, y_mat, REAR_X, CAB_X0 + 0.02, 0.70, HOOD_TOP, -BODY_HALF, BODY_HALF,
              rv_back=0.42, rv_front=0.02, r_top=0.06, r_top_back=0.20, r_top_front=0.02, r_bot=0.02)
    for s, tag in ((-1, "R"), (1, "L")):
        cut(cw, cutter_cyl("ArchRear" + tag, sx, STEER_R, s * (STEER_Z - TYRE_W / 2 - 0.06), s * (BODY_HALF + 0.3),
                           STEER_ARCH_R))
        # Ahead of the arch the hood only comes down to the deck: the fender wing and the step
        # well are below it.
        cut(cw, cutter_box("HoodUnder" + tag, (-2.30, 0.0, s * 0.70), (-1.0, DECK_Y0, s * (BODY_HALF + 0.3))))
    # The lower counterweight between the steer tyres, narrower, down to the bumper line.
    rbox("ForkliftCounterweightLow", coll, y_mat, REAR_X, -2.05, 0.30, 0.80, -0.68, 0.68,
         rv_back=0.20, rv_front=0.02, r_bot=0.03)
    # Rear face details: dark recess panel across the top middle, lamp cluster housings at the
    # top corners, the tow-pin slot and the notch below it.
    bk = bmesh.new()
    gbox_span(bk, (REAR_X - 0.012, 1.30, -0.34), (REAR_X + 0.02, 1.50, 0.34))
    for s in (-1, 1):
        gbox_span(bk, (REAR_X - 0.016, 1.34, s * 0.42), (REAR_X + 0.02, 1.50, s * 0.69))
    gbox_span(bk, (REAR_X - 0.012, 0.48, -0.07), (REAR_X + 0.02, 0.95, 0.07))
    gbox_span(bk, (REAR_X - 0.012, 0.30, -0.30), (REAR_X + 0.02, 0.44, 0.30))
    obj("ForkliftRearRecesses", bk, coll, [c_mat], bevel=0.01, segs=2)
    # Lamp clusters: these sit on the rounded corners, so they're turned to face back-and-out.
    bl, ba, br = bmesh.new(), bmesh.new(), bmesh.new()
    for s in (-1, 1):
        for k, mesh in enumerate((bl, ba, br)):
            zc = s * (0.47 + 0.08 * k)
            gcyl(mesh, (REAR_X - 0.02, 1.42, zc), 0.035, 0.012, 'x', segs=20)
    obj("ForkliftRearWhite", bl, coll, [M["lamp"]], bevel=0.003, segs=2)
    obj("ForkliftRearAmber", ba, coll, [M["amber"]], bevel=0.003, segs=2)
    obj("ForkliftRearRed", br, coll, [M["red_lamp"]], bevel=0.003, segs=2)
    bp = bmesh.new()
    grod(bp, (REAR_X + 0.01, 0.50, 0.0), (REAR_X + 0.01, 0.82, 0.0), 0.025, segs=12)
    obj("ForkliftTowPin", bp, coll, [M["rod"]], bevel=0.0)
    # Dark vented hood hump behind the cab, with its slots.
    rbox("ForkliftHoodHump", coll, c_mat, -2.95, -1.80, HOOD_TOP - 0.02, HOOD_TOP + 0.13, -0.52, 0.52,
         rv_back=0.14, rv_front=0.06, r_top=0.05)
    bv = bmesh.new()
    for k in range(4):
        x = -2.80 + k * 0.26
        for s in (-1, 1):
            gbox_span(bv, (x - 0.07, HOOD_TOP + 0.125, s * 0.08), (x + 0.07, HOOD_TOP + 0.14, s * 0.40))
    obj("ForkliftHoodSlots", bv, coll, [M["black"]], bevel=0.003, segs=1)
    # Deck: the fender tops over the drive tyres and the deck in front of the cab, one plate
    # running back under the cab to the hood.
    rbox("ForkliftDeck", coll, y_mat, CAB_X0 + 0.01, 0.24, DECK_Y0, DECK_Y1, -BODY_HALF, BODY_HALF,
         rv_front=0.14, r_top=0.02, r_bot=0.01, segs=4)
    # Core of the frame between the tyres, under the deck.
    rbox("ForkliftFrame", coll, y_mat, -2.10, 0.22, 0.30, DECK_Y0, -0.74, 0.74, r_bot=0.02, rv_front=0.04)
    # Slanted fender wings: behind the drive tyres and in front of the steer tyres; their
    # outer faces are flush with the deck edge. Between them, a step well on each side.
    bw = bmesh.new()
    both_sides(bw, [(-0.58, DECK_Y0 + 0.01), (-0.40, DECK_Y0 + 0.01), (-0.72, 0.28), (-0.90, 0.28)], 0.74, BODY_HALF)
    both_sides(bw, [(-2.40, DECK_Y0 + 0.01), (-2.20, DECK_Y0 + 0.01), (-1.94, 0.28), (-2.12, 0.28)], 0.70, BODY_HALF)
    # Front lip of the drive-tyre fenders, turned down.
    for s in (-1, 1):
        gbox_span(bw, (0.17, DECK_Y0 - 0.10, s * 0.76), (0.24, DECK_Y0, s * BODY_HALF))
    obj("ForkliftFenderWings", bw, coll, [y_mat], bevel=0.012, segs=3)
    # Step wells: back wall, the middle step's box and the treads.
    bs = bmesh.new()
    for s in (-1, 1):
        gbox_span(bs, (-2.10, 0.30, s * 0.74), (-0.70, DECK_Y0, s * 0.92))
        gbox_span(bs, (-1.55, 0.32, s * 0.92), (-0.95, 0.62, s * 1.06))
        gbox_span(bs, (-2.06, 0.20, s * 0.74), (-0.82, 0.26, s * (BODY_HALF - 0.01)))
    obj("ForkliftStepWells", bs, coll, [y_mat], bevel=0.008, segs=2)
    bt = bmesh.new()
    for s in (-1, 1):
        for x0, x1, y, zo in ((-2.08, -0.84, 0.26, BODY_HALF), (-1.62, -0.88, 0.62, 1.10), (-1.12, -0.66, 0.94, 1.08)):
            gbox_span(bt, (x0, y, s * 0.92), (x1, y + 0.06, s * zo))
    obj("ForkliftStepTreads", bt, coll, [M["tread"]], bevel=0.006, segs=2)
    # Dark running gear seen under the body: drive axle housing, steer axle, frame bottom.
    bc = bmesh.new()
    gcyl(bc, (0.0, TYRE_R, 0.0), 0.16, 2 * (DRIVE_Z - TYRE_W / 2 - 0.02), 'z', segs=32)
    gbox_span(bc, (sx - 0.14, STEER_R - 0.08, -(STEER_Z - TYRE_W / 2 - 0.03)), (sx + 0.14, STEER_R + 0.10, STEER_Z - TYRE_W / 2 - 0.03))
    gbox_span(bc, (-2.6, 0.22, -0.62), (0.2, 0.32, 0.62))
    for s in (-1, 1):
        grod(bc, (sx + 0.12, STEER_R, s * 0.20), (sx + 0.12, STEER_R, s * (STEER_Z - 0.20)), 0.035, segs=10)
    obj("ForkliftRunningGear", bc, coll, [M["mast"]], bevel=0.01, segs=2)
    # Lettering and unit numbers.
    for s, tag in ((1, "L"), (-1, "R")):
        side_text("ForkliftDecalName" + tag, coll, M["navy"], "HYSTER", -2.06, 1.48, 0.15, s)
        side_text("ForkliftDecalModel" + tag, coll, M["decal_red"], "230", -1.90 if s > 0 else -2.22, 1.32, 0.12, s)
        side_text("ForkliftDecalUnit" + tag, coll, M["black"], "4", -2.85, 1.38, 0.20, s)
    text("ForkliftDecalUnitRear", coll, M["black"], "4", (REAR_X - 0.002, 1.12, 0.52), (90, 0, -90), 0.18)
    return cw


def build_cab(coll, M):
    """Charcoal cab on the deck: lower tub, raked windshield, doors with upper and lower
    windows, narrow rear side windows, a flat roof, work lights on the rear roof corners."""
    k = M["cab"]
    y0 = DECK_Y1
    ax = lambda y: CAB_XF - (y - 1.50) * (CAB_XF - CAB_XF_TOP) / (CAB_TOP - 0.08 - 1.50) if y > 1.50 else CAB_XF  # noqa: E731
    # Lower tub (below the window line), full width; its front drops to the windshield foot.
    bt = bmesh.new()
    side_prism(bt, [(CAB_X0, y0), (CAB_XF, y0), (CAB_XF, 1.50), (ax(BELT), BELT), (CAB_X0, BELT)], -CAB_HALF, CAB_HALF)
    obj("ForkliftCabTub", bt, coll, [k], bevel=0.02, segs=3)
    # Frame: rear posts, door posts, A-pillars, top rails, the rail at the window line, and the
    # roof.
    yt = CAB_TOP - 0.08
    bf = bmesh.new()
    for s in (-1, 1):
        z = s * CAB_HALF
        zi, zo = sorted((z - s * 0.06, z + s * 0.005))
        gbox_span(bf, (CAB_X0, BELT, zi), (CAB_X0 + 0.07, yt, zo))                      # rear post
        gbox_span(bf, (-1.36, BELT - 0.40, zi), (-1.30, yt, zo))                        # door rear post
        gbeam(bf, (ax(1.50) - 0.03, 1.50, z - s * 0.025), (ax(yt) - 0.03, yt, z - s * 0.025), 0.07, 0.06)   # A-pillar
        gbox_span(bf, (CAB_X0, yt - 0.06, zi), (ax(yt), yt, zo))                         # top rail
        gbox_span(bf, (CAB_X0, BELT - 0.02, zi), (ax(BELT), BELT + 0.04, zo))            # window-line rail
        # Lower door window frame.
        gbox_span(bf, (-1.24, 1.34, z), (-0.72, 1.38, z + s * 0.012))
        gbox_span(bf, (-1.24, 1.62, z), (-0.72, 1.66, z + s * 0.012))
        gbox_span(bf, (-1.24, 1.34, z), (-1.20, 1.66, z + s * 0.012))
        gbox_span(bf, (-0.76, 1.34, z), (-0.72, 1.66, z + s * 0.012))
        # Door handle and the vent grille on the rear side panel.
        gbox_span(bf, (-1.28, 1.80, z), (-1.18, 1.83, z + s * 0.03))
        for j in range(7):
            gbox_span(bf, (-1.62, 1.38 + j * 0.035, z), (-1.52, 1.395 + j * 0.035, z + s * 0.012))
    gbox_span(bf, (CAB_X0 - 0.005, yt - 0.06, -CAB_HALF), (CAB_X0 + 0.07, yt, CAB_HALF))   # rear header
    gbeam(bf, (ax(yt) - 0.03, yt - 0.03, -CAB_HALF), (ax(yt) - 0.03, yt - 0.03, CAB_HALF), 0.07, 0.06)  # windshield header
    gbox_span(bf, (CAB_X0 - 0.005, BELT - 0.02, -CAB_HALF), (CAB_X0 + 0.07, BELT + 0.04, CAB_HALF))
    obj("ForkliftCabFrame", bf, coll, [k], bevel=0.012, segs=2)
    rbox("ForkliftCabRoof", coll, k, CAB_X0 - 0.06, CAB_XF_TOP + 0.04, yt, CAB_TOP, -CAB_HALF - 0.05, CAB_HALF + 0.05,
         rv_back=0.08, rv_front=0.08, r_top=0.04, r_bot=0.01, segs=4)
    # Glass: windshield, door and rear side windows, rear window, lower door windows.
    bg = bmesh.new()
    t = 0.01
    side_prism(bg, [(CAB_XF - 0.03, 1.50), (CAB_XF - 0.03 + t, 1.50), (ax(yt) - 0.03 + t, yt), (ax(yt) - 0.03, yt)],
               -CAB_HALF + 0.03, CAB_HALF - 0.03)
    for s in (-1, 1):
        z = s * (CAB_HALF - 0.025)
        side_prism(bg, [(-1.30, BELT + 0.04), (ax(BELT + 0.04) - 0.05, BELT + 0.04), (ax(yt - 0.06) - 0.05, yt - 0.06),
                        (-1.30, yt - 0.06)], z - t / 2, z + t / 2)
        gbox_span(bg, (CAB_X0 + 0.07, BELT + 0.04, z - t / 2), (-1.36, yt - 0.06, z + t / 2))
        gbox_span(bg, (-1.20, 1.38, s * CAB_HALF), (-0.76, 1.62, s * (CAB_HALF + 0.004)))
    gbox_span(bg, (CAB_X0 + 0.02, BELT + 0.04, -CAB_HALF + 0.05), (CAB_X0 + 0.02 + t, yt - 0.06, CAB_HALF - 0.05))
    obj("ForkliftCabGlass", bg, coll, [M["glass"]], bevel=0.0)
    # Wiper, rear work lights, roof-edge seal.
    bm = bmesh.new()
    grod(bm, (ax(1.60) - 0.05, 1.60, 0.15), (ax(2.45) - 0.05, 2.45, -0.10), 0.008, segs=6)
    for s in (-1, 1):
        gbox(bm, (CAB_X0 + 0.02, CAB_TOP + 0.06, s * (CAB_HALF - 0.08)), (0.10, 0.12, 0.16))
        gbox(bm, (ax(yt) - 0.02, CAB_TOP + 0.06, s * (CAB_HALF - 0.08)), (0.10, 0.12, 0.16))
    obj("ForkliftCabFittings", bm, coll, [M["black"]], bevel=0.01, segs=2)
    bl = bmesh.new()
    for s in (-1, 1):
        gcyl(bl, (CAB_X0 - 0.035, CAB_TOP + 0.06, s * (CAB_HALF - 0.08)), 0.045, 0.01, 'x', segs=20)
        gcyl(bl, (ax(yt) + 0.035, CAB_TOP + 0.06, s * (CAB_HALF - 0.08)), 0.045, 0.01, 'x', segs=20)
    obj("ForkliftWorkLights", bl, coll, [M["lamp"]], bevel=0.0)
    # Interior: seat, steering column and wheel, dash, armrest with levers.
    rbox("ForkliftSeat", coll, M["black"], -1.40, -0.98, BELT, BELT + 0.12, -0.25, 0.25, rv_back=0.05, rv_front=0.05, r_top=0.04, segs=4)
    rbox("ForkliftSeatBack", coll, M["black"], -1.50, -1.38, BELT + 0.06, BELT + 0.70, -0.24, 0.24, rv_back=0.05, rv_front=0.05, r_top=0.07, segs=4)
    bi = bmesh.new()
    grod(bi, (CAB_XF - 0.12, BELT, 0.0), (CAB_XF - 0.40, BELT + 0.40, 0.0), 0.03, segs=10)
    L.add_torus(bi, 0.18, 0.016, L.mat(G(CAB_XF - 0.42, BELT + 0.44, 0.0), (90 - 35, 0, 90)), segs=32, minor=8)
    gbox_span(bi, (CAB_XF - 0.22, BELT - 0.02, -0.60), (CAB_XF - 0.08, BELT + 0.22, 0.60))
    gbox_span(bi, (-1.10, BELT + 0.12, -0.38), (-0.75, BELT + 0.24, -0.28))
    for j in range(3):
        grod(bi, (-0.85 + j * 0.05, BELT + 0.24, -0.33), (-0.85 + j * 0.05, BELT + 0.36, -0.33), 0.01, segs=8)
    obj("ForkliftInterior", bi, coll, [M["black"]], bevel=0.008, segs=2)
    # Intake pipe behind the cab (middle) and exhaust stack at its right rear corner.
    bx = bmesh.new()
    gcyl(bx, (CAB_X0 - 0.10, (HOOD_TOP + 3.05) / 2, 0.0), 0.075, 3.05 - HOOD_TOP, 'y', segs=24)
    gcyl(bx, (CAB_X0 - 0.10, 3.08, 0.0), 0.10, 0.08, 'y', segs=24)
    gcyl(bx, (CAB_X0 - 0.16, (HOOD_TOP + 3.00) / 2, -(CAB_HALF + 0.12)), 0.065, 3.00 - HOOD_TOP, 'y', segs=24)
    gcyl(bx, (CAB_X0 - 0.16, 2.30, -(CAB_HALF + 0.12)), 0.11, 0.55, 'y', segs=24)
    gcyl(bx, (CAB_X0 - 0.16, 2.00, -(CAB_HALF + 0.12)), 0.11, 0.08, 'y', segs=24)
    grod(bx, (CAB_X0 - 0.10, 2.30, -(CAB_HALF + 0.12)), (CAB_X0 + 0.0, 2.30, -(CAB_HALF - 0.02)), 0.02, segs=8)
    obj("ForkliftStacks", bx, coll, [k], bevel=0.008, segs=2)
    # Precleaner cap on the exhaust side, as on the truck: a black box on a short arm.
    rbox("ForkliftPrecleaner", coll, M["black"], CAB_X0 - 0.30, CAB_X0 - 0.02, 2.62, 2.80, -(CAB_HALF + 0.30), -(CAB_HALF + 0.04),
         rv_back=0.04, rv_front=0.04, r_top=0.03, segs=3)


# ---------------------------------------------------------------- wheels

def build_tyre(bm, bml, bmr):
    """Tyre (lathed about the wheel axis) with slanted bar lugs, and a dished disc rim."""
    r = TYRE_R
    prof = [(0.315, -0.150), (0.37, -0.168), (0.45, -0.175), (0.50, -0.165), (0.535, -0.140), (r - 0.012, -0.10),
            (r - 0.012, 0.10), (0.535, 0.140), (0.50, 0.165), (0.45, 0.175), (0.37, 0.168), (0.315, 0.150)]
    L.add_lathe(bm, prof, segs=96, closed=True)
    n = 30
    for k in range(n):
        a = 2 * math.pi * k / n
        for side, skew in ((-1, 0.45), (1, -0.45)):
            aa = a + (math.pi / n if side > 0 else 0.0)
            p = Vector((r * math.cos(aa), side * 0.075, r * math.sin(aa)))
            m = Matrix.Translation(p) @ Matrix.Rotation(-aa, 4, 'Y') @ Matrix.Rotation(skew, 4, 'X')
            L.add_box(bml, (0.026, 0.16, 0.07), m)
    rim = [(0.0, -0.11), (0.10, -0.11), (0.13, -0.09), (0.22, -0.085), (0.27, -0.04), (0.29, -0.12),
           (0.32, -0.155), (0.32, -0.165), (0.30, -0.16), (0.30, 0.15), (0.32, 0.155), (0.32, 0.165), (0.0, 0.165)]
    L.add_lathe(bmr, rim, segs=64)
    for k in range(10):
        a = 2 * math.pi * k / 10
        L.add_cyl(bmr, 0.016, 0.03, Matrix.Translation((0.17 * math.cos(a), -0.10, 0.17 * math.sin(a))) @ Matrix.Rotation(math.pi / 2, 4, 'X'), segs=6)
    L.add_cyl(bmr, 0.085, 0.05, Matrix.Translation((0, -0.125, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'X'), segs=24, r2=0.06)


def build_wheels(coll, M):
    for prefix, x, zc, sc in (("ForkliftDriveWheel", 0.0, DRIVE_Z, 1.0), ("ForkliftSteerWheel", -WHEELBASE, STEER_Z, STEER_R / TYRE_R)):
        for s, tag in ((-1, "R"), (1, "L")):
            bm, bml, bmr = bmesh.new(), bmesh.new(), bmesh.new()
            build_tyre(bm, bml, bmr)
            w = L.make_object(prefix + tag, bm, coll, [M["tyre"]], smooth_angle=60)
            lugs = L.make_object(prefix.replace("Wheel", "Lugs") + tag, bml, coll, [M["tyre"]], bevel=0.008, bevel_segments=2)
            rim = L.make_object(prefix.replace("Wheel", "Rim") + tag, bmr, coll, [M["rim"]], bevel=0.004, bevel_segments=2, smooth_angle=45)
            lugs.parent = w
            rim.parent = w
            w.location = G(x, TYRE_R * sc, s * zc)
            w.scale = (sc, sc, sc)
            # Lathe axis is local Y (Godot -Z); the rim's outer face is at local -Y, which is
            # Godot +Z: right for the left wheels, flipped for the right ones.
            w.rotation_euler = (0, 0, math.pi if s < 0 else 0.0)


# ---------------------------------------------------------------- mast and carriage

def build_mast(coll, M):
    """Outer mast (fixed to the truck, tilts with it in reality) and the inner mast, which
    rises once the carriage has used its free lift."""
    bm, bmi, bmc, bmh, bmr, bmt = (bmesh.new() for _ in range(6))
    yb = 0.32
    for s in (-1, 1):
        z = s * MAST_HALF
        # Outer channel: web outboard, flanges front and back (open inward).
        gbox_span(bm, (MAST_X - 0.10, yb, z + s * 0.05), (MAST_X + 0.10, MAST_LOW_TOP, z + s * 0.08))
        gbox_span(bm, (MAST_X + 0.07, yb, z - s * 0.08), (MAST_X + 0.10, MAST_LOW_TOP, z + s * 0.08))
        gbox_span(bm, (MAST_X - 0.10, yb, z - s * 0.08), (MAST_X - 0.07, MAST_LOW_TOP, z + s * 0.08))
        # Inner channel (moves), nested inside.
        zi = s * INNER_HALF
        gbox_span(bmi, (MAST_X - 0.065, yb + 0.06, zi - 0.045), (MAST_X + 0.065, MAST_LOW_TOP - 0.07, zi + 0.045))
        gbox_span(bmi, (MAST_X - 0.065, yb + 0.06, zi + s * 0.045), (MAST_X - 0.04, MAST_LOW_TOP - 0.07, zi + s * 0.10))
        gbox_span(bmi, (MAST_X + 0.04, yb + 0.06, zi + s * 0.045), (MAST_X + 0.065, MAST_LOW_TOP - 0.07, zi + s * 0.10))
        # Lift cylinders behind the outer channels: barrel fixed, rod and its head on the inner
        # mast's crosshead.
        gcyl(bmh, (MAST_X - 0.19, (yb + 2.95) / 2, z), 0.065, 2.95 - yb, 'y', segs=24)
        gcyl(bmh, (MAST_X - 0.19, 2.95, z), 0.075, 0.06, 'y', segs=24)
        gcyl(bmr, (MAST_X - 0.19, (1.0 + MAST_LOW_TOP - 0.10) / 2, z), 0.042, MAST_LOW_TOP - 0.10 - 1.0, 'y', segs=16)
        gbox_span(bmi, (MAST_X - 0.26, MAST_LOW_TOP - 0.16, z - 0.06), (MAST_X - 0.04, MAST_LOW_TOP - 0.07, z + 0.06))
        # Tilt cylinders: from brackets on the deck beside the cab up to the mast.
        p0 = Vector((-0.62, DECK_Y1 + 0.10, s * 0.80))
        p1 = Vector((MAST_X - 0.10, 1.86, s * (MAST_HALF + 0.12)))
        pm = p0.lerp(p1, 0.62)
        grod(bmh, tuple(p0), tuple(pm), 0.075, segs=20)
        grod(bmt, tuple(pm), tuple(p1), 0.04, segs=14)
        gbox_span(bmh, (-0.72, DECK_Y1, s * 0.74), (-0.52, DECK_Y1 + 0.18, s * 0.86))
        gbox_span(bm, (MAST_X - 0.16, 1.78, s * (MAST_HALF + 0.08)), (MAST_X - 0.04, 1.94, s * (MAST_HALF + 0.16)))
        # Tilt pivot brackets at the mast foot.
        gbox_span(bm, (MAST_X - 0.24, yb, s * (MAST_HALF - 0.06)), (MAST_X - 0.08, yb + 0.22, s * (MAST_HALF + 0.06)))
        # Work light on an arm off the top header.
        gbox_span(bm, (MAST_X - 0.02, MAST_LOW_TOP - 0.40, s * (MAST_HALF + 0.08)), (MAST_X + 0.03, MAST_LOW_TOP - 0.34, s * (MAST_HALF + 0.30)))
        gbox(bm, (MAST_X + 0.08, MAST_LOW_TOP - 0.37, s * (MAST_HALF + 0.30)), (0.12, 0.12, 0.18))
    # Outer cross members: header at the top, one low and one in the middle, behind the
    # carriage's travel.
    gbox_span(bm, (MAST_X - 0.10, MAST_LOW_TOP - 0.14, -MAST_HALF - 0.08), (MAST_X + 0.10, MAST_LOW_TOP, MAST_HALF + 0.08))
    for y in (0.55, 1.95):
        gbox_span(bm, (MAST_X - 0.10, y - 0.07, -MAST_HALF), (MAST_X - 0.04, y + 0.07, MAST_HALF))
    # Inner crosshead with the chain sheaves, and an inner cross member lower down.
    gbox_span(bmi, (MAST_X - 0.06, MAST_LOW_TOP - 0.20, -INNER_HALF), (MAST_X + 0.04, MAST_LOW_TOP - 0.07, INNER_HALF))
    gbox_span(bmi, (MAST_X - 0.06, 1.40, -INNER_HALF), (MAST_X - 0.02, 1.52, INNER_HALF))
    bsh = bmesh.new()
    for s in (-1, 1):
        gcyl(bsh, (MAST_X + 0.02, MAST_LOW_TOP - 0.10, s * 0.20), 0.09, 0.05, 'z', segs=24)
    # Chains from the carriage up over the sheaves (the front run), both near the middle.
    for s in (-1, 1):
        z = s * 0.20
        for k in range(40):
            y = 1.12 + k * (MAST_LOW_TOP - 0.10 - 1.12) / 39
            gbox(bmc, (MAST_X + 0.11, y, z), (0.03, 0.055, 0.05))
            gcyl(bmc, (MAST_X + 0.11, y - 0.0275, z), 0.010, 0.056, 'z', segs=8)
    # Hoses over the hose sheave at the top left, down the channel.
    bho = bmesh.new()
    gcyl(bho, (MAST_X - 0.02, MAST_LOW_TOP + 0.06, MAST_HALF + 0.14), 0.10, 0.06, 'z', segs=24)
    for dz in (0.11, 0.17):
        grod(bho, (MAST_X - 0.12, MAST_LOW_TOP + 0.04, MAST_HALF + dz), (MAST_X - 0.12, 0.9, MAST_HALF + dz), 0.014, segs=8)
    bl = bmesh.new()
    for s in (-1, 1):
        gbox_span(bl, (MAST_X + 0.14, MAST_LOW_TOP - 0.42, s * (MAST_HALF + 0.24)), (MAST_X + 0.145, MAST_LOW_TOP - 0.32, s * (MAST_HALF + 0.36)))
    obj("ForkliftMast", bm, coll, [M["mast"]], bevel=0.01, segs=2)
    obj("ForkliftMastHydraulics", bmh, coll, [M["mast"]], bevel=0.006, segs=2)
    obj("ForkliftMastHoses", bho, coll, [M["black"]], bevel=0.004, segs=1)
    obj("ForkliftMastLamps", bl, coll, [M["lamp"]], bevel=0.0)
    obj("ForkliftTiltRods", bmt, coll, [M["rod"]], bevel=0.0)
    inner = obj("ForkliftMastInner", bmi, coll, [M["mast"]], bevel=0.008, segs=2)
    obj("ForkliftMastInnerRods", bmr, coll, [M["rod"]], bevel=0.0).parent = inner
    obj("ForkliftMastSheaves", bsh, coll, [M["chain"]], bevel=0.006, segs=2).parent = inner
    obj("ForkliftMastChains", bmc, coll, [M["chain"]], bevel=0.002, segs=1).parent = inner
    text("ForkliftBadgeMast", coll, M["yellow"], "HYSTER", (MAST_X - 0.01, 2.30, MAST_HALF + 0.081), (90, 90, 0), 0.13)
    return inner


def build_carriage(coll, M):
    """Full-width carriage with no backrest, fork positioner cylinders on top, hook-on forks."""
    bm, bmh, bmw = bmesh.new(), bmesh.new(), bmesh.new()
    cx = CARRIAGE_X
    gbox_span(bm, (cx - 0.10, 0.86, -CARRIAGE_HALF), (cx, 1.02, CARRIAGE_HALF))     # top hook bar
    gbox_span(bm, (cx - 0.10, 0.14, -CARRIAGE_HALF), (cx, 0.28, CARRIAGE_HALF))     # bottom bar
    gbox_span(bm, (cx - 0.12, 0.50, -CARRIAGE_HALF + 0.10), (cx - 0.06, 0.60, CARRIAGE_HALF - 0.10))
    for z in (-CARRIAGE_HALF + 0.03, CARRIAGE_HALF - 0.03):
        gbox_span(bm, (cx - 0.12, 0.14, z - 0.03), (cx - 0.02, 1.02, z + 0.03))
    for z in (-0.05, 0.05):
        gbox_span(bm, (cx - 0.12, 0.14, z - 0.025), (cx - 0.04, 1.02, z + 0.025))
    # Back plates and the roller brackets that run in the inner channels.
    for s in (-1, 1):
        gbox_span(bm, (MAST_X + 0.07, 0.20, s * (INNER_HALF - 0.08)), (cx - 0.10, 1.00, s * (INNER_HALF - 0.02)))
        for y in (0.30, 0.90):
            gcyl(bm, (MAST_X, y, s * (INNER_HALF - 0.01)), 0.055, 0.05, 'z', segs=20)
    gbox_span(bmw, (cx - 0.10, 1.02, -CARRIAGE_HALF), (cx + 0.01, 1.05, CARRIAGE_HALF))
    # Positioner cylinders on top of the hook bar: barrels from the middle, rods out to the forks.
    for s in (-1, 1):
        grod(bmh, (cx - 0.06, 1.11, s * 0.10), (cx - 0.06, 1.11, s * 0.62), 0.055, segs=20)
        gbox_span(bmh, (cx - 0.10, 1.04, s * 0.06), (cx - 0.02, 1.16, s * 0.14))
    carriage = obj("ForkliftCarriage", bm, coll, [M["mast"]], bevel=0.01, segs=2)
    obj("ForkliftPositioner", bmh, coll, [M["mast"]], bevel=0.005, segs=2).parent = carriage
    obj("ForkliftCarriageWear", bmw, coll, [M["fork"]], bevel=0.004, segs=2).parent = carriage
    for s, tag in ((1, "L"), (-1, "R")):
        bf = bmesh.new()
        hx = FORK_FACE_X
        gbox_span(bf, (hx - 0.04, 0.02, -FORK_W / 2), (hx - 0.04 + FORK_T, FORK_SHANK_H, FORK_W / 2))
        L.add_prism(bf, [(hx - 0.04, 0.0), (hx + FORK_LEN, 0.0), (hx + FORK_LEN, 0.012), (hx + FORK_LEN - 0.20, FORK_T),
                         (hx - 0.04, FORK_T)], -FORK_W / 2, FORK_W / 2)
        L.add_prism(bf, [(hx - 0.04, FORK_T), (hx + 0.10, FORK_T), (hx - 0.04 + FORK_T, 0.25)], -FORK_W / 2, FORK_W / 2)  # heel
        # Upper and lower hooks round the carriage bars, and the positioner rod's lug.
        gbox_span(bf, (cx - 0.13, 1.02, -FORK_W / 2 + 0.02), (hx - 0.04, 1.08, FORK_W / 2 - 0.02))
        gbox_span(bf, (cx - 0.13, 0.86, -FORK_W / 2 + 0.02), (cx - 0.10, 1.08, FORK_W / 2 - 0.02))
        gbox_span(bf, (cx, 0.16, -FORK_W / 2 + 0.02), (hx - 0.04, 0.26, FORK_W / 2 - 0.02))
        gbox_span(bf, (cx - 0.10, 1.05, -0.04), (cx - 0.02, 1.17, 0.04))
        fork = obj("ForkliftFork" + tag, bf, coll, [M["fork"]], bevel=0.01, segs=2, loc=(0, 0, s * FORK_SPREAD))
        fork.parent = carriage
        # Positioner rod from the barrel out to this fork's lug.
        grod(bmh2 := bmesh.new(), (cx - 0.06, 1.11, s * 0.60), (cx - 0.06, 1.11, s * (FORK_SPREAD - 0.04)), 0.032, segs=14)
        obj("ForkliftPositionerRod" + tag, bmh2, coll, [M["rod"]], bevel=0.0).parent = carriage
    return carriage


# ---------------------------------------------------------------- build

def _studio_collection():
    """The Forklift collection, linked only into the forklift's own scene so the mill scene
    (shared with other work) isn't touched."""
    sc = bpy.data.scenes.get(STUDIO) or bpy.data.scenes.new(STUDIO)
    coll = bpy.data.collections.new(COLL)
    sc.collection.children.link(coll)
    return coll


def build(M=None):
    M = materials(M if M is not None else {})
    L.clear_collection(COLL)
    coll = _studio_collection()
    root = bpy.data.objects.new("Forklift", None)
    coll.objects.link(root)
    build_body(coll, M)
    build_cab(coll, M)
    build_wheels(coll, M)
    build_mast(coll, M)
    build_carriage(coll, M)
    for o in list(coll.all_objects):
        if o is not root and o.parent is None:
            o.parent = root
    return {"objects": len(coll.all_objects), "length_to_fork_face": round(FORK_FACE_X - REAR_X, 3),
            "width": round(2 * BODY_HALF, 3)}
