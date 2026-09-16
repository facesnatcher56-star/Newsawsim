"""Modular builder for 50-bay industrial lumber bin sorter with authentic roller chains,
sprockets with real tooth profiles, top chain riding on top of race, clean haul-out chains,
and pillow block bearing hardware.
"""
import bpy, bmesh, math, os, time
from mathutils import Vector, Matrix

t0 = time.time()
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
OUT = os.path.join(ROOT, 'game/assets/models/bin_sorter')
os.makedirs(OUT, exist_ok=True)

# Clear existing scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, color, metal, rough):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    if p:
        p.inputs['Base Color'].default_value = (*color, 1)
        p.inputs['Metallic'].default_value = metal
        p.inputs['Roughness'].default_value = rough
    return m

paint_green  = mat('Forest green powder coated frame', (.075, .19, .13), .7, .38)
orange       = mat('Safety orange carriage and gate', (.92, .38, .05), .5, .35)
yellow       = mat('Safety yellow catwalk and rails', (.85, .68, .05), .6, .4)
dark_steel   = mat('Oiled chain steel', (.075, .085, .095), .9, .27)
bright_steel = mat('Machined pins and shafts', (.36, .40, .43), .95, .22)
galvanized   = mat('Galvanized haul-out channel', (.45, .48, .50), .85, .35)
uhmw_white   = mat('Low-friction UHMW wear strip', (.88, .88, .85), .05, .20)

def xyz(v):
    # Godot (x, y, z) -> Blender (x, -z, y)
    return Vector((v[0], -v[2], v[1]))

def add_box(bm, pos, size):
    loc = xyz(pos)
    dim = Vector((size[0], size[2], size[1]))
    mat_xform = Matrix.Translation(loc) @ Matrix.Diagonal((*dim, 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_xform)

def add_cyl(bm, pos, r, length, axis='X', verts=16):
    loc = xyz(pos)
    rot = Matrix.Identity(4)
    if axis == 'X':
        rot = Matrix.Rotation(math.pi / 2, 4, 'Y')
    elif axis == 'Y':
        rot = Matrix.Rotation(math.pi / 2, 4, 'X')
    elif axis == 'Z':
        rot = Matrix.Rotation(math.pi / 2, 4, 'X')
    mat_xform = Matrix.Translation(loc) @ rot @ Matrix.Diagonal((r * 2, r * 2, length, 1.0))
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=0.5, radius2=0.5, depth=1.0, matrix=mat_xform)

# Fast direct cylinder along Godot Z (shaft axis / pin axis)
def add_cyl_direct_z(bm, x, y, z_min, z_max, r, segments=8):
    cos_sin = [(r * math.cos(2 * math.pi * k / segments), r * math.sin(2 * math.pi * k / segments)) for k in range(segments)]
    vf = [bm.verts.new(xyz((x + cs[0], y + cs[1], z_max))) for cs in cos_sin]
    vb = [bm.verts.new(xyz((x + cs[0], y + cs[1], z_min))) for cs in cos_sin]
    bm.faces.new(vf)
    bm.faces.new(reversed(vb))
    for k in range(segments):
        nk = (k + 1) % segments
        bm.faces.new([vf[k], vf[nk], vb[nk], vb[k]])

# Fast direct dogbone roller chain link plate
def add_dogbone_plate(bm, p1, p2, z, thickness, r_lobe=0.028, h_waist=0.036):
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    L = math.hypot(dx, dy)
    if L < 1e-4:
        return
    ang = math.atan2(dy, dx)
    cos_a = math.cos(ang)
    sin_a = math.sin(ang)
    
    r_d = r_lobe * 0.7071
    pts_2d = [
        (L + r_lobe, 0.0),
        (L + r_d, r_d),
        (L * 0.5, h_waist * 0.5),
        (-r_d, r_d),
        (-r_lobe, 0.0),
        (-r_d, -r_d),
        (L * 0.5, -h_waist * 0.5),
        (L + r_d, -r_d)
    ]
    M = len(pts_2d)
    z_f = z + thickness * 0.5
    z_b = z - thickness * 0.5
    
    verts_f = [bm.verts.new(xyz((p1[0] + u * cos_a - v * sin_a, p1[1] + u * sin_a + v * cos_a, z_f))) for u, v in pts_2d]
    verts_b = [bm.verts.new(xyz((p1[0] + u * cos_a - v * sin_a, p1[1] + u * sin_a + v * cos_a, z_b))) for u, v in pts_2d]
        
    bm.faces.new(verts_f)
    bm.faces.new(reversed(verts_b))
    for i in range(M):
        ni = (i + 1) % M
        bm.faces.new([verts_f[i], verts_f[ni], verts_b[ni], verts_b[i]])

# Fast true sprocket profile generator with roller seating pockets and hub
def add_sprocket_with_teeth(bm, center, r_pitch, num_teeth, thickness, r_roller=0.022):
    xc, yc, zc = center
    delta_th = 2.0 * math.pi / num_teeth
    r_root = r_pitch - r_roller
    r_tip = r_pitch + 0.038
    
    pts = []
    for k in range(num_teeth):
        # Center valley roller pocket at tangent entry (pi/2) and around wrap
        th = math.pi * 0.5 + k * delta_th
        phi = th + delta_th * 0.5
        # 1. Valley roller seat pocket
        pts.append((r_root * math.cos(th), r_root * math.sin(th)))
        # 2. Rising tooth flank
        pts.append((r_pitch * math.cos(th + delta_th * 0.18), r_pitch * math.sin(th + delta_th * 0.18)))
        # 3. Tooth crest left
        pts.append((r_tip * math.cos(phi - delta_th * 0.06), r_tip * math.sin(phi - delta_th * 0.06)))
        # 4. Tooth crest right
        pts.append((r_tip * math.cos(phi + delta_th * 0.06), r_tip * math.sin(phi + delta_th * 0.06)))
        # 5. Falling tooth flank
        pts.append((r_pitch * math.cos(th + delta_th * 0.82), r_pitch * math.sin(th + delta_th * 0.82)))

    M = len(pts)
    z_f = zc + thickness * 0.5
    z_b = zc - thickness * 0.5
    vf = [bm.verts.new(xyz((xc + p[0], yc + p[1], z_f))) for p in pts]
    vb = [bm.verts.new(xyz((xc + p[0], yc + p[1], z_b))) for p in pts]
    bm.faces.new(vf)
    bm.faces.new(reversed(vb))
    for i in range(M):
        ni = (i + 1) % M
        bm.faces.new([vf[i], vf[ni], vb[ni], vb[i]])
        
    # Machined center hub
    hub_r = 0.09
    hub_w = thickness + 0.040
    add_cyl_direct_z(bm, xc, yc, zc - hub_w * 0.5, zc + hub_w * 0.5, hub_r, 16)

# Pillow block bearing unit and frame mounting bracket
def add_pillow_block_bearing(bm_housing, bm_steel, center, shaft_r=0.050, side='left'):
    xc, yc, zc = center
    base_w = 0.30     # length along X
    base_h = 0.045    # height along Y
    base_d = 0.14     # depth along Z
    base_drop = 0.080 # from shaft center down to base bottom

    # Heavy cast-iron base plate
    add_box(bm_housing, (xc, yc - base_drop + base_h * 0.5, zc), (base_w, base_h, base_d))

    # Cylindrical bearing housing arch wrapping the shaft
    add_cyl_direct_z(bm_housing, xc, yc, zc - (base_d - 0.02) * 0.5, zc + (base_d - 0.02) * 0.5, shaft_r + 0.038, 16)

    # Housing side gussets
    add_box(bm_housing, (xc - 0.085, yc - base_drop * 0.45, zc), (0.07, base_drop * 0.75, base_d - 0.02))
    add_box(bm_housing, (xc + 0.085, yc - base_drop * 0.45, zc), (0.07, base_drop * 0.75, base_d - 0.02))

    # Grease zerk fitting on housing cap
    add_cyl(bm_steel, (xc, yc + shaft_r + 0.050, zc), 0.008, 0.026, 'Y', 8)

    # 2 Grade 8 hex mounting bolts through foot ears
    for bx in [xc - 0.105, xc + 0.105]:
        add_cyl(bm_steel, (bx, yc - base_drop + base_h * 0.5, zc), 0.012, base_h + 0.02, 'Y', 6)

    # Structural steel mounting shelf welded to the frame column
    shelf_th = 0.025
    add_box(bm_housing, (xc, yc - base_drop - shelf_th * 0.5, zc), (base_w + 0.06, shelf_th, base_d + 0.04))
    # Gusset plate under shelf
    add_box(bm_housing, (xc, yc - base_drop - 0.12, zc), (0.08, 0.20, 0.04))

def mesh_from_bmesh(name, bm, material=None):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if material:
        mesh.materials.append(material)
    return mesh

def obj_from_mesh(name, mesh, loc=(0,0,0)):
    obj = bpy.data.objects.new(name, mesh)
    obj.location = xyz(loc)
    bpy.context.collection.objects.link(obj)
    return obj

def export(path, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True)

# -----------------------------------------------------------------------------
# SPECIFICATIONS
# -----------------------------------------------------------------------------
NUM_BAYS = 50
BAY_W = 1.0             # 1.0 m width per bay
BAY_D = 5.5             # 5.5 m depth across Z (Z in [-2.75, +2.75])
TOTAL_L = NUM_BAYS * BAY_W  # 50.0 m

SUPER_TOP_Y = 5.80      # Top of superstructure girders
PITCH = 0.20            # 0.20 m standard chain pitch
OVERHEAD_TEETH = 10     # 10 teeth
R_OVERHEAD = PITCH / (2.0 * math.sin(math.pi / OVERHEAD_TEETH)) # ~0.3236m

OVERHEAD_SHAFT_Y = 5.00
CHAIN_RETURN_Y = OVERHEAD_SHAFT_Y + R_OVERHEAD  # ~5.324m (top return pitch line)
CHAIN_WORK_Y   = OVERHEAD_SHAFT_Y - R_OVERHEAD  # ~4.676m (lower working pitch line)
LUG_TIP_Y      = 4.22                           # Downward lug tip elevation (80mm below 4.30m board plane)
TRANSPORT_Y    = 4.30                           # Board transport plane (top of UHMW slide rails)
CARRIAGE_REST_Y= 3.40                           # Top catch height of carriage (Zone C, <= 3.50m)
DIVIDER_BOTTOM_Y = 1.60                         # Bottom of sorting bays / top of 1.4m haul-out corridor

HAULOUT_TEETH  = 6                              # 6 teeth
R_HAULOUT      = 0.10                           # ~0.10m radius
HAULOUT_SHAFT_Y= 0.10                           # Haul-out shaft elevation
HAULOUT_Y      = HAULOUT_SHAFT_Y + R_HAULOUT    # 0.20m (floor haul-out chain top carrying surface)
DISCHARGE_Y    = 0.05                           # Carriage fork elevation during discharge (15cm below haulout)

OVERHEAD_CHAINS = [-1.8, -0.6, 0.6, 1.8]
# 5 Staggered slide rails: chains run in the clear 1.2m open lanes between rails
SLIDE_RAILS     = [-2.4, -1.2, 0.0, 1.2, 2.4]
HAULOUT_CHAINS  = [-2.0, -1.0, 0.0, 1.0, 2.0]
CARRIAGE_FORKS  = [-1.5, -0.5, 0.5, 1.5]

print("=" * 75)
print("BUILDING 50-BAY BIN SORTER WITH AUTHENTIC ROLLER CHAINS & SPROCKETS")
print(f"Overhead Sprockets: N={OVERHEAD_TEETH}, R_pitch={R_OVERHEAD:.4f}m, Pitch={PITCH:.2f}m")
print(f"Overhead Chains: Return Y={CHAIN_RETURN_Y:.3f}m (ON TOP of race), Working Y={CHAIN_WORK_Y:.3f}m")
print(f"Slide Rails: 5 Staggered UHMW Rails at Y={TRANSPORT_Y:.2f}m, Lug Tip Y={LUG_TIP_Y:.2f}m")
print(f"Pack Corridor: Open tunnel Y in [{HAULOUT_Y:.2f}, {DIVIDER_BOTTOM_Y:.2f}]m (Headroom={DIVIDER_BOTTOM_Y - HAULOUT_Y:.2f}m)")
print(f"Haul-Out: 5 Plain Drag Chain Strands at Y={HAULOUT_Y:.2f}m (NO BLOCKS)")
print(f"Carriage: Max raised Y={CARRIAGE_REST_Y:.2f}m (leaves {TRANSPORT_Y - (CARRIAGE_REST_Y + 0.20):.2f}m clear gap below board plane)")
print("=" * 75)

# -----------------------------------------------------------------------------
# 1. PROTOTYPE ORANGE CATCH CARRIAGE (Zone C: Max height strictly <= 3.60m)
# -----------------------------------------------------------------------------
bm_carr = bmesh.new()
# Spine beam at X = -0.35m (top at Y = 0.0)
add_box(bm_carr, (-0.35, -0.05, 0.0), (0.14, 0.10, 5.0))

# 4 Heavy Cantilever load support forks extending in +X from spine
for z_fk in CARRIAGE_FORKS:
    # Fork body extending from X = -0.35 to +0.38 (top surface at Y = 0.0)
    add_box(bm_carr, (0.015, -0.03, z_fk), (0.73, 0.06, 0.12))
    # Stiffener gusset connecting fork to spine
    add_box(bm_carr, (-0.25, 0.03, z_fk), (0.15, 0.08, 0.10))
    # Low-profile rear upright backstop post (height 0.20m, top at Y = +0.20m)
    add_box(bm_carr, (-0.35, 0.10, z_fk), (0.08, 0.20, 0.10))

# Low-profile guide shoe brackets engaging column guide channels (top at Y = +0.17m)
for side in [-2.55, 2.55]:
    add_box(bm_carr, (-0.35, 0.05, side), (0.12, 0.24, 0.10))
    add_box(bm_carr, (-0.35, 0.05, side + (0.08 if side > 0 else -0.08)), (0.08, 0.18, 0.06))

carr_mesh = mesh_from_bmesh('CarriageMesh', bm_carr, orange)
sample_carr = obj_from_mesh('bin_cradle', carr_mesh, (0, 0, 0))
export(os.path.join(OUT, 'bin_cradle.glb'), [sample_carr])
bpy.data.objects.remove(sample_carr, do_unlink=True)

# -----------------------------------------------------------------------------
# 2. PROTOTYPE DIVERTER DROP GATE (Downstream Pivot with Recessed Shaft)
# -----------------------------------------------------------------------------
bm_gate = bmesh.new()
# Hinge shaft axis is recessed 65mm UNDER the board transport plane (Y = -0.065m)
# Shaft radius is 0.020m (top of shaft at Y = -0.045m, safely below the 0.0m slide plane)
add_cyl(bm_gate, (0.0, -0.065, 0.0), 0.020, 5.0, 'Z')

# 5 Diverter drop skids with UHMW wear tops extending along -X (upstream) from pivot across bay opening
for z_rail in SLIDE_RAILS:
    # Steel skid body extending from X = 0.0 to X = -0.84 (center at X = -0.42m)
    add_box(bm_gate, (-0.42, -0.025, z_rail), (0.84, 0.035, 0.08))
    # Low-friction UHMW top wear strip (top surface flush at Y = 0.0 when gate is closed)
    add_box(bm_gate, (-0.42, -0.005, z_rail), (0.84, 0.010, 0.07))
    # Hinge collar / ear dropping down to wrap around the recessed shaft
    add_box(bm_gate, (-0.02, -0.045, z_rail), (0.05, 0.040, 0.06))
    add_cyl(bm_gate, (0.0, -0.065, z_rail), 0.028, 0.06, 'Z')

# Transverse tie bar connecting all 5 skids underneath, lowered to Y = -0.12m so it clears lug tips (Y = 4.22m)
add_box(bm_gate, (-0.42, -0.12, 0.0), (0.05, 0.04, 5.0))
# Vertical connecting struts between tie bar and each skid
for z_rail in SLIDE_RAILS:
    add_box(bm_gate, (-0.42, -0.075, z_rail), (0.04, 0.07, 0.06))

# Actuator lever arm tucked underneath outboard (away from lumber path)
add_box(bm_gate, (-0.06, -0.18, 2.5), (0.06, 0.18, 0.04))
add_cyl(bm_gate, (-0.06, -0.26, 2.5), 0.015, 0.06, 'Z')

gate_mesh = mesh_from_bmesh('GateMesh', bm_gate, orange)
sample_gate = obj_from_mesh('bin_diverter_gate', gate_mesh, (0, 0, 0))
export(os.path.join(OUT, 'bin_diverter_gate.glb'), [sample_gate])
bpy.data.objects.remove(sample_gate, do_unlink=True)

# -----------------------------------------------------------------------------
# 2b. PROTOTYPE CHAIN LINK & PUSHER LUG
# -----------------------------------------------------------------------------
bm_link = bmesh.new()
add_dogbone_plate(bm_link, (0.0, 0.0), (PITCH, 0.0), -0.026, 0.006)
add_dogbone_plate(bm_link, (0.0, 0.0), (PITCH, 0.0),  0.026, 0.006)
add_cyl_direct_z(bm_link, 0.0, 0.0, -0.016, 0.016, 0.022, 12)
add_cyl_direct_z(bm_link, 0.0, 0.0, -0.030, 0.030, 0.012, 8)
mesh_link = mesh_from_bmesh('SorterChainLinkMesh', bm_link, dark_steel)
sample_link = obj_from_mesh('sorter_chain_link', mesh_link, (0, 0, 0))
export(os.path.join(OUT, 'sorter_chain_link.glb'), [sample_link])
bpy.data.objects.remove(sample_link, do_unlink=True)

bm_lug = bmesh.new()
lug_h = CHAIN_WORK_Y - LUG_TIP_Y
add_box(bm_lug, (0.0, -lug_h * 0.5, 0.0), (0.08, lug_h, 0.07))
add_box(bm_lug, (-0.05, -0.12, 0.0), (0.09, 0.20, 0.05))
add_box(bm_lug, (0.0, 0.0, 0.0), (0.12, 0.060, 0.052))
add_box(bm_lug, (0.02, -lug_h + 0.05, 0.0), (0.03, 0.10, 0.07))
mesh_lug = mesh_from_bmesh('SorterChainLugMesh', bm_lug, paint_green)
sample_lug = obj_from_mesh('sorter_chain_lug', mesh_lug, (0, 0, 0))
export(os.path.join(OUT, 'sorter_chain_lug.glb'), [sample_lug])
bpy.data.objects.remove(sample_lug, do_unlink=True)

bm_hd_link = bmesh.new()
PITCH_HD = 0.10
add_dogbone_plate(bm_hd_link, (0.0, 0.0), (PITCH_HD, 0.0), -0.018, 0.004, r_lobe=0.018, h_waist=0.024)
add_dogbone_plate(bm_hd_link, (0.0, 0.0), (PITCH_HD, 0.0),  0.018, 0.004, r_lobe=0.018, h_waist=0.024)
add_cyl_direct_z(bm_hd_link, 0.0, 0.0, -0.012, 0.012, 0.015, 10)
add_cyl_direct_z(bm_hd_link, 0.0, 0.0, -0.022, 0.022, 0.008, 8)
mesh_hd_link = mesh_from_bmesh('HaulOutChainLinkMesh', bm_hd_link, dark_steel)
sample_hd_link = obj_from_mesh('haulout_chain_link', mesh_hd_link, (0, 0, 0))
export(os.path.join(OUT, 'haulout_chain_link.glb'), [sample_hd_link])
bpy.data.objects.remove(sample_hd_link, do_unlink=True)


# -----------------------------------------------------------------------------
# 3. STATIC FRAME & CONVEYANCE STRUCTURE
# -----------------------------------------------------------------------------
bm_green  = bmesh.new()
bm_galv   = bmesh.new()
bm_dark   = bmesh.new()
bm_yellow = bmesh.new()
bm_bright = bmesh.new()
bm_uhmw   = bmesh.new()

# Function to build continuous linear chain strand with dogbone plates, rollers, pins, and optional lugs
def build_linear_strand(start_x, end_x, y, z, pitch, is_overhead_working=False):
    num_links = int((end_x - start_x) / pitch)
    for k in range(num_links):
        x1 = start_x + k * pitch
        x2 = x1 + pitch
        is_outer = (k % 2 == 1)
        w = 0.052 if is_outer else 0.036
        
        # Dogbone side plates
        add_dogbone_plate(bm_dark, (x1, y), (x2, y), z - w * 0.5, 0.006)
        add_dogbone_plate(bm_dark, (x1, y), (x2, y), z + w * 0.5, 0.006)
        
        # Cylindrical roller sleeve at pin 1
        add_cyl_direct_z(bm_dark, x1, y, z - 0.016, z + 0.016, 0.022, 8)
        # Joint pin
        add_cyl_direct_z(bm_bright, x1, y, z - 0.030, z + 0.030, 0.012, 6)

        # Downward pusher lugs on working run every 1.0m (every 5th link)
        if is_overhead_working and (k % 5 == 0):
            lug_h = y - LUG_TIP_Y
            # Main pushing arm hanging down into the clear 1.2m open lane
            add_box(bm_green, (x1, y - lug_h * 0.5, z), (0.08, lug_h, 0.07))
            # Heavy reinforcement heel gusset
            add_box(bm_green, (x1 - 0.05, y - 0.12, z), (0.09, 0.20, 0.05))
            # Chain link attachment bracket
            add_box(bm_dark, (x1, y, z), (0.12, 0.060, w + 0.015))
            # Lower pushing face wear shoe
            add_box(bm_green, (x1 + 0.02, LUG_TIP_Y + 0.05, z), (0.03, 0.10, 0.07))

# Function to build 180° chain wrap around end sprockets
def build_wrap_strand(xc, yc, z, r_pitch, num_teeth, is_left_tail=True):
    # Over 180° arc: num_teeth // 2 steps
    steps = num_teeth // 2
    delta_th = math.pi / steps
    start_th = math.pi * 0.5 if is_left_tail else -math.pi * 0.5
    dir_sign = 1.0 if is_left_tail else 1.0
    
    for s in range(steps):
        th1 = start_th + dir_sign * (s * delta_th)
        th2 = start_th + dir_sign * ((s + 1) * delta_th)
        p1 = (xc + r_pitch * math.cos(th1), yc + r_pitch * math.sin(th1))
        p2 = (xc + r_pitch * math.cos(th2), yc + r_pitch * math.sin(th2))
        is_outer = (s % 2 == 1)
        w = 0.052 if is_outer else 0.036
        
        # Dogbone side plates along arc
        add_dogbone_plate(bm_dark, p1, p2, z - w * 0.5, 0.006)
        add_dogbone_plate(bm_dark, p1, p2, z + w * 0.5, 0.006)
        
        # Roller & pin at p1
        add_cyl_direct_z(bm_dark, p1[0], p1[1], z - 0.016, z + 0.016, 0.022, 8)
        add_cyl_direct_z(bm_bright, p1[0], p1[1], z - 0.030, z + 0.030, 0.012, 6)

# --- A. Columns & Structural Frame ---
for i in range(NUM_BAYS + 1):
    x = i * BAY_W
    add_box(bm_green, (x, SUPER_TOP_Y / 2.0, -BAY_D / 2.0), (0.16, SUPER_TOP_Y, 0.16))
    add_box(bm_green, (x, SUPER_TOP_Y / 2.0,  BAY_D / 2.0), (0.16, SUPER_TOP_Y, 0.16))
    add_box(bm_galv, (x, 0.02, -BAY_D / 2.0), (0.34, 0.04, 0.34))
    add_box(bm_galv, (x, 0.02,  BAY_D / 2.0), (0.34, 0.04, 0.34))
    add_box(bm_green, (x, SUPER_TOP_Y - 0.10, 0.0), (0.14, 0.20, BAY_D))
    add_box(bm_green, (x, 2.60, -BAY_D / 2.0 + 0.05), (0.12, 0.12, 0.10))
    add_box(bm_green, (x, 2.60,  BAY_D / 2.0 - 0.05), (0.12, 0.12, 0.10))
    add_box(bm_dark, (x, 2.20, -BAY_D / 2.0 + 0.12), (0.08, 4.20, 0.08))
    add_box(bm_dark, (x, 2.20,  BAY_D / 2.0 - 0.12), (0.08, 4.20, 0.08))
    
    # Divider Containment Walls (Truncated at DIVIDER_BOTTOM_Y = 1.60m, top at Y = 4.10m below slide plane)
    slat_h = 4.10 - DIVIDER_BOTTOM_Y
    slat_mid_y = (4.10 + DIVIDER_BOTTOM_Y) / 2.0
    for z_slat in [-2.4, -1.8, -1.2, -0.6, 0.0, 0.6, 1.2, 1.8, 2.4]:
        add_box(bm_green, (x, slat_mid_y, z_slat), (0.06, slat_h, 0.06))
    add_box(bm_green, (x, 4.10,             0.0), (0.08, 0.08, 5.0))
    add_box(bm_green, (x, DIVIDER_BOTTOM_Y, 0.0), (0.08, 0.08, 5.0))

    # Fixed longitudinal slide rail transition saddles over boundary X = x
    for z_rail in SLIDE_RAILS:
        add_box(bm_galv, (x, TRANSPORT_Y - 0.025, z_rail), (0.16, 0.035, 0.08))
        add_box(bm_uhmw, (x, TRANSPORT_Y - 0.005, z_rail), (0.16, 0.010, 0.07))

    if i < NUM_BAYS and (i % 10 == 0 or i == NUM_BAYS - 1):
        for side in [-BAY_D / 2.0, BAY_D / 2.0]:
            add_box(bm_green, (x + BAY_W / 2.0, SUPER_TOP_Y / 2.0, side), 
                    (math.hypot(BAY_W, SUPER_TOP_Y), 0.08, 0.08))

# Longitudinal Superstructure Girders
add_box(bm_green, (TOTAL_L / 2.0, SUPER_TOP_Y, -BAY_D / 2.0), (TOTAL_L + 1.2, 0.20, 0.16))
add_box(bm_green, (TOTAL_L / 2.0, SUPER_TOP_Y,  BAY_D / 2.0), (TOTAL_L + 1.2, 0.20, 0.16))

# Catwalk System
CW_Z = BAY_D / 2.0 + 0.60
CW_Y = 4.60
add_box(bm_yellow, (TOTAL_L / 2.0, CW_Y, CW_Z), (TOTAL_L + 1.6, 0.05, 0.90))
add_box(bm_yellow, (TOTAL_L / 2.0, CW_Y + 1.10, CW_Z + 0.42), (TOTAL_L + 1.6, 0.04, 0.04))
add_box(bm_yellow, (TOTAL_L / 2.0, CW_Y + 0.55, CW_Z + 0.42), (TOTAL_L + 1.6, 0.03, 0.03))
add_box(bm_yellow, (TOTAL_L / 2.0, CW_Y + 0.10, CW_Z + 0.42), (TOTAL_L + 1.6, 0.15, 0.015))
for i in range(0, NUM_BAYS + 1, 2):
    x = i * BAY_W
    add_box(bm_green,  (x, CW_Y - 0.12, BAY_D / 2.0 + 0.35), (0.10, 0.18, 0.70))
    add_box(bm_yellow, (x, CW_Y + 0.55, CW_Z + 0.42),        (0.05, 1.10, 0.05))
for x_lad in [-0.8, TOTAL_L + 0.8]:
    add_box(bm_yellow, (x_lad, CW_Y / 2.0, CW_Z + 0.30), (0.05, CW_Y, 0.05))
    add_box(bm_yellow, (x_lad, CW_Y / 2.0, CW_Z - 0.30), (0.05, CW_Y, 0.05))
    for r_i in range(13):
        rung_y = 0.35 * (r_i + 1)
        if rung_y < CW_Y:
            add_cyl(bm_yellow, (x_lad, rung_y, CW_Z), 0.015, 0.55, 'Z')

# --- B. Overhead Continuous Roller Chains & Guide Races ---
X_TAIL = -0.70
X_HEAD = TOTAL_L + 0.70

for z_tr in OVERHEAD_CHAINS:
    # 1. Upper Return Guide Race:
    # CRITICAL: Sits UNDER the return chain so chain rides ON TOP of race!
    # Chain roller bottom is at CHAIN_RETURN_Y - 0.022 = 5.302m
    race_top_y = CHAIN_RETURN_Y - 0.022
    add_box(bm_galv, (TOTAL_L / 2.0, race_top_y - 0.035, z_tr), (TOTAL_L + 1.2, 0.05, 0.10))
    # Low-friction UHMW wear strip on top of race
    add_box(bm_uhmw, (TOTAL_L / 2.0, race_top_y - 0.005, z_tr), (TOTAL_L + 1.2, 0.010, 0.08))

    # 2. Lower Working Hold-down Guide Track:
    # Positioned above the lower working chain to prevent lifting while pushing lumber
    hold_bot_y = CHAIN_WORK_Y + 0.022
    add_box(bm_galv, (TOTAL_L / 2.0, hold_bot_y + 0.025, z_tr), (TOTAL_L + 1.2, 0.04, 0.10))

    # Dynamic overhead roller chains with downward lugs are animated by SorterChainSystem

# Infeed approach glide rails at X = -0.6 to 0.0 at TRANSPORT_Y = 4.30m
for z_rail in SLIDE_RAILS:
    add_box(bm_galv, (-0.30, TRANSPORT_Y - 0.025, z_rail), (0.60, 0.035, 0.08))
    add_box(bm_uhmw, (-0.30, TRANSPORT_Y - 0.005, z_rail), (0.60, 0.010, 0.07))


# --- C. Lowered 5-Strand Floor Haul-Out Drag Chain Conveyor ---
X_HD_TAIL = -0.70
X_HD_HEAD = TOTAL_L + 1.20
PITCH_HD = 0.1047

for z_tr in HAULOUT_CHAINS:
    # Open galvanized floor race
    add_box(bm_galv, (TOTAL_L / 2.0, HAULOUT_Y - 0.07, z_tr), (TOTAL_L + 2.2, 0.10, 0.14))
    # Dynamic floor haul-out roller chains are animated by SorterChainSystem

# --- D. Heavy Shaft Support Hardware (Pillow Block Bearings) ---
for end_z in [-2.55, 2.55]:
    # Top Overhead Tail Shaft Bearings
    add_pillow_block_bearing(bm_green, bm_bright, (X_TAIL, OVERHEAD_SHAFT_Y, end_z), 0.050, 'left')
    # Top Overhead Drive Shaft Bearings
    add_pillow_block_bearing(bm_green, bm_bright, (X_HEAD, OVERHEAD_SHAFT_Y, end_z), 0.050, 'right')
    # Haul-Out Tail Shaft Bearings
    add_pillow_block_bearing(bm_green, bm_bright, (X_HD_TAIL, HAULOUT_SHAFT_Y, end_z), 0.045, 'left')
    # Haul-Out Drive Shaft Bearings
    add_pillow_block_bearing(bm_green, bm_bright, (X_HD_HEAD, HAULOUT_SHAFT_Y, end_z), 0.045, 'right')

# Overhead Motor Drive Package
add_box(bm_green, (X_HEAD + 0.35, OVERHEAD_SHAFT_Y - 0.15, 2.5), (0.50, 0.45, 0.40))
add_cyl(bm_green, (X_HEAD + 0.35, OVERHEAD_SHAFT_Y - 0.15, 2.9), 0.20, 0.48, 'Z')
add_box(bm_yellow,(X_HEAD + 0.35, OVERHEAD_SHAFT_Y,        2.4), (0.38, 0.35, 0.52))

# Lowered Haul-Out Motor Drive Package
add_cyl(bm_green, (X_HD_HEAD + 0.25, HAULOUT_SHAFT_Y, 2.5), 0.16, 0.42, 'Z')
add_box(bm_green, (X_HD_HEAD + 0.25, HAULOUT_SHAFT_Y, 2.2), (0.38, 0.28, 0.30))

# Consolidate Static Meshes
mesh_green  = mesh_from_bmesh('Structure_ForestGreen', bm_green, paint_green)
mesh_yellow = mesh_from_bmesh('Structure_SafetyYellow', bm_yellow, yellow)
mesh_galv   = mesh_from_bmesh('Structure_GalvanizedSteel', bm_galv, galvanized)
mesh_dark   = mesh_from_bmesh('Structure_OiledSteel', bm_dark, dark_steel)
mesh_bright = mesh_from_bmesh('Structure_BrightPins', bm_bright, bright_steel)
mesh_uhmw   = mesh_from_bmesh('Structure_UHMWWearStrips', bm_uhmw, uhmw_white)

obj_green  = obj_from_mesh('Structure_ForestGreen', mesh_green)
obj_yellow = obj_from_mesh('Structure_SafetyYellow', mesh_yellow)
obj_galv   = obj_from_mesh('Structure_GalvanizedSteel', mesh_galv)
obj_dark   = obj_from_mesh('Structure_OiledSteel', mesh_dark)
obj_bright = obj_from_mesh('Structure_BrightPins', mesh_bright)
obj_uhmw   = obj_from_mesh('Structure_UHMWWearStrips', mesh_uhmw)

static_objects = [obj_green, obj_yellow, obj_galv, obj_dark, obj_bright, obj_uhmw]

# -----------------------------------------------------------------------------
# 4. ROTATING SHAFTS & SPROCKETS (4 Animatable Common Cross Shafts)
# -----------------------------------------------------------------------------
shaft_objects = []

# Top Overhead Drive Shaft with Real Tooth Sprockets
bm_td = bmesh.new()
add_cyl_direct_z(bm_td, 0.0, 0.0, -2.55, 2.55, 0.050, 16)
for z_tr in OVERHEAD_CHAINS:
    add_sprocket_with_teeth(bm_td, (0.0, 0.0, z_tr), R_OVERHEAD, OVERHEAD_TEETH, 0.032)
mesh_td = mesh_from_bmesh('TopDriveShaftMesh', bm_td, bright_steel)
obj_td = obj_from_mesh('TopDriveShaft', mesh_td, (X_HEAD, OVERHEAD_SHAFT_Y, 0.0))
shaft_objects.append(obj_td)

# Top Overhead Tail Shaft with Real Tooth Sprockets
bm_tt = bmesh.new()
add_cyl_direct_z(bm_tt, 0.0, 0.0, -2.55, 2.55, 0.050, 16)
for z_tr in OVERHEAD_CHAINS:
    add_sprocket_with_teeth(bm_tt, (0.0, 0.0, z_tr), R_OVERHEAD, OVERHEAD_TEETH, 0.032)
mesh_tt = mesh_from_bmesh('TopTailShaftMesh', bm_tt, bright_steel)
obj_tt = obj_from_mesh('TopTailShaft', mesh_tt, (X_TAIL, OVERHEAD_SHAFT_Y, 0.0))
shaft_objects.append(obj_tt)

# Lowered Haul-Out Drive Shaft with Real Tooth Sprockets
bm_hd = bmesh.new()
add_cyl_direct_z(bm_hd, 0.0, 0.0, -2.55, 2.55, 0.045, 16)
for z_tr in HAULOUT_CHAINS:
    add_sprocket_with_teeth(bm_hd, (0.0, 0.0, z_tr), R_HAULOUT, HAULOUT_TEETH, 0.028)
mesh_hd = mesh_from_bmesh('HaulOutDriveShaftMesh', bm_hd, bright_steel)
obj_hd = obj_from_mesh('HaulOutDriveShaft', mesh_hd, (X_HD_HEAD, HAULOUT_SHAFT_Y, 0.0))
shaft_objects.append(obj_hd)

# Lowered Haul-Out Tail Shaft with Real Tooth Sprockets
bm_ht = bmesh.new()
add_cyl_direct_z(bm_ht, 0.0, 0.0, -2.55, 2.55, 0.045, 16)
for z_tr in HAULOUT_CHAINS:
    add_sprocket_with_teeth(bm_ht, (0.0, 0.0, z_tr), R_HAULOUT, HAULOUT_TEETH, 0.028)
mesh_ht = mesh_from_bmesh('HaulOutTailShaftMesh', bm_ht, bright_steel)
obj_ht = obj_from_mesh('HaulOutTailShaft', mesh_ht, (X_HD_TAIL, HAULOUT_SHAFT_Y, 0.0))
shaft_objects.append(obj_ht)

# -----------------------------------------------------------------------------
# 5. INSTANCE 50 CARRIAGES & 50 DIVERTER GATES
# -----------------------------------------------------------------------------
carriage_objects = []
gate_objects = []

for b in range(NUM_BAYS):
    c_obj = bpy.data.objects.new(f'Carriage_{b:02d}', carr_mesh)
    c_obj.location = xyz((b * BAY_W + 0.50, CARRIAGE_REST_Y, 0.0))
    bpy.context.collection.objects.link(c_obj)
    carriage_objects.append(c_obj)
    
    g_obj = bpy.data.objects.new(f'Gate_{b:02d}', gate_mesh)
    g_obj.location = xyz((b * BAY_W + BAY_W - 0.08, TRANSPORT_Y, 0.0))
    bpy.context.collection.objects.link(g_obj)
    gate_objects.append(g_obj)

all_objects = static_objects + shaft_objects + gate_objects + carriage_objects

print(f"Assembly complete: {len(all_objects)} total objects "
      f"({len(static_objects)} static meshes, {len(shaft_objects)} shafts, "
      f"{len(gate_objects)} gates, {len(carriage_objects)} carriages)")

# -----------------------------------------------------------------------------
# 6. EXPORT FULL ASSEMBLY TO GLB & BLEND
# -----------------------------------------------------------------------------
glb_path = os.path.join(OUT, 'bin_sorter_frame.glb')
export(glb_path, all_objects)
print("EXPORTED GLB:", glb_path)

bpy.context.scene.unit_settings.system = 'METRIC'
blend_path = os.path.join(OUT, 'bin_sorter.blend')
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print("SAVED BLEND:", blend_path)
t1 = time.time()
print(f"BIN_SORTER_BUILD_SUCCESS in {t1 - t0:.2f} seconds.")
