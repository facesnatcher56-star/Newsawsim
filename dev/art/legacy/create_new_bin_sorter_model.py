import bpy
import os
import math

def create_mat(name, color, metallic=0.6, roughness=0.35, emission=(0, 0, 0)):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs['Base Color'].default_value = color
        bsdf.inputs['Metallic'].default_value = metallic
        bsdf.inputs['Roughness'].default_value = roughness
        if 'Emission' in bsdf.inputs and any(emission):
            bsdf.inputs['Emission'].default_value = (emission[0], emission[1], emission[2], 1.0)
    return mat

def add_box(name, location, size, material=None, rotation=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    bpy.ops.object.transform_apply(scale=True)
    if material:
        obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    return obj

def add_cylinder(name, location, radius, depth, rotation=(0, 0, 0), material=None, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    return obj

def build_new_bin_sorter():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()

    # Create Materials
    mat_green = create_mat("IndustrialGreen", (0.16, 0.36, 0.22, 1.0), metallic=0.7, roughness=0.35)
    mat_yellow = create_mat("SafetyYellow", (0.92, 0.76, 0.08, 1.0), metallic=0.4, roughness=0.4)
    mat_orange = create_mat("SafetyOrange", (0.92, 0.42, 0.08, 1.0), metallic=0.5, roughness=0.35)
    mat_dark_steel = create_mat("DarkSteel", (0.14, 0.16, 0.18, 1.0), metallic=0.85, roughness=0.25)
    mat_chrome = create_mat("Chrome", (0.85, 0.88, 0.90, 1.0), metallic=0.95, roughness=0.1)
    mat_red_led = create_mat("RedLED", (0.9, 0.1, 0.05, 1.0), metallic=0.2, roughness=0.2, emission=(1.0, 0.1, 0.05))
    mat_green_led = create_mat("GreenLED", (0.1, 0.9, 0.2, 1.0), metallic=0.2, roughness=0.2, emission=(0.1, 1.0, 0.2))

    num_bins = 10
    bin_w = 0.9
    bin_depth = 5.5
    sorter_h = 4.0
    total_len = num_bins * bin_w + 1.2

    root_obj = bpy.data.objects.new("NewBinSorterModel", None)
    bpy.context.collection.objects.link(root_obj)

    # 1. Structural Gantry
    gantry_parent = bpy.data.objects.new("GantryStructure", None)
    gantry_parent.parent = root_obj
    bpy.context.collection.objects.link(gantry_parent)

    column_positions_x = [-0.5 + i * bin_w for i in range(num_bins + 1)]
    side_zs = [-bin_depth / 2.0, bin_depth / 2.0]

    for i, x in enumerate(column_positions_x):
        for z in side_zs:
            # Columns
            add_box(f"Col_{i}_Z{z:.1f}", (x, sorter_h / 2.0, z), (0.20, sorter_h, 0.20), mat_green, parent=gantry_parent)
            # Base Foot Plates
            add_box(f"Foot_{i}_Z{z:.1f}", (x, 0.02, z), (0.42, 0.04, 0.42), mat_dark_steel, parent=gantry_parent)

        # Cross Beams at Top
        add_box(f"CrossBeam_{i}", (x, sorter_h, 0), (0.20, 0.24, bin_depth + 0.4), mat_green, parent=gantry_parent)

    # Longitudinal Framing
    for z in side_zs:
        add_box(f"TopHeader_Z{z:.1f}", (total_len / 2.0 - 0.5, sorter_h, z), (total_len, 0.26, 0.20), mat_green, parent=gantry_parent)
        add_box(f"MidTie_Z{z:.1f}", (total_len / 2.0 - 0.5, sorter_h - 1.3, z), (total_len, 0.18, 0.16), mat_green, parent=gantry_parent)
        add_box(f"LowerHauloutRail_Z{z:.1f}", (total_len / 2.0 - 0.5, 0.2, z), (total_len, 0.20, 0.16), mat_dark_steel, parent=gantry_parent)

    # 2. Catwalk & Safety System
    catwalk_parent = bpy.data.objects.new("CatwalkAssembly", None)
    catwalk_parent.parent = root_obj
    bpy.context.collection.objects.link(catwalk_parent)

    catwalk_z = side_zs[1] + 0.6
    catwalk_h = sorter_h - 0.4
    add_box("CatwalkFloorGrate", (total_len / 2.0 - 0.5, catwalk_h, catwalk_z), (total_len + 0.6, 0.06, 0.85), mat_dark_steel, parent=catwalk_parent)
    add_box("SafetyToeKick", (total_len / 2.0 - 0.5, catwalk_h + 0.08, catwalk_z + 0.40), (total_len + 0.6, 0.14, 0.03), mat_yellow, parent=catwalk_parent)

    rail_z = catwalk_z + 0.40
    add_cylinder("HandrailTop", (total_len / 2.0 - 0.5, catwalk_h + 1.05, rail_z), 0.022, total_len + 0.6, rotation=(0, math.pi/2, 0), material=mat_yellow, parent=catwalk_parent)
    add_cylinder("HandrailMid", (total_len / 2.0 - 0.5, catwalk_h + 0.55, rail_z), 0.018, total_len + 0.6, rotation=(0, math.pi/2, 0), material=mat_yellow, parent=catwalk_parent)

    for i, x in enumerate(column_positions_x):
        add_cylinder(f"HandrailPost_{i}", (x, catwalk_h + 0.55, rail_z), 0.022, 1.05, material=mat_yellow, parent=catwalk_parent)

    # Access Ladder
    ladder_x = -0.5
    for r in range(12):
        add_cylinder(f"LadderRung_{r}", (ladder_x, 0.3 * r + 0.15, catwalk_z), 0.014, 0.45, rotation=(math.pi/2, 0, 0), material=mat_yellow, parent=catwalk_parent)
    add_cylinder("LadderSideLeft", (ladder_x, catwalk_h / 2.0 + 0.3, catwalk_z - 0.22), 0.02, catwalk_h + 0.6, material=mat_yellow, parent=catwalk_parent)
    add_cylinder("LadderSideRight", (ladder_x, catwalk_h / 2.0 + 0.3, catwalk_z + 0.22), 0.02, catwalk_h + 0.6, material=mat_yellow, parent=catwalk_parent)

    # 3. Bin Bays, Drop Gates & Indexing Hoppers
    bays_parent = bpy.data.objects.new("BinBays", None)
    bays_parent.parent = root_obj
    bpy.context.collection.objects.link(bays_parent)

    for b in range(num_bins):
        bay_x = b * bin_w
        bay_group = bpy.data.objects.new(f"Bay_{b}", None)
        bay_group.parent = bays_parent
        bpy.context.collection.objects.link(bay_group)

        # Drop Gate Diverter Paddle (Interactive in Godot)
        gate_obj = add_box(f"DropGateFlapper_{b}", (bay_x + 0.35, sorter_h - 0.22, 0), (0.65, 0.05, bin_depth - 0.5), mat_orange, parent=bay_group)
        # Pneumatic Cylinder
        add_cylinder(f"GatePistonCylinder_{b}", (bay_x + 0.35, sorter_h + 0.3, 0), 0.045, 0.42, material=mat_chrome, parent=bay_group)

        # Bin Pocket Divider Posts & Walls
        add_box(f"DividerWallLeft_{b}", (bay_x, sorter_h / 2.0 - 0.4, 0), (0.05, sorter_h - 1.2, bin_depth - 0.3), mat_dark_steel, parent=bay_group)

        # Optical Sensor Beacons (Red & Green Status LEDs)
        add_box(f"SensorBeaconRed_{b}", (bay_x + 0.45, sorter_h + 0.4, side_zs[1] + 0.15), (0.08, 0.12, 0.08), mat_red_led, parent=bay_group)
        add_box(f"SensorBeaconGreen_{b}", (bay_x + 0.45, sorter_h + 0.55, side_zs[1] + 0.15), (0.08, 0.12, 0.08), mat_green_led, parent=bay_group)

    # 4. Overhead Drag Conveyor & Motor Drives
    overhead_parent = bpy.data.objects.new("OverheadConveyor", None)
    overhead_parent.parent = root_obj
    bpy.context.collection.objects.link(overhead_parent)

    track_zs = [-bin_depth * 0.35, -bin_depth * 0.15, 0.0, bin_depth * 0.15, bin_depth * 0.35]
    for idx, tz in enumerate(track_zs):
        add_box(f"TrackChannel_{idx}", (total_len / 2.0 - 0.5, sorter_h + 0.15, tz), (total_len + 0.4, 0.12, 0.10), mat_dark_steel, parent=overhead_parent)
        add_cylinder(f"SprocketInfeed_{idx}", (-0.5, sorter_h + 0.15, tz), 0.16, 0.06, rotation=(math.pi/2, 0, 0), material=mat_dark_steel, parent=overhead_parent)
        add_cylinder(f"SprocketOutfeed_{idx}", (total_len - 0.5, sorter_h + 0.15, tz), 0.16, 0.06, rotation=(math.pi/2, 0, 0), material=mat_dark_steel, parent=overhead_parent)

    # Drive Motor Assembly
    motor_x = total_len - 0.3
    motor_z = side_zs[1] + 0.4
    add_cylinder("DriveMotorCasing", (motor_x, sorter_h + 0.2, motor_z), 0.22, 0.65, rotation=(0, 0, math.pi/2), material=mat_green, parent=overhead_parent)
    add_box("GearboxHousing", (motor_x - 0.3, sorter_h + 0.2, motor_z - 0.2), (0.42, 0.42, 0.48), mat_dark_steel, parent=overhead_parent)
    add_box("JunctionBox", (motor_x, sorter_h + 0.48, motor_z), (0.20, 0.20, 0.16), mat_dark_steel, parent=overhead_parent)

    # Export as GLB
    output_dir = "/home/deck/new-game-project/models"
    os.makedirs(output_dir, exist_ok=True)
    output_filepath = os.path.join(output_dir, "new_bin_sorter.glb")

    bpy.ops.object.select_all(action='DESELECT')
    root_obj.select_set(True)
    for child in root_obj.children_recursive:
        child.select_set(True)

    print(f"Exporting New Bin Sorter GLB to: {output_filepath}")
    bpy.ops.export_scene.gltf(
        filepath=output_filepath,
        export_format='GLB',
        use_selection=True
    )
    print("Export complete!")

if __name__ == "__main__":
    build_new_bin_sorter()
