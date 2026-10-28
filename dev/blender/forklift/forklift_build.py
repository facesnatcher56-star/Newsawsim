"""Heavy-duty lumber-yard forklift, modelled after the user's Hyster XD-series photos
(dev/blender/forklift/refs/). Run inside Blender.

Sized to that class: 4.3 m to the fork faces, 2.4 m wide, 2.85 m wheelbase, 2.97 m cab,
about 10 t rated (a finished stacker package is about 6.7 t). Lumber spec: 72 in red forks on
a fork positioner, spread about 2.1 m under 16 ft boards.

How it is modelled (the earlier versions were bare boxes): every body panel is a block whose
edges carry their own bevel radius (the big rounded rear corners of the counterweight, soft
top edges, crisp bottoms), beveled with 8 segments and smooth shaded, so the panels read as
the rounded castings and pressings on the real truck. Wheel arches are boolean cuts with
swept black flares over them; tyres and rims are lathed profiles with real tread lugs.

What the photos show, and this builds:
- big single tyres on black dished rims, black flares over all four;
- yellow body: a full-width counterweight with big rounded rear corners and a black lamp band
  across the back (round lamps, HYSTER lettering), a black bumper below it, a grille hatch on
  the rear deck; flat side panels under the cab with a step recess (two silver treads);
  a front cowl over the drive tyres with headlights beside the mast;
- a tall glass cab with slim black pillars, black roof, work lights and an amber beacon;
- a black two-stage mast with chains outside the channels and a lettered top crossbar, a
  black carriage with fork-positioner cylinders and a pale wear strip, red forks.

Forklift-local frame, Godot axes: +X forward (toward the forks), +Y up, +Z to the left;
origin on the ground under the middle of the drive axle. Moving parts are separate objects:
ForkliftMastInner, ForkliftCarriage (ForkliftForkL/R children, spread in Z),
ForkliftDriveWheelL/R, ForkliftSteerWheelL/R (origin on the axle, spin about Z).
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

G, gbox, gbox_span, gcyl, grod, obj = S.G, S.gbox, S.gbox_span, S.gcyl, S.grod, S.obj

COLL = "Forklift"
CUTTERS = "ForkliftCutters"
INCH = 0.0254

WHEELBASE = 2.85
TYRE_R = 0.55
TYRE_W = 0.36
DRIVE_Z = 1.03                        # tyre centre lines
STEER_Z = 0.93
BODY_HALF = 1.20
FORK_FACE_X = 0.70
REAR_X = FORK_FACE_X - 4.30
BELT_Y = 1.55                         # side panel tops; the cab sits here
CW_TOP = 1.64                         # counterweight / rear deck top
CAB_X0, CAB_X1, CAB_HALF = -1.66, 0.16, 0.84
CAB_TOP = 2.97
MAST_X = 0.42
MAST_HALF = 0.62
MAST_LOW_TOP = 3.45
FORK_LEN = 72 * INCH
FORK_T = 0.08
FORK_W = 0.20
FORK_SHANK_H = 1.15
FORK_SPREAD = 1.05
CARRIAGE_HALF = 1.20
CARRIAGE_X = FORK_FACE_X - 0.10
ARCH_R = TYRE_R + 0.10                # wheel arch cut radius


# ---------------------------------------------------------------- materials

def _principled(name, base, rough, metal=0.0, coat=0.0, transmission=0.0, emission=None, bump=0.0):
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
    b.inputs["Coat Roughness"].default_value = 0.06
    b.inputs["Transmission Weight"].default_value = transmission
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
    m.diffuse_color = (*base, 1.0)
    return m


def materials(M):
    M["fl_body"] = _principled("Forklift_Yellow", (0.92, 0.56, 0.0), 0.32, coat=0.3)
    M["fl_dark"] = _principled("Forklift_Black", (0.004, 0.004, 0.0045), 0.38, coat=0.3)
    M["fl_red"] = _principled("Forklift_ForkRed", (0.55, 0.012, 0.008), 0.38, coat=0.3)
    M["fl_tyre"] = _principled("Forklift_Tyre", (0.007, 0.007, 0.007), 0.78, bump=0.15)
    M["fl_glass"] = _principled("Forklift_Glass", (0.80, 0.86, 0.86), 0.02, transmission=1.0)
    M["fl_light"] = _principled("Forklift_Lamp", (0.95, 0.95, 0.92), 0.05, emission=(1.0, 0.97, 0.9))
    M["fl_amber"] = _principled("Forklift_Amber", (1.0, 0.45, 0.02), 0.1, emission=(1.0, 0.4, 0.02))
    M["fl_lamp_red"] = _principled("Forklift_RedLamp", (0.7, 0.02, 0.01), 0.1, emission=(0.6, 0.0, 0.0))
    M["fl_steel"] = _principled("Forklift_Steel", (0.75, 0.75, 0.75), 0.22, metal=1.0, bump=0.05)
    M["fl_wear"] = _principled("Forklift_Wear", (0.62, 0.52, 0.36), 0.6)
    M["fl_seat"] = _principled("Forklift_Seat", (0.008, 0.008, 0.008), 0.7, bump=0.1)
    return M


# ---------------------------------------------------------------- shape helpers

def _finish(o, bevel_w, segs=8, limit='WEIGHT'):
    md = o.modifiers.new("Bevel", 'BEVEL')
    md.width = bevel_w
    md.segments = segs
    md.limit_method = limit
    if limit == 'ANGLE':
        md.angle_limit = math.radians(35)
    md.harden_normals = True
    md.use_clamp_overlap = True
    md.miter_outer = 'MITER_ARC'
    return md


def rbox(name, coll, mat, x0, x1, y0, y1, z0, z1, rv_back=0.0, rv_front=0.0, r_top=0.0,
         r_top_back=None, r_top_front=None, r_bot=0.0, back_lean=0.0, front_lean=0.0, segs=8,
         loc=(0, 0, 0)):
    """Block from (x0,y0,z0) to (x1,y1,z1) whose edges carry their own radius: vertical edges
    at the back (rv_back) and front (rv_front), top edges along X (r_top), top edges across
    at the back/front, bottom edges (r_bot). back_lean/front_lean move the top back/front
    edges inward, sloping that face."""
    r_top_back = r_top if r_top_back is None else r_top_back
    r_top_front = r_top if r_top_front is None else r_top_front
    me = bpy.data.meshes.new(name)
    vs, idx = [], {}
    for ix, x in ((0, x0), (1, x1)):
        for iy, y in ((0, y0), (1, y1)):
            for iz, z in ((0, z0), (1, z1)):
                xx = x + (back_lean if (ix == 0 and iy == 1) else 0.0) - (front_lean if (ix == 1 and iy == 1) else 0.0)
                idx[(ix, iy, iz)] = len(vs)
                vs.append(G(xx, y, z))
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
    o.location = G(*loc)
    _finish(o, rmax, segs)
    return o


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


def flare(name, coll, mat, xc, yc, z_in, z_out, r0, thick=0.05, lip=0.07, a0=0.0, a1=180.0, steps=48):
    """Black wheel flare: a curved skin over the tyre from z_in to z_out (z_out outboard),
    with a lip turning down at the outer edge, swept round the wheel from a0 to a1 degrees."""
    s = 1.0 if z_out > z_in else -1.0
    sec = [(r0, z_in), (r0 + thick, z_in), (r0 + thick, z_out), (r0 - lip, z_out), (r0 - lip, z_out - s * 0.035),
           (r0, z_out - s * 0.035)]
    bm = bmesh.new()
    rings = []
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        rings.append([bm.verts.new(G(xc + r * math.cos(a), yc + r * math.sin(a), z)) for r, z in sec])
    n = len(sec)
    for k in range(steps):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = L.make_object(name, bm, coll, [mat], bevel=0.012, bevel_segments=3, smooth_angle=50)
    return o


def text(name, coll, mat, body, loc, rot, size, extrude=0.004):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    o = bpy.data.objects.new(name, cu)
    coll.objects.link(o)
    o.data.materials.append(mat)
    o.location = G(*loc)
    o.rotation_euler = rot
    return o


# ---------------------------------------------------------------- body

def build_body(coll, M):
    sx = -WHEELBASE
    y_mat, k_mat = M["fl_body"], M["fl_dark"]
    # Counterweight: the big rounded casting at the back, full width, rear face leaning in a
    # touch at the top; wheel wells for the steer tyres are cut out of it.
    cw = rbox("ForkliftCounterweight", coll, y_mat, REAR_X, -1.60, 0.62, CW_TOP, -BODY_HALF, BODY_HALF,
              rv_back=0.42, rv_front=0.02, r_top=0.10, r_top_back=0.16, r_top_front=0.02, r_bot=0.03)
    # Black lamp band across the back, proud of the casting, and the black bumper below.
    # The band wraps the rear corners and stops short of the steer-tyre flares.
    rbox("ForkliftLampBand", coll, k_mat, REAR_X - 0.018, -2.60, 1.28, 1.47, -BODY_HALF - 0.018, BODY_HALF + 0.018,
         rv_back=0.44, rv_front=0.06, r_top=0.02, r_bot=0.02)
    rbox("ForkliftBumper", coll, k_mat, REAR_X - 0.01, -3.36, 0.34, 0.52, -BODY_HALF + 0.10, BODY_HALF - 0.10,
         rv_back=0.30, rv_front=0.10, r_top=0.03, r_bot=0.03)
    # Mid body: flat side panels from the counterweight to the mast, up to the cab's belt
    # line; front wheel arches cut out; a step recess on the left (+Z) side behind the front
    # tyre.
    mid = rbox("ForkliftMidBody", coll, y_mat, -1.70, 0.30, 0.48, BELT_Y, -BODY_HALF + 0.004, BODY_HALF - 0.004,
               rv_front=0.10, r_top=0.05, r_top_front=0.08, r_bot=0.02)
    for s, tag in ((-1, "R"), (1, "L")):
        zi, zo = s * (DRIVE_Z - TYRE_W / 2 - 0.07), s * (BODY_HALF + 0.3)
        cut(mid, cutter_cyl("ArchFront" + tag, 0.0, TYRE_R, zi, zo, ARCH_R))
        zi, zo = s * (STEER_Z - TYRE_W / 2 - 0.07), s * (BODY_HALF + 0.3)
        cut(cw, cutter_cyl("ArchRear" + tag, sx, TYRE_R, zi, zo, ARCH_R))
    cut(mid, cutter_box("StepRecess", (-1.40, 0.40, BODY_HALF - 0.14), (-ARCH_R - 0.08, 1.12, BODY_HALF + 0.3)))
    # Step treads in the recess, and the recess back wall.
    bt = bmesh.new()
    for y in (0.50, 0.86):
        gbox_span(bt, (-1.38, y, BODY_HALF - 0.14), (-ARCH_R - 0.10, y + 0.035, BODY_HALF - 0.005))
        for k in range(14):
            xk = -1.36 + k * ((-ARCH_R - 0.12) - (-1.36)) / 13
            gbox_span(bt, (xk - 0.006, y + 0.035, BODY_HALF - 0.13), (xk + 0.006, y + 0.042, BODY_HALF - 0.01))
    obj("ForkliftStepTreads", bt, coll, [M["fl_steel"]], bevel=0.002, segs=1)
    # Black chassis seen under the body: frame rails, axle housings, steer axle.
    bk = bmesh.new()
    gbox_span(bk, (-2.30, 0.30, -0.78), (0.32, 0.62, 0.78))
    gbox_span(bk, (-0.30, 0.36, -BODY_HALF + 0.30), (0.30, 0.70, BODY_HALF - 0.30))
    gbox_span(bk, (sx - 0.15, 0.36, -0.80), (sx + 0.15, 0.62, 0.80))
    obj("ForkliftChassis", bk, coll, [k_mat], bevel=0.02, segs=2)
    # Black flares over the four tyres.
    for s, tag in ((-1, "R"), (1, "L")):
        flare("ForkliftFlareFront" + tag, coll, k_mat, 0.0, TYRE_R, s * (DRIVE_Z - TYRE_W / 2 - 0.02),
              s * (DRIVE_Z + TYRE_W / 2 + 0.08), ARCH_R - 0.02, a0=-8, a1=188)
        flare("ForkliftFlareRear" + tag, coll, k_mat, sx, TYRE_R, s * (STEER_Z - TYRE_W / 2 - 0.02),
              s * (BODY_HALF + 0.06), ARCH_R - 0.02, a0=-12, a1=192)
    # Rear deck grille hatch and the round rear lamps, lettering on the band and the side.
    rbox("ForkliftDeckHatch", coll, k_mat, REAR_X + 0.55, -2.25, CW_TOP - 0.02, CW_TOP + 0.05, -0.62, 0.62,
         rv_back=0.10, rv_front=0.10, r_top=0.02)
    bg = bmesh.new()
    for k in range(16):
        x = REAR_X + 0.66 + k * ((-2.36) - (REAR_X + 0.66)) / 15
        gbox_span(bg, (x - 0.014, CW_TOP + 0.05, -0.55), (x + 0.014, CW_TOP + 0.062, 0.55))
    obj("ForkliftDeckGrille", bg, coll, [M["fl_steel"]], bevel=0.002, segs=1)
    bl, br = bmesh.new(), bmesh.new()
    for z, mesh in ((-0.86, br), (-0.70, bl), (0.70, bl), (0.86, br)):
        gcyl(mesh, (REAR_X - 0.022, 1.375, z), 0.055, 0.02, 'x', segs=24)
    obj("ForkliftRearAmber", bl, coll, [M["fl_amber"]], bevel=0.004, segs=2)
    obj("ForkliftRearRed", br, coll, [M["fl_lamp_red"]], bevel=0.004, segs=2)
    text("ForkliftBadgeRear", coll, y_mat, "HYSTER", (REAR_X - 0.03, 1.375, 0.0), (math.radians(90), 0, math.radians(-90)), 0.15)
    text("ForkliftBadgeSide", coll, k_mat, "HYSTER", (-1.20, BELT_Y - 0.12, BODY_HALF + 0.001), (math.radians(90), 0, 0), 0.12)
    # Headlights on the front corners of the cowl, beside the mast.
    bh, bhl = bmesh.new(), bmesh.new()
    for z in (-1.0, 1.0):
        gbox(bh, (0.27, 1.36, z), (0.10, 0.14, 0.20))
        for dz in (-0.05, 0.05):
            gcyl(bhl, (0.325, 1.36, z + dz), 0.04, 0.01, 'x', segs=20)
    obj("ForkliftHeadlightHousings", bh, coll, [k_mat], bevel=0.02, segs=3)
    obj("ForkliftHeadlights", bhl, coll, [M["fl_light"]], bevel=0.0)
    return cw


def build_cab(coll, M):
    """Glass cab: slim black pillars and rails, black roof with an overhang, glass all round,
    door on the left, work lights at the roof corners, amber beacon, mirrors, interior."""
    k = M["fl_dark"]
    y0 = BELT_Y
    bp = bmesh.new()
    for px in (CAB_X0, CAB_X1):
        for pz in (-CAB_HALF, CAB_HALF):
            gbox_span(bp, (px - 0.04, y0, pz - 0.04), (px + 0.04, CAB_TOP - 0.08, pz + 0.04))
    for pz in (-CAB_HALF, CAB_HALF):
        gbox_span(bp, (-0.80, y0, pz - 0.03), (-0.75, CAB_TOP - 0.08, pz + 0.03))          # door post
        gbox_span(bp, (CAB_X0, y0, pz - 0.035), (CAB_X1, y0 + 0.07, pz + 0.035))           # bottom rails
        gbox_span(bp, (-1.60, y0 + 0.6, pz - 0.02), (-0.80, y0 + 0.64, pz + 0.02)) if pz > 0 else None
    for px in (CAB_X0, CAB_X1):
        gbox_span(bp, (px - 0.035, y0, -CAB_HALF), (px + 0.035, y0 + 0.07, CAB_HALF))
    obj("ForkliftCabFrame", bp, coll, [k], bevel=0.012, segs=3)
    rbox("ForkliftCabRoof", coll, k, CAB_X0 - 0.07, CAB_X1 + 0.10, CAB_TOP - 0.12, CAB_TOP, -CAB_HALF - 0.07, CAB_HALF + 0.07,
         rv_back=0.06, rv_front=0.06, r_top=0.04, r_bot=0.01)
    bg = bmesh.new()
    t = 0.008
    gbox_span(bg, (CAB_X0 + 0.04, y0 + 0.07, -CAB_HALF - t / 2), (CAB_X1 - 0.04, CAB_TOP - 0.12, -CAB_HALF + t / 2))
    gbox_span(bg, (CAB_X0 + 0.04, y0 + 0.07, CAB_HALF - t / 2), (CAB_X1 - 0.04, CAB_TOP - 0.12, CAB_HALF + t / 2))
    gbox_span(bg, (CAB_X0 - t / 2, y0 + 0.07, -CAB_HALF + 0.04), (CAB_X0 + t / 2, CAB_TOP - 0.12, CAB_HALF - 0.04))
    gbox_span(bg, (CAB_X1 - t / 2, y0 + 0.07, -CAB_HALF + 0.04), (CAB_X1 + t / 2, CAB_TOP - 0.12, CAB_HALF - 0.04))
    obj("ForkliftCabGlass", bg, coll, [M["fl_glass"]], bevel=0.0)
    # Door handle, wiper, work lights, beacon, mirrors.
    bm = bmesh.new()
    gbox_span(bm, (-0.92, y0 + 0.55, CAB_HALF + 0.03), (-0.84, y0 + 0.58, CAB_HALF + 0.06))
    grod(bm, (CAB_X1 + 0.02, y0 + 0.15, 0.1), (CAB_X1 + 0.02, y0 + 0.85, 0.35), 0.008, segs=6)
    for s in (-1, 1):
        grod(bm, (CAB_X1, CAB_TOP - 0.45, s * CAB_HALF), (CAB_X1 + 0.18, CAB_TOP - 0.50, s * (CAB_HALF + 0.30)), 0.012, segs=8)
        gbox(bm, (CAB_X1 + 0.18, CAB_TOP - 0.62, s * (CAB_HALF + 0.32)), (0.03, 0.24, 0.15))
        for px in (CAB_X1 + 0.06, CAB_X0 - 0.02):
            gbox(bm, (px, CAB_TOP + 0.07, s * 0.66), (0.11, 0.11, 0.16))
    obj("ForkliftCabFittings", bm, coll, [k], bevel=0.01, segs=2)
    bl = bmesh.new()
    for s in (-1, 1):
        gcyl(bl, (CAB_X1 + 0.115, CAB_TOP + 0.07, s * 0.66), 0.04, 0.01, 'x', segs=20)
        gcyl(bl, (CAB_X0 - 0.075, CAB_TOP + 0.07, s * 0.66), 0.04, 0.01, 'x', segs=20)
    obj("ForkliftWorkLights", bl, coll, [M["fl_light"]], bevel=0.0)
    ba = bmesh.new()
    gcyl(ba, (CAB_X0 + 0.40, CAB_TOP + 0.09, -0.45), 0.07, 0.16, 'y', segs=24)
    obj("ForkliftBeacon", ba, coll, [M["fl_amber"]], bevel=0.02, segs=3)
    # Interior: seat, steering column and wheel, dash, armrest with joysticks.
    rbox("ForkliftSeat", coll, M["fl_seat"], -1.25, -0.75, y0 + 0.30, y0 + 0.44, -0.27, 0.27, rv_back=0.06, rv_front=0.06, r_top=0.05, r_bot=0.03)
    rbox("ForkliftSeatBack", coll, M["fl_seat"], -1.32, -1.18, y0 + 0.40, y0 + 1.05, -0.26, 0.26, rv_back=0.05, rv_front=0.05, r_top=0.08)
    bi = bmesh.new()
    grod(bi, (CAB_X1 - 0.12, y0 + 0.15, 0.0), (CAB_X1 - 0.42, y0 + 0.62, 0.0), 0.03, segs=10)
    L.add_torus(bi, 0.18, 0.016, L.mat(G(CAB_X1 - 0.44, y0 + 0.66, 0.0), (90 - 35, 0, 90)), segs=32, minor=8)
    gbox_span(bi, (CAB_X1 - 0.20, y0 + 0.07, -0.70), (CAB_X1 - 0.05, y0 + 0.45, 0.70))
    gbox_span(bi, (-0.95, y0 + 0.40, 0.30), (-0.55, y0 + 0.55, 0.40))
    for k_ in range(3):
        grod(bi, (-0.65 + k_ * 0.05, y0 + 0.55, 0.35), (-0.65 + k_ * 0.05, y0 + 0.66, 0.35), 0.01, segs=8)
    obj("ForkliftInterior", bi, coll, [k], bevel=0.008, segs=2)


# ---------------------------------------------------------------- wheels

def build_tyre(bm, bml, bmr):
    """Tyre (lathed about the wheel axis) with chevron lugs, and a dished black rim."""
    prof = [(0.315, -0.155), (0.37, -0.178), (0.45, -0.186), (0.51, -0.175), (0.538, -0.150), (TYRE_R, -0.11),
            (TYRE_R, 0.11), (0.538, 0.150), (0.51, 0.175), (0.45, 0.186), (0.37, 0.178), (0.315, 0.155)]
    L.add_lathe(bm, prof, segs=96, closed=True)
    n = 34
    for k in range(n):
        a = 2 * math.pi * (k + 0.5 * 0) / n
        for side, skew in ((-1, 0.35), (1, -0.35)):
            aa = a + (math.pi / n if side > 0 else 0.0)
            p = Vector(((TYRE_R + 0.012) * math.cos(aa), side * 0.075, (TYRE_R + 0.012) * math.sin(aa)))
            m = Matrix.Translation(p) @ Matrix.Rotation(-aa, 4, 'Y') @ Matrix.Rotation(skew, 4, 'X')
            L.add_box(bml, (0.03, 0.15, 0.075), m)
    rim = [(0.0, -0.13), (0.125, -0.13), (0.15, -0.105), (0.23, -0.10), (0.285, -0.05), (0.305, -0.135),
           (0.335, -0.17), (0.335, -0.18), (0.305, -0.175), (0.305, 0.165), (0.335, 0.17), (0.335, 0.18), (0.0, 0.18)]
    L.add_lathe(bmr, rim, segs=64)
    for k in range(10):
        a = 2 * math.pi * k / 10
        L.add_cyl(bmr, 0.016, 0.03, Matrix.Translation((0.10 * math.cos(a), -0.14, 0.10 * math.sin(a))) @ Matrix.Rotation(math.pi / 2, 4, 'X'), segs=6)
    L.add_cyl(bmr, 0.07, 0.03, Matrix.Translation((0, -0.145, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'X'), segs=24)


def build_wheels(coll, M):
    for prefix, x, zc in (("ForkliftDriveWheel", 0.0, DRIVE_Z), ("ForkliftSteerWheel", -WHEELBASE, STEER_Z)):
        for s, tag in ((-1, "R"), (1, "L")):
            bm, bml, bmr = bmesh.new(), bmesh.new(), bmesh.new()
            build_tyre(bm, bml, bmr)
            w = L.make_object(prefix + tag, bm, coll, [M["fl_tyre"]], smooth_angle=60)
            lugs = L.make_object(prefix.replace("Wheel", "Lugs") + tag, bml, coll, [M["fl_tyre"]], bevel=0.008, bevel_segments=2)
            rim = L.make_object(prefix.replace("Wheel", "Rim") + tag, bmr, coll, [M["fl_dark"]], bevel=0.004, bevel_segments=2, smooth_angle=45)
            lugs.parent = w
            rim.parent = w
            w.location = G(x, TYRE_R, s * zc)
            # Lathe axis is local Y (Godot -Z); the rim's outer face is at local -Y, which is
            # Godot +Z: right for the left wheels, flipped for the right ones.
            w.rotation_euler = (0, 0, math.pi if s < 0 else 0.0)


# ---------------------------------------------------------------- mast and carriage

def build_mast(coll, M):
    bm, bmi, bmc, bmh = (bmesh.new() for _ in range(4))
    for z in (-MAST_HALF, MAST_HALF):
        s = 1 if z > 0 else -1
        gbox_span(bm, (MAST_X - 0.12, 0.35, z - 0.08), (MAST_X + 0.12, MAST_LOW_TOP, z + 0.08))
        gbox_span(bm, (MAST_X - 0.12, 0.35, z - s * 0.10), (MAST_X + 0.12, MAST_LOW_TOP, z - s * 0.08))     # flange
        gbox_span(bmi, (MAST_X - 0.07, 0.40, z - s * 0.16 - 0.06), (MAST_X + 0.13, MAST_LOW_TOP - 0.06, z - s * 0.16 + 0.06))
        grod(bmh, (MAST_X - 0.60, 1.05, z * 1.12), (MAST_X - 0.12, 1.45, z), 0.065, segs=16)            # tilt cylinders
        grod(bmc, (MAST_X - 0.30, 1.20, z * 1.05), (MAST_X - 0.12, 1.45, z), 0.035, segs=12)
        for k in range(44):                                                                         # leaf chain, outside
            y = 0.95 + k * (MAST_LOW_TOP - 1.05) / 43
            gbox(bmc, (MAST_X + 0.02, y, z + s * 0.12), (0.055, 0.055, 0.04))
            gcyl(bmc, (MAST_X + 0.02, y - 0.0275, z + s * 0.12), 0.012, 0.05, 'z', segs=8)
        gcyl(bmc, (MAST_X + 0.02, MAST_LOW_TOP + 0.02, z + s * 0.12), 0.10, 0.05, 'z', segs=24)
        grod(bmh, (MAST_X - 0.16, 0.60, z - s * 0.05), (MAST_X - 0.16, MAST_LOW_TOP - 0.3, z - s * 0.05), 0.016, segs=8)
    gbox_span(bm, (MAST_X - 0.12, MAST_LOW_TOP - 0.24, -MAST_HALF - 0.10), (MAST_X + 0.14, MAST_LOW_TOP, MAST_HALF + 0.10))
    for y in (0.45, 1.95):
        gbox_span(bm, (MAST_X - 0.10, y - 0.07, -MAST_HALF), (MAST_X + 0.04, y + 0.07, MAST_HALF))
    gcyl(bmh, (MAST_X - 0.02, 1.45, 0.0), 0.09, 1.9, 'y', segs=24)
    grod(bmc, (MAST_X - 0.02, 2.4, 0.0), (MAST_X - 0.02, MAST_LOW_TOP - 0.24, 0.0), 0.055, segs=16)
    obj("ForkliftMast", bm, coll, [M["fl_dark"]], bevel=0.012, segs=2)
    obj("ForkliftMastInner", bmi, coll, [M["fl_dark"]], bevel=0.01, segs=2)
    obj("ForkliftMastChains", bmc, coll, [M["fl_steel"]], bevel=0.002, segs=1)
    obj("ForkliftMastHydraulics", bmh, coll, [M["fl_dark"]], bevel=0.006, segs=2)
    text("ForkliftBadgeMast", coll, M["fl_body"], "HYSTER", (MAST_X + 0.142, MAST_LOW_TOP - 0.12, 0.0),
         (math.radians(90), 0, math.radians(90)), 0.15)
    bl, bh = bmesh.new(), bmesh.new()
    for s in (-1, 1):
        gbox(bh, (MAST_X + 0.10, MAST_LOW_TOP - 0.40, s * (MAST_HALF + 0.22)), (0.12, 0.12, 0.16))
        gbox_span(bh, (MAST_X, MAST_LOW_TOP - 0.42, s * (MAST_HALF + 0.08)), (MAST_X + 0.04, MAST_LOW_TOP - 0.38, s * (MAST_HALF + 0.16)))
        gcyl(bl, (MAST_X + 0.165, MAST_LOW_TOP - 0.40, s * (MAST_HALF + 0.22)), 0.045, 0.01, 'x', segs=20)
    obj("ForkliftMastLampHousings", bh, coll, [M["fl_dark"]], bevel=0.015, segs=2)
    obj("ForkliftMastLamps", bl, coll, [M["fl_light"]], bevel=0.0)


def build_carriage(coll, M):
    bm, bmh, bmw = bmesh.new(), bmesh.new(), bmesh.new()
    cx = CARRIAGE_X
    for y0, y1 in ((0.12, 0.30), (0.88, 1.06)):
        gbox_span(bm, (cx - 0.09, y0, -CARRIAGE_HALF), (cx, y1, CARRIAGE_HALF))
    for z in (-CARRIAGE_HALF + 0.04, -0.55, 0.0, 0.55, CARRIAGE_HALF - 0.04):
        gbox_span(bm, (cx - 0.20, 0.12, z - 0.04), (cx - 0.09, 1.20, z + 0.04))
    gbox_span(bmw, (cx - 0.09, 1.06, -CARRIAGE_HALF), (cx + 0.015, 1.13, CARRIAGE_HALF))
    for y in (0.50, 0.68):
        for s in (-1, 1):
            grod(bmh, (cx - 0.045, y, s * 0.10), (cx - 0.045, y, s * (FORK_SPREAD - 0.14)), 0.042, segs=16)
            grod(bmh, (cx - 0.045, y, s * 0.10), (cx - 0.045, y, s * 0.55), 0.05, segs=16)
    carriage = obj("ForkliftCarriage", bm, coll, [M["fl_dark"]], bevel=0.012, segs=2)
    obj("ForkliftPositioner", bmh, coll, [M["fl_steel"]], bevel=0.004, segs=2).parent = carriage
    obj("ForkliftCarriageWear", bmw, coll, [M["fl_wear"]], bevel=0.005, segs=2).parent = carriage
    for s, tag in ((1, "L"), (-1, "R")):
        bf = bmesh.new()
        hx = FORK_FACE_X
        gbox_span(bf, (hx - 0.04, 0.02, -FORK_W / 2), (hx - 0.04 + FORK_T, FORK_SHANK_H, FORK_W / 2))
        L.add_prism(bf, [(hx - 0.04, 0.0), (hx + FORK_LEN, 0.0), (hx + FORK_LEN, 0.012), (hx + FORK_LEN - 0.18, FORK_T),
                         (hx - 0.04, FORK_T)], -FORK_W / 2, FORK_W / 2)
        L.add_prism(bf, [(hx - 0.04, FORK_T), (hx + 0.10, FORK_T), (hx - 0.04 + FORK_T, 0.25)], -FORK_W / 2, FORK_W / 2)  # heel
        for y0 in (0.16, 0.92):
            gbox_span(bf, (cx, y0, -FORK_W / 2 + 0.02), (hx - 0.04, y0 + 0.12, FORK_W / 2 - 0.02))
        fork = obj("ForkliftFork" + tag, bf, coll, [M["fl_red"]], bevel=0.01, segs=2, loc=(0, 0, s * FORK_SPREAD))
        fork.parent = carriage
    return carriage


def build(M):
    materials(M)
    L.clear_collection(COLL)
    coll = L.collection(COLL)
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
