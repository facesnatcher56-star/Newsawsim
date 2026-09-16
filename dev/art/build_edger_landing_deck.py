"""Run with Blender --background --python this_file. Coordinates authored in Godot axes."""
import bpy, math, os, bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
OUT = os.path.join(ROOT, 'game/assets/models/edger_landing_deck')
os.makedirs(OUT, exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, color, metal, rough):
    m = bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p = m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    return m

paint = mat('Forest green powder coated frame', (.075,.19,.13), .7, .38)
steel = mat('Brushed galvanized ramp steel', (.48,.53,.56), .85, .32)
dark = mat('Oiled chain steel', (.075,.085,.095), .9, .27)
bright = mat('Machined pins and fasteners', (.36,.40,.43), .95, .22)
yellow = mat('Safety ochre drive guard', (.78,.36,.045), .65, .4)
cast_steel = mat('Cast steel conveyor shoe', (.18, .19, .20), .85, .40)

def xyz(v): return (v[0], -v[2], v[1])

def finish(o, name, m):
    o.name = name; o.data.materials.append(m)
    return o

def box(name, pos, size, m, bevel=.003):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(pos)); o = bpy.context.object
    o.dimensions = (size[0], size[2], size[1]); bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Fabricated edge radii', 'BEVEL'); mod.width = bevel; mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o, name, m)

def cyl(name, pos, r, length, m, axis='X', verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=length, location=xyz(pos))
    o = bpy.context.object
    if axis == 'X': o.rotation_euler[1] = math.pi / 2
    elif axis == 'Z': o.rotation_euler[0] = math.pi / 2
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, m)

def make_dogbone_plate(name, x_pos, thickness, pitch, r_end, h_waist, m):
    bm = bmesh.new()
    pts = []
    n_arc = 8
    # Front semicircle: from angle pi/2 to 3*pi/2 around (0, 0)
    for i in range(n_arc + 1):
        ang = math.pi / 2.0 + math.pi * i / n_arc
        y = r_end * math.sin(ang)
        z = r_end * math.cos(ang)
        pts.append(Vector((y, z)))
    
    # Bottom waist curve from (y=-r_end, z=0) to (y=-r_end, z=pitch)
    for i in range(1, 5):
        t = i / 5.0
        z = t * pitch
        y = -r_end + 4.0 * (r_end - h_waist / 2.0) * t * (1.0 - t)
        pts.append(Vector((y, z)))
    
    # Rear semicircle: from angle -pi/2 to pi/2 around (0, pitch)
    for i in range(n_arc + 1):
        ang = -math.pi / 2.0 + math.pi * i / n_arc
        y = r_end * math.sin(ang)
        z = pitch + r_end * math.cos(ang)
        pts.append(Vector((y, z)))
        
    # Top waist curve from (y=r_end, z=pitch) to (y=r_end, z=0)
    for i in range(1, 5):
        t = 1.0 - i / 5.0
        z = t * pitch
        y = r_end - 4.0 * (r_end - h_waist / 2.0) * t * (1.0 - t)
        pts.append(Vector((y, z)))

    # In Blender coordinates: Godot (x, y, z) -> Blender (x, -z, y)
    verts_f = [bm.verts.new((x_pos - thickness / 2.0, -p.y, p.x)) for p in pts]
    verts_b = [bm.verts.new((x_pos + thickness / 2.0, -p.y, p.x)) for p in pts]
    
    n = len(pts)
    for i in range(n):
        i_next = (i + 1) % n
        bm.faces.new([verts_f[i], verts_b[i], verts_b[i_next], verts_f[i_next]])
        
    bm.faces.new(verts_f)
    bm.faces.new(reversed(verts_b))
    
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(m)
    return obj

def make_rooftop_body(name, pitch, m):
    # H78A pitched rooftop conveyor link body
    w_roof = 0.114
    half_w = w_roof / 2.0
    
    y_peak = 0.028
    y_eaves = 0.015
    y_roof_bot = 0.008
    y_channel_ceil = 0.020
    
    gap = 0.0028
    z_front = -0.012
    z_rear = pitch - 0.012 - gap
    
    z_bevel = 0.006
    drop_bevel = 0.003
    
    bm = bmesh.new()
    
    z_slices = [
        (z_front, True),
        (z_front + z_bevel, False),
        (z_rear - z_bevel, False),
        (z_rear, True)
    ]
    
    slice_verts = []
    for z, is_bev in z_slices:
        yp = y_peak - (drop_bevel if is_bev else 0.0)
        ye = y_eaves - (drop_bevel if is_bev else 0.0)
        poly = [
            Vector((-half_w, y_roof_bot)),
            Vector((-half_w, ye)),
            Vector((-0.004, yp)),
            Vector(( 0.004, yp)),
            Vector(( half_w, ye)),
            Vector(( half_w, y_roof_bot)),
            Vector(( 0.038, y_channel_ceil)),
            Vector((-0.038, y_channel_ceil)),
        ]
        verts = [bm.verts.new(xyz((p.x, p.y, z))) for p in poly]
        slice_verts.append(verts)
        
    n_poly = 8
    for s in range(len(z_slices) - 1):
        v0 = slice_verts[s]
        v1 = slice_verts[s+1]
        for i in range(n_poly):
            i_next = (i + 1) % n_poly
            bm.faces.new([v0[i], v1[i], v1[i_next], v0[i_next]])
            
    bm.faces.new(reversed(slice_verts[0]))
    bm.faces.new(slice_verts[-1])
    
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    
    mesh = bpy.data.meshes.new(name + '_roof')
    bm.to_mesh(mesh)
    bm.free()
    roof_obj = bpy.data.objects.new(name + '_roof', mesh)
    bpy.context.collection.objects.link(roof_obj)
    if m: roof_obj.data.materials.append(m)
    return roof_obj

def make_slotted_side_wall(name, x_center, thickness, pitch, m, y_top=0.015):
    bm = bmesh.new()
    r_boss = 0.021
    y_bot = -0.020
    
    outer_pts = []
    n_arc = 8
    for i in range(n_arc + 1):
        ang = math.pi / 2.0 + math.pi * i / n_arc
        y = r_boss * math.sin(ang)
        z = r_boss * math.cos(ang)
        outer_pts.append(Vector((y, z)))
    
    outer_pts.append(Vector((y_bot, pitch)))
    
    for i in range(n_arc + 1):
        ang = -math.pi / 2.0 + math.pi * i / n_arc
        y = r_boss * math.sin(ang)
        z = pitch + r_boss * math.cos(ang)
        outer_pts.append(Vector((y, z)))
        
    outer_pts.append(Vector((y_top, 0.0)))
    
    z_mid = pitch / 2.0
    y_slot = 0.002
    r_slot = 0.0055
    slot_w = 0.024
    
    hole_pts = []
    z_c_r = z_mid + slot_w / 2.0
    for i in range(n_arc + 1):
        ang = -math.pi / 2.0 + math.pi * i / n_arc
        y = y_slot + r_slot * math.sin(ang)
        z = z_c_r + r_slot * math.cos(ang)
        hole_pts.append(Vector((y, z)))
        
    z_c_f = z_mid - slot_w / 2.0
    for i in range(n_arc + 1):
        ang = math.pi / 2.0 + math.pi * i / n_arc
        y = y_slot + r_slot * math.sin(ang)
        z = z_c_f + r_slot * math.cos(ang)
        hole_pts.append(Vector((y, z)))
        
    x_min = x_center - thickness / 2.0
    x_max = x_center + thickness / 2.0
    
    v_out_f = [bm.verts.new(xyz((x_min, p.x, p.y))) for p in outer_pts]
    v_hole_f = [bm.verts.new(xyz((x_min, p.x, p.y))) for p in hole_pts]
    edges_f_out = [bm.edges.new((v_out_f[i], v_out_f[(i+1)%len(v_out_f)])) for i in range(len(v_out_f))]
    edges_f_hole = [bm.edges.new((v_hole_f[i], v_hole_f[(i+1)%len(v_hole_f)])) for i in range(len(v_hole_f))]
    bmesh.ops.bridge_loops(bm, edges=edges_f_out + edges_f_hole)
    
    v_out_b = [bm.verts.new(xyz((x_max, p.x, p.y))) for p in outer_pts]
    v_hole_b = [bm.verts.new(xyz((x_max, p.x, p.y))) for p in hole_pts]
    edges_b_out = [bm.edges.new((v_out_b[i], v_out_b[(i+1)%len(v_out_b)])) for i in range(len(v_out_b))]
    edges_b_hole = [bm.edges.new((v_hole_b[i], v_hole_b[(i+1)%len(v_hole_b)])) for i in range(len(v_hole_b))]
    bmesh.ops.bridge_loops(bm, edges=edges_b_out + edges_b_hole)
    
    bmesh.ops.bridge_loops(bm, edges=edges_f_out + edges_b_out)
    bmesh.ops.bridge_loops(bm, edges=edges_f_hole + edges_b_hole)
    
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if m: obj.data.materials.append(m)
    return obj

def make_cast_top_attachment(name, pitch, m):
    # Standalone rooftop attachment shoe with mounting lugs
    roof = make_rooftop_body(name + '_roof', pitch, m)
    ears = []
    for z in [0.0, pitch]:
        for x in [-0.052, 0.052]:
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.015, depth=0.006, location=xyz((x, 0, z)))
            cyl_obj = bpy.context.object
            cyl_obj.rotation_euler[1] = math.pi / 2
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
            ears.append(cyl_obj)
            
            bpy.ops.mesh.primitive_cube_add(size=1, location=xyz((x, 0.008, z)))
            up = bpy.context.object
            up.dimensions = (0.006, 0.016, 0.008)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            ears.append(up)
            
    bpy.ops.object.select_all(action='DESELECT')
    roof.select_set(True)
    for e in ears: e.select_set(True)
    bpy.context.view_layer.objects.active = roof
    bpy.ops.object.join()
    roof.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    if m: roof.data.materials.append(m)
    return roof

TRACKS = [-2.75, -1.375, 0, 1.375, 2.75]
for z in [-.65, 1.35, 3.35]:
    box('Crossmember', (0, -.40, z), (5.95, .18, .12), paint)
    for x in [-2.7, 2.7]:
        box('Square tube leg', (x, -1.04, z), (.12, 1.36, .12), paint)
        box('Anchor foot', (x, -1.74, z), (.30, .025, .28), steel)
        for dx in [-.10, .10]: cyl('Anchor bolt', (x + dx, -1.715, z), .018, .035, bright, 'Y', 6)

for x in TRACKS:
    box('Chain guide rail', (x, -.075, 1.35), (.12, .10, 4), paint)
    box('Return guide', (x, -.340, 1.35), (.10, .035, 4), dark)
    for z in [-.65, 3.35]:
        box('Pillow bearing', (x - .11, -.16, z), (.06, .14, .18), paint)
        for dz in [-.065, .065]: cyl('Bearing bolt', (x - .11, -.085, z + dz), .012, .02, bright, 'Y', 6)
        cyl('Sprocket hub', (x, -.16, z), .075, .16, bright)
        cyl('Sprocket', (x, -.16, z), .125, .075, dark, verts=24)
        for k in range(16):
            a = math.tau * k / 16
            tooth = box('Sprocket tooth', (x, -.16 + .133 * math.cos(a), z + .133 * math.sin(a)), (.08, .025, .024), dark, .001)
            tooth.rotation_euler[0] = a

for z in [-.65, 3.35]: cyl('Common drive shaft', (0, -.16, z), .035, 6, bright)
box('Gear reducer', (3.02, -.22, 3.35), (.36, .32, .32), paint)
cyl('Electric motor', (3.32, -.22, 3.35), .15, .38, paint)
for x in [3.18 + i * .035 for i in range(9)]: cyl('Motor cooling fin', (x, -.22, 3.35), .163, .009, paint)
box('Drive coupling guard', (2.95, -.13, 3.35), (.25, .22, .38), yellow)

# Short 0.8 m landing lane only. Each plate climbs along incoming +X.
for i, x1 in enumerate(TRACKS):
    x0 = -3.10 if i == 0 else TRACKS[i - 1] + .062
    x1 -= .062
    y0 = -.070; y1 = .008
    length = math.hypot(x1 - x0, y1 - y0)
    ramp = box('LandingRamp_%02d' % i, ((x0 + x1) / 2, (y0 + y1) / 2 - .004, 0), (length, .008, .8), steel, .001)
    ramp.rotation_euler[1] = -math.atan2(y1 - y0, x1 - x0)
    for z in [-.34, .34]:
        box('Ramp support bracket', (x1 - .08, -.11, z), (.10, .22, .04), paint)

# Keep each common shaft and its sprockets independently animatable.
rotating = []
for i, z in enumerate([-.65, 3.35]):
    objs = [o for o in bpy.context.scene.objects if o.name.startswith(('Sprocket', 'Common drive shaft')) and abs(o.location.y + z) < .2]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]; bpy.ops.object.join()
    shaft = objs[0]; shaft.name = 'DriveShaft_%d' % i
    bpy.context.scene.cursor.location = xyz((0, -.16, z)); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    rotating.append(shaft)

# Combine static meshes by material to limit draw calls.
for material in [paint, steel, dark, bright, yellow]:
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.active_material == material and o not in rotating]
    if objs:
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs: o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]; bpy.ops.object.join()
        objs[0].name = 'Structure_' + material.name.split()[0]

def export(path, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True)

# -----------------------------------------------------------------------------
# Cast-Top ANSI Conveyor Chain
# -----------------------------------------------------------------------------
RUN = 4.0
RADIUS = 0.145
LOOP = 2.0 * RUN + 2.0 * math.pi * RADIUS
LINK_COUNT = 104
PITCH = LOOP / LINK_COUNT

# Standalone reusable Top Block Attachment part
standalone_top_block = make_cast_top_attachment('Top_Block_Attachment', PITCH, cast_steel)
export(os.path.join(OUT, 'top_block_attachment.glb'), [standalone_top_block])

# 1. Build Inner Link (H78A Rooftop Style)
inner_parts = []
inner_roof = make_rooftop_body('InnerRoof', PITCH, cast_steel)
inner_w1 = make_slotted_side_wall('InnerWallL', -0.043, 0.008, PITCH, cast_steel)
inner_w2 = make_slotted_side_wall('InnerWallR',  0.043, 0.008, PITCH, cast_steel)
inner_parts.extend([inner_roof, inner_w1, inner_w2])
for z in [0.0, PITCH]:
    inner_parts.append(cyl('Roller', (0, 0, z), 0.018, 0.076, bright))

bpy.ops.object.select_all(action='DESELECT')
for o in inner_parts: o.select_set(True)
bpy.context.view_layer.objects.active = inner_parts[0]
bpy.ops.object.join()
inner_link = inner_parts[0]
inner_link.name = 'RollerChainInnerLink'
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# 2. Build Outer Link (H78A Rooftop Style)
outer_parts = []
outer_roof = make_rooftop_body('OuterRoof', PITCH, cast_steel)
outer_w1 = make_slotted_side_wall('OuterWallL', -0.053, 0.008, PITCH, cast_steel)
outer_w2 = make_slotted_side_wall('OuterWallR',  0.053, 0.008, PITCH, cast_steel)
outer_parts.extend([outer_roof, outer_w1, outer_w2])
for z in [0.0, PITCH]:
    outer_parts.append(cyl('Pin', (0, 0, z), 0.009, 0.120, bright))
    for dx in [-0.059, 0.059]:
        outer_parts.append(cyl('PinHead', (dx, 0, z), 0.0115, 0.004, dark))

bpy.ops.object.select_all(action='DESELECT')
for o in outer_parts: o.select_set(True)
bpy.context.view_layer.objects.active = outer_parts[0]
bpy.ops.object.join()
outer_link = outer_parts[0]
outer_link.name = 'RollerChainOuterLink'
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# Export prototype link GLBs
export(os.path.join(OUT, 'roller_chain_inner_link.glb'), [inner_link])
export(os.path.join(OUT, 'roller_chain_outer_link.glb'), [outer_link])
export(os.path.join(OUT, 'roller_chain_link.glb'), [inner_link])

def pin_pos(s):
    s = s % LOOP
    if s < RUN:
        return Vector((0.0, -0.018, -0.65 + s))
    s -= RUN
    arc = math.pi * RADIUS
    if s < arc:
        ang = s / RADIUS
        return Vector((0.0, -0.163 + RADIUS * math.cos(ang), 3.35 + RADIUS * math.sin(ang)))
    s -= arc
    if s < RUN:
        return Vector((0.0, -0.308, 3.35 - s))
    s -= RUN
    ang = math.pi + s / RADIUS
    return Vector((0.0, -0.163 + RADIUS * math.cos(ang), -0.65 + RADIUS * math.sin(ang)))

# Instantiate alternating inner and outer cast-top links along all 5 chain races
chain_objects = []
for ti, x in enumerate(TRACKS):
    for j in range(LINK_COUNT):
        s0 = j * PITCH
        s1 = (j + 1) * PITCH
        p0 = pin_pos(s0)
        p1 = pin_pos(s1)
        dy = p1.y - p0.y
        dz = p1.z - p0.z
        ang = math.atan2(-dy, dz)
        
        is_inner = (j % 2 == 0)
        mesh_data = inner_link.data if is_inner else outer_link.data
        o = bpy.data.objects.new('Chain_%d_Link_%03d' % (ti, j), mesh_data)
        bpy.context.collection.objects.link(o)
        o.location = xyz((x, p0.y, p0.z))
        o.rotation_euler = (ang, 0, 0)
        chain_objects.append(o)

# Remove prototype instances from the main assembly
bpy.data.objects.remove(standalone_top_block, do_unlink=True)
bpy.data.objects.remove(inner_link, do_unlink=True)
bpy.data.objects.remove(outer_link, do_unlink=True)

all_deck_objects = list(bpy.context.scene.objects)
export(os.path.join(OUT, 'landing_deck_frame.glb'), all_deck_objects)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(__file__), 'edger_landing_deck.blend'))
print('LANDING_DECK_BUILD_OK', len(bpy.context.scene.objects), 'objects', LINK_COUNT, 'links per chain')
