"""Rig for the procedural Sherman.

Controls live as custom properties on the ``Tank_Controls`` empty:

- ``turret_yaw``     degrees, positive turns the turret left
- ``gun_elevation``  degrees, -10 (depressed) to +25
- ``gun_recoil``     0..1, slides the barrel back 32 cm
- ``travel``         metres driven; key it alongside the root's movement
- ``steer``          metres added to the left track and taken from the right
                     (positive turns right; travel 0 + steer = pivot turn)

Wheels, rollers, sprockets and idlers spin from those values at their own
radii, and the Geometry Nodes track links run around the loop so the lower
run stays planted on the ground.
"""
import math

import bpy

import tank_build as B

TRACK_NG = "TankTrackLinks"
CONTROLS = "Tank_Controls"

# Rolling radius of each kind of wheel against the track.
RADII = {"RoadWheel": B.WHEEL_R, "Roller": 0.11, "Sprocket": B.SPROCKET[2], "Idler": B.IDLER[2]}


def track_node_group():
    ng = bpy.data.node_groups.get(TRACK_NG)
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new(TRACK_NG, 'GeometryNodeTree')
    ng.is_modifier = True
    iface = ng.interface
    iface.new_socket("Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
    iface.new_socket("Offset", in_out='INPUT', socket_type='NodeSocketFloat')
    count = iface.new_socket("Count", in_out='INPUT', socket_type='NodeSocketInt')
    count.default_value = 83
    count.min_value = 1
    iface.new_socket("Path", in_out='INPUT', socket_type='NodeSocketObject')
    iface.new_socket("Link", in_out='INPUT', socket_type='NodeSocketObject')
    iface.new_socket("Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')

    n, lk = ng.nodes, ng.links
    gi = n.new('NodeGroupInput')
    go = n.new('NodeGroupOutput')

    def math_node(op, a, b):
        m = n.new('ShaderNodeMath')
        m.operation = op
        for sock, val in ((m.inputs[0], a), (m.inputs[1], b)):
            if isinstance(val, bpy.types.NodeSocket):
                lk.new(val, sock)
            else:
                sock.default_value = val
        return m.outputs[0]

    path = n.new('GeometryNodeObjectInfo')
    path.transform_space = 'RELATIVE'
    lk.new(gi.outputs['Path'], path.inputs['Object'])
    link = n.new('GeometryNodeObjectInfo')
    link.transform_space = 'ORIGINAL'
    lk.new(gi.outputs['Link'], link.inputs['Object'])
    length = n.new('GeometryNodeCurveLength')
    lk.new(path.outputs['Geometry'], length.inputs['Curve'])

    # One point per link, spaced evenly and shifted along the loop by Offset.
    pts = n.new('GeometryNodePoints')
    lk.new(gi.outputs['Count'], pts.inputs['Count'])
    index = n.new('GeometryNodeInputIndex')
    step = math_node('DIVIDE', length.outputs['Length'], gi.outputs['Count'])
    dist = math_node('ADD', math_node('MULTIPLY', index.outputs['Index'], step), gi.outputs['Offset'])
    dist = math_node('FLOORED_MODULO', dist, length.outputs['Length'])
    sample = n.new('GeometryNodeSampleCurve')
    sample.mode = 'LENGTH'
    sample.use_all_curves = False
    lk.new(path.outputs['Geometry'], sample.inputs['Curves'])
    lk.new(dist, sample.inputs['Length'])
    setpos = n.new('GeometryNodeSetPosition')
    lk.new(pts.outputs['Points'], setpos.inputs['Geometry'])
    lk.new(sample.outputs['Position'], setpos.inputs['Position'])

    # Link X along the tangent, Z out of the loop (the loop is planar in XZ).
    sep = n.new('ShaderNodeSeparateXYZ')
    lk.new(sample.outputs['Tangent'], sep.inputs[0])
    outward = n.new('ShaderNodeCombineXYZ')
    lk.new(sep.outputs['Z'], outward.inputs['X'])
    lk.new(math_node('MULTIPLY', sep.outputs['X'], -1.0), outward.inputs['Z'])
    align_x = n.new('FunctionNodeAlignRotationToVector')
    align_x.axis = 'X'
    lk.new(sample.outputs['Tangent'], align_x.inputs['Vector'])
    align_z = n.new('FunctionNodeAlignRotationToVector')
    align_z.axis = 'Z'
    align_z.pivot_axis = 'X'
    lk.new(align_x.outputs['Rotation'], align_z.inputs['Rotation'])
    lk.new(outward.outputs['Vector'], align_z.inputs['Vector'])

    inst = n.new('GeometryNodeInstanceOnPoints')
    lk.new(setpos.outputs['Geometry'], inst.inputs['Points'])
    lk.new(link.outputs['Geometry'], inst.inputs['Instance'])
    lk.new(align_z.outputs['Rotation'], inst.inputs['Rotation'])
    realize = n.new('GeometryNodeRealizeInstances')
    lk.new(inst.outputs['Instances'], realize.inputs['Geometry'])
    lk.new(realize.outputs['Geometry'], go.inputs['Geometry'])
    for i, node in enumerate(n):
        node.location = (i * 180, 0)
    return ng


def _socket_id(ng, name):
    for item in ng.interface.items_tree:
        if getattr(item, "in_out", None) == 'INPUT' and item.name == name:
            return item.identifier
    raise KeyError(name)


def add_track_modifier(track, path, link, count):
    ng = track_node_group()
    md = track.modifiers.new("TrackLinks", 'NODES')
    md.node_group = ng
    md[_socket_id(ng, "Count")] = count
    md[_socket_id(ng, "Path")] = path
    md[_socket_id(ng, "Link")] = link
    return md


def _prop(obj, name, default, lo, hi, desc, soft=None):
    obj[name] = default
    ui = obj.id_properties_ui(name)
    kw = dict(min=lo, max=hi, description=desc, default=default)
    if soft:
        kw.update(soft_min=soft[0], soft_max=soft[1])
    ui.update(**kw)


def make_controls(root):
    ctl = bpy.data.objects.get(CONTROLS)
    if ctl is None:
        ctl = bpy.data.objects.new(CONTROLS, None)
        root.users_collection[0].objects.link(ctl)
    ctl.empty_display_type = 'SINGLE_ARROW'
    ctl.empty_display_size = 1.2
    ctl.location = (0, 0, 3.3)
    ctl.parent = root
    ctl.matrix_parent_inverse = root.matrix_world.inverted()
    _prop(ctl, "turret_yaw", 0.0, -360.0, 360.0, "Turret traverse in degrees (positive = left)", (-180, 180))
    _prop(ctl, "gun_elevation", 0.0, -10.0, 25.0, "Gun elevation in degrees")
    _prop(ctl, "gun_recoil", 0.0, 0.0, 1.0, "Barrel recoil (0 = battery, 1 = full recoil)")
    _prop(ctl, "travel", 0.0, -1e6, 1e6, "Distance driven in metres; key it with the root's movement", (-50, 50))
    _prop(ctl, "steer", 0.0, -1e6, 1e6, "Extra metres on the left track, minus on the right (positive turns right)", (-10, 10))
    return ctl


def _drive(obj, path, index, expr, ctl, props):
    obj.driver_remove(path, index)
    fc = obj.driver_add(path, index)
    drv = fc.driver
    drv.type = 'SCRIPTED'
    for prop in props:
        var = drv.variables.new()
        var.name = prop
        var.type = 'SINGLE_PROP'
        var.targets[0].id = ctl
        var.targets[0].data_path = '["%s"]' % prop
    drv.expression = expr
    return fc


def add_drivers(ctl):
    objs = bpy.data.objects
    _drive(objs["Turret"], "rotation_euler", 2, "radians(turret_yaw)", ctl, ["turret_yaw"])
    _drive(objs["Gun"], "rotation_euler", 1, "-radians(gun_elevation)", ctl, ["gun_elevation"])
    _drive(objs["GunBarrel"], "location", 0, "-0.32 * gun_recoil", ctl, ["gun_recoil"])

    count = 0
    for obj in objs:
        kind = next((k for k in RADII if obj.name.startswith(k + "_") or obj.name.endswith("_" + k)), None)
        if kind is None or obj.hide_render:
            continue
        left = obj.location.y > 0
        r = RADII[kind]
        # Right-side parts are turned 180 degrees about Z, which flips their spin axis.
        expr = "(travel + steer) / %.4f" % r if left else "-(travel - steer) / %.4f" % r
        _drive(obj, "rotation_euler", 1, expr, ctl, ["travel", "steer"])
        count += 1

    ng = bpy.data.node_groups[TRACK_NG]
    off = _socket_id(ng, "Offset")
    for side, expr in (("L", "-(travel + steer)"), ("R", "-(travel - steer)")):
        _drive(objs["Track_" + side], 'modifiers["TrackLinks"]["%s"]' % off, -1, expr, ctl, ["travel", "steer"])
    return count


def demo_animation(ctl, root, frames=240):
    """Drive 10 m up the ruts, traverse toward the camera, elevate and fire."""
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, frames
    scene.render.fps = 24
    for obj in (ctl, root):
        obj.animation_data_clear()

    def key(obj, path, frame, value, index=-1):
        if index >= 0:
            getattr(obj, path)[index] = value
            obj.keyframe_insert(path, index=index, frame=frame)
        else:
            obj[path] = value
            obj.keyframe_insert('["%s"]' % path, frame=frame)

    drive_end = 150
    key(root, "location", 1, -10.0, 0)
    key(root, "location", drive_end, 0.0, 0)
    key(ctl, "travel", 1, 0.0)
    key(ctl, "travel", drive_end, 10.0)
    key(ctl, "turret_yaw", 110, 0.0)
    key(ctl, "turret_yaw", 190, 28.0)
    key(ctl, "gun_elevation", 130, 0.0)
    key(ctl, "gun_elevation", 195, 4.0)
    key(ctl, "gun_recoil", 212, 0.0)
    key(ctl, "gun_recoil", 214, 1.0)
    key(ctl, "gun_recoil", 230, 0.0)
    # Recoil snaps back instantly and returns slowly.
    for fc in ctl.animation_data.action.fcurves if hasattr(ctl.animation_data.action, "fcurves") else []:
        if "gun_recoil" in fc.data_path:
            fc.keyframe_points[1].interpolation = 'LINEAR'
            fc.keyframe_points[0].interpolation = 'LINEAR'
    scene.frame_set(1)


def rig():
    root = bpy.data.objects["M4A3_Sherman_Root"]
    ctl = make_controls(root)
    spinning = add_drivers(ctl)
    demo_animation(ctl, root)
    return {"controls": ctl.name, "spinning_parts": spinning}
