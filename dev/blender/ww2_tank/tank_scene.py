"""Ground, sky, sun, camera and render settings for the tank beauty shot."""
import math

import bpy
from mathutils import Vector

import tank_lib as L

COLL = "Tank_Scene"


def build(materials, engine='CYCLES', samples=128, res=(1920, 1080)):
    L.clear_collection(COLL)
    coll = L.collection(COLL)
    scene = bpy.context.scene

    ground = build_ground(coll, materials["ground"])
    build_vegetation(ground, coll, materials)
    far_me = bpy.data.meshes.new("GroundFar")
    s = 800.0
    far_me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    far_me.materials.append(materials["ground"])
    far = bpy.data.objects.new("GroundFar", far_me)
    coll.objects.link(far)
    far.location.z = -0.005

    # Sky and sun.
    world = bpy.data.worlds.get("Tank_World") or bpy.data.worlds.new("Tank_World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new('ShaderNodeTexSky')
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_disc = False
    sky.sun_elevation = math.radians(28)
    sky.sun_rotation = math.radians(-35)
    bg = nt.nodes.new('ShaderNodeBackground')
    bg.inputs['Strength'].default_value = 0.12
    out = nt.nodes.new('ShaderNodeOutputWorld')
    nt.links.new(sky.outputs['Color'], bg.inputs['Color'])
    nt.links.new(bg.outputs['Background'], out.inputs['Surface'])

    sun_data = bpy.data.lights.new("Sun", 'SUN')
    sun_data.energy = 3.2
    sun_data.angle = math.radians(1.5)
    sun_data.color = (1.0, 0.95, 0.88)
    sun = bpy.data.objects.new("Sun", sun_data)
    coll.objects.link(sun)
    sun.rotation_euler = (math.radians(90 - 28), 0, math.radians(-35 + 90))

    # Camera aimed at the tank's front three-quarter.
    target = bpy.data.objects.new("CameraTarget", None)
    coll.objects.link(target)
    target.location = (0.1, 0.0, 1.05)
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 45
    cam_data.dof.use_dof = True
    cam_data.dof.focus_object = target
    cam_data.dof.aperture_fstop = 8.0
    cam = bpy.data.objects.new("Camera", cam_data)
    coll.objects.link(cam)
    cam.location = (8.6, 6.4, 1.55)
    track = cam.constraints.new('TRACK_TO')
    track.target = target
    scene.camera = cam

    # Render settings.
    scene.render.engine = engine
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    if engine == 'CYCLES':
        prefs = bpy.context.preferences.addons['cycles'].preferences
        scene.cycles.device = 'GPU' if prefs.compute_device_type != 'NONE' else 'CPU'
        scene.cycles.samples = samples
        scene.cycles.use_denoising = True
        scene.cycles.max_bounces = 6
    vs = scene.view_settings
    vs.view_transform = 'AgX'
    for look in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        try:
            vs.look = look
            break
        except TypeError:
            pass
    vs.exposure = 0.0
    return {"camera": cam.name, "engine": scene.render.engine}


def _smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def build_ground(coll, material, size=40.0, segs=400, track_y=1.10, half_w=0.22, depth=0.04):
    """Dirt patch with the tank's own track ruts leading up to it."""
    import bmesh
    me = bpy.data.meshes.new("Ground")
    ground = bpy.data.objects.new("Ground", me)
    coll.objects.link(ground)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=segs, y_segments=segs, size=size / 2)
    bm.to_mesh(me)
    bm.free()
    from mathutils import noise
    rut = me.attributes.new("rut", 'FLOAT', 'POINT')
    group = ground.vertex_groups.new(name="displace")
    grass_group = ground.vertex_groups.new(name="grass")
    edge = size / 2
    weights = []
    grass_w = []
    for i, v in enumerate(me.vertices):
        x, y = v.co.x, v.co.y
        d = abs(abs(y) - track_y)
        along = _smoothstep(2.9, 2.4, x) * _smoothstep(-edge, -edge + 6, x)
        trough = _smoothstep(half_w + 0.03, half_w - 0.05, d) * along
        berm = _smoothstep(half_w + 0.2, half_w + 0.08, d) * _smoothstep(half_w - 0.02, half_w + 0.08, d) * along
        v.co.z = -depth * trough + 0.025 * berm
        rut.data[i].value = max(trough, 0.6 * berm)
        r = max(abs(x), abs(y))
        weights.append(_smoothstep(edge, edge - 4, r) * (1.0 - 0.7 * trough))
        # Grass grows in patches, avoids the ruts and the ground under the tank.
        patch = _smoothstep(-0.1, 0.35, noise.noise(Vector((x * 0.35, y * 0.35, 0.0))))
        under = _smoothstep(1.0, 0.0, max(abs(x) - 3.0, abs(y) - 1.35))
        lane = _smoothstep(0.55, 0.0, d) * along
        grass_w.append(patch * (1.0 - under) * (1.0 - lane) * _smoothstep(edge, edge - 1, r))
    for i, w in enumerate(weights):
        group.add([i], w, 'REPLACE')
    for i, w in enumerate(grass_w):
        if w > 0.0:
            grass_group.add([i], w, 'REPLACE')
    me.shade_smooth()
    me.materials.append(material)
    tex = bpy.data.textures.get("GroundBumps") or bpy.data.textures.new("GroundBumps", 'CLOUDS')
    tex.noise_scale = 1.4
    tex.noise_depth = 4
    disp = ground.modifiers.new("Displace", 'DISPLACE')
    disp.texture = tex
    disp.texture_coords = 'GLOBAL'
    disp.strength = 0.1
    disp.mid_level = 0.5
    disp.vertex_group = "displace"
    return ground


def build_vegetation(ground, coll, materials, grass_count=90000, pebble_count=6000):
    import bmesh
    from mathutils import noise
    me = ground.data
    me.materials.append(materials["grass"])

    # Dry grass tufts.
    ground.modifiers.new("Grass", 'PARTICLE_SYSTEM')
    psys = ground.particle_systems[-1]
    ps = psys.settings
    ps.name = "Grass"
    ps.type = 'HAIR'
    ps.use_advanced_hair = False  # advanced mode takes length from emit velocity, not hair_length
    ps.count = grass_count
    ps.hair_length = 0.14
    ps.emit_from = 'FACE'
    ps.use_emit_random = True
    ps.material_slot = materials["grass"].name
    ps.child_type = 'INTERPOLATED'
    ps.child_percent = 3
    ps.rendered_child_count = 10
    ps.child_radius = 0.04
    ps.clump_factor = 0.5
    ps.roughness_1 = 0.03
    ps.roughness_endpoint = 0.04
    ps.roughness_2 = 0.03
    ps.child_length = 0.7
    ps.child_length_threshold = 0.4
    ps.normal_factor = 1.0
    ps.factor_random = 0.04
    ps.brownian_factor = 0.0
    ps.radius_scale = 0.004
    ps.root_radius = 1.0
    ps.tip_radius = 0.0
    psys.vertex_group_density = "grass"
    psys.vertex_group_length = "grass"
    psys.seed = 7

    # Pebbles scattered over the dirt.
    peb_coll = L.collection("Pebbles", coll)
    peb_coll.hide_render = False
    variants = []
    for k in range(4):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
        for v in bm.verts:
            v.co *= 1.0 + 0.35 * noise.noise(v.co * 1.3 + Vector((k * 3.1, 0, 0)))
            v.co.z *= 0.55
        pm = bpy.data.meshes.new("Pebble_%d" % k)
        bm.to_mesh(pm)
        bm.free()
        pm.shade_smooth()
        pm.materials.append(materials["stone"])
        po = bpy.data.objects.new("Pebble_%d" % k, pm)
        peb_coll.objects.link(po)
        po.location = (0, 0, -50)
        variants.append(po)
    ground.modifiers.new("Pebbles", 'PARTICLE_SYSTEM')
    psys = ground.particle_systems[-1]
    ps = psys.settings
    ps.name = "Pebbles"
    ps.type = 'HAIR'
    ps.count = pebble_count
    ps.hair_length = 0.02
    ps.render_type = 'COLLECTION'
    ps.instance_collection = peb_coll
    ps.use_collection_pick_random = True
    ps.particle_size = 0.025
    ps.size_random = 0.8
    ps.use_rotations = True
    ps.rotation_mode = 'NOR'
    ps.phase_factor_random = 2.0
    ps.use_rotation_instance = False
    psys.vertex_group_density = "displace"
    psys.seed = 3
    return {"grass": grass_count, "pebbles": pebble_count}


def add_camera(name, loc, target_loc, lens=45):
    coll = L.collection(COLL)
    target = bpy.data.objects.new(name + "_Target", None)
    coll.objects.link(target)
    target.location = target_loc
    data = bpy.data.cameras.new(name)
    data.lens = lens
    cam = bpy.data.objects.new(name, data)
    coll.objects.link(cam)
    cam.location = loc
    c = cam.constraints.new('TRACK_TO')
    c.target = target
    return cam
