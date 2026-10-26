"""Mesh helpers for the procedural WW2 tank build (run inside Blender)."""
import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector


def collection(name, parent=None):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(coll)
    return coll


def clear_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        return
    for child in list(coll.children_recursive):
        for obj in list(child.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in list(coll.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for child in list(coll.children_recursive):
        bpy.data.collections.remove(child)
    bpy.data.collections.remove(coll)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def mat(loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    """Build a 4x4 matrix from location, XYZ euler degrees and optional scale."""
    m = Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot], 'XYZ').to_matrix().to_4x4()
    if scale is not None:
        m = m @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    return m


def _set_mat(verts, mat_index):
    for v in verts:
        for f in v.link_faces:
            f.material_index = mat_index


def add_box(bm, size, m=None, mat_index=0):
    m = m or Matrix()
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
    _set_mat(ret['verts'], mat_index)
    return ret['verts']


def add_cyl(bm, r, depth, m=None, segs=24, r2=None, mat_index=0):
    """Cylinder/cone along local Z, centred on the origin."""
    m = m or Matrix()
    ret = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segs,
        radius1=r, radius2=r if r2 is None else r2, depth=depth, matrix=m)
    _set_mat(ret['verts'], mat_index)
    return ret['verts']


def add_sphere(bm, r, m=None, segs=16, rings=8, mat_index=0):
    m = m or Matrix()
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r, matrix=m)
    _set_mat(ret['verts'], mat_index)
    return ret['verts']


def frame_between(p0, p1, up=(0, 0, 1)):
    """Matrix centred between two points with local X along p0->p1."""
    p0, p1 = Vector(p0), Vector(p1)
    x = (p1 - p0).normalized()
    upv = Vector(up)
    if abs(x.dot(upv)) > 0.99:
        upv = Vector((0, 1, 0))
    y = upv.cross(x).normalized()
    z = x.cross(y)
    rot = Matrix((x, y, z)).transposed().to_4x4()
    return Matrix.Translation((p0 + p1) / 2) @ rot, (p1 - p0).length


def add_beam(bm, p0, p1, w, h, up=(0, 0, 1), mat_index=0):
    m, length = frame_between(p0, p1, up)
    return add_box(bm, (length, w, h), m, mat_index)


def add_rod(bm, p0, p1, r, segs=12, mat_index=0):
    m, length = frame_between(p0, p1)
    return add_cyl(bm, r, length, m @ mat(rot=(0, 90, 0)), segs=segs, mat_index=mat_index)


def add_lathe(bm, profile, segs=48, m=None, mats=None, closed=False):
    """Spin a list of (radius, axial) points around local Y.

    A radius of 0 at either end closes that end with a fan. ``mats`` gives a
    material index per profile segment. ``closed`` joins the last point back
    to the first (for tori and rings).
    """
    m = m or Matrix()
    start_pole = not closed and profile[0][0] < 1e-6
    end_pole = not closed and profile[-1][0] < 1e-6
    lo = 1 if start_pole else 0
    hi = len(profile) - 1 if end_pole else len(profile)
    body = profile[lo:hi]
    nb = len(body)

    def mi(i):
        return mats[min(i, len(mats) - 1)] if mats else 0

    rings = []
    for k in range(segs):
        t = 2 * math.pi * k / segs
        c, s = math.cos(t), math.sin(t)
        rings.append([bm.verts.new(m @ Vector((r * c, a, r * s))) for r, a in body])
    faces = []
    nseg = nb if closed else nb - 1
    for k in range(segs):
        r0, r1 = rings[k], rings[(k + 1) % segs]
        for i in range(nseg):
            j = (i + 1) % nb
            f = bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
            f.material_index = mi(i + lo)
            faces.append(f)
    if start_pole:
        c = bm.verts.new(m @ Vector((0, profile[0][1], 0)))
        for k in range(segs):
            f = bm.faces.new((c, rings[k][0], rings[(k + 1) % segs][0]))
            f.material_index = mi(0)
            faces.append(f)
    if end_pole:
        c = bm.verts.new(m @ Vector((0, profile[-1][1], 0)))
        for k in range(segs):
            f = bm.faces.new((c, rings[(k + 1) % segs][-1], rings[k][-1]))
            f.material_index = mi(len(profile) - 2)
            faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def add_torus(bm, R, r, m=None, segs=24, minor=8, mat_index=0):
    prof = [(R + r * math.cos(2 * math.pi * i / minor), r * math.sin(2 * math.pi * i / minor)) for i in range(minor)]
    return add_lathe(bm, prof, segs, m, mats=[mat_index], closed=True)


def add_prism(bm, pts, y0, y1, m=None, mat_index=0):
    """Extrude a closed polygon given in the XZ plane between y0 and y1."""
    m = m or Matrix()
    a = [bm.verts.new(m @ Vector((x, y0, z))) for x, z in pts]
    b = [bm.verts.new(m @ Vector((x, y1, z))) for x, z in pts]
    faces = [bm.faces.new(a), bm.faces.new(b[::-1])]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((a[i], b[i], b[j], a[j])))
    for f in faces:
        f.material_index = mat_index
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def add_loft(bm, rings, cap_bottom=True, cap_top=True, mat_index=0):
    """Skin a list of equal-length closed point loops."""
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    faces = []
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    if cap_bottom:
        faces.append(bm.faces.new(vr[0][::-1]))
    if cap_top:
        faces.append(bm.faces.new(vr[-1]))
    for f in faces:
        f.material_index = mat_index
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def superellipse(a_front, a_rear, b, n, z, segs, xoff=0.0, yoff=0.0):
    """Closed loop with separate front/rear half-lengths (along X)."""
    pts = []
    for k in range(segs):
        t = 2 * math.pi * k / segs
        c, s = math.cos(t), math.sin(t)
        a = a_front if c >= 0 else a_rear
        x = a * math.copysign(abs(c) ** (2 / n), c)
        y = b * math.copysign(abs(s) ** (2 / n), s)
        pts.append(Vector((x + xoff, y + yoff, z)))
    return pts


def make_object(name, bm, coll, materials=(), bevel=None, bevel_segments=3, smooth_angle=40,
                weighted=True, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for material in materials:
        me.materials.append(material)
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = [math.radians(a) for a in rot]
    if parent is not None:
        obj.parent = parent
    if bevel:
        md = obj.modifiers.new("Bevel", 'BEVEL')
        md.width = bevel
        md.segments = bevel_segments
        md.limit_method = 'ANGLE'
        md.angle_limit = math.radians(smooth_angle)
        md.harden_normals = True
        md.miter_outer = 'MITER_ARC'
        md.use_clamp_overlap = True
    if weighted:
        md = obj.modifiers.new("WeightedNormal", 'WEIGHTED_NORMAL')
        md.keep_sharp = True
    return obj


def link_copy(src, name, coll, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), parent=None):
    """Linked duplicate sharing the source mesh."""
    obj = bpy.data.objects.new(name, src.data)
    coll.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = [math.radians(a) for a in rot]
    obj.scale = scale
    for md in src.modifiers:
        new = obj.modifiers.new(md.name, md.type)
        for prop in md.bl_rna.properties:
            if not prop.is_readonly and prop.identifier not in {"name", "type"}:
                setattr(new, prop.identifier, getattr(md, prop.identifier))
    if parent is not None:
        obj.parent = parent
    return obj


def convex_hull_2d(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]  # counter-clockwise


def resample_loop(loop, count):
    """Return ``count`` (point, tangent) pairs evenly spaced around a closed polyline."""
    segs = []
    total = 0.0
    n = len(loop)
    for i in range(n):
        a, b = Vector(loop[i]), Vector(loop[(i + 1) % n])
        length = (b - a).length
        segs.append((a, b, total, length))
        total += length
    out = []
    step = total / count
    si = 0
    for k in range(count):
        s = k * step
        while segs[si][2] + segs[si][3] < s:
            si += 1
        a, b, s0, length = segs[si]
        t = (s - s0) / length if length > 0 else 0.0
        p = a.lerp(b, t)
        # Smooth the tangent by looking a little ahead and behind along the loop.
        out.append((p, s))
    pts = [p for p, _ in out]
    res = []
    for k in range(count):
        tangent = (pts[(k + 1) % count] - pts[k - 1]).normalized()
        res.append((pts[k], tangent))
    return res, total
