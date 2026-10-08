import bpy
import os
import math

def create_material(name, color, metallic=0.5, roughness=0.4):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs['Base Color'].default_value = color
        bsdf.inputs['Metallic'].default_value = metallic
        bsdf.inputs['Roughness'].default_value = roughness
    return mat

def add_box(name, location, size, material=None):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    bpy.ops.object.transform_apply(scale=True)
    if material:
        obj.data.materials.append(material)
    return obj

def add_cylinder(name, location, radius, depth, rotation=(0, 0, 0), material=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    return obj

def build_bin_sorter():
    # Clear existing objects
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()

    # Materials
    mat_green = create_material("IndustrialGreen", (0.15, 0.35, 0.22, 1.0), metallic=0.7, roughness=0.35)
    mat_yellow = create_material("SafetyYellow", (0.9, 0.75, 0.08, 1.0), metallic=0.4, roughness=0.4)
    mat_orange = create_material("SafetyOrange", (0.92, 0.42, 0.08, 1.0), metallic=0.5, roughness=0.35)
    mat_dark_steel = create_material("DarkSteel", (0.15, 0.17, 0.20, 1.0), metallic=0.85, roughness=0.25)
    mat_chrome = create_material("Chrome", (0.85, 0.88, 0.90, 1.0), metallic=0.95, roughness=0.1)

    num_bins = 6
    bin_w = 1.0
    bin_depth = 5.5
    sorter_h = 4.0
    total_len = num_bins * bin_w + 1.2

    # Create root collection/parent structure
    root_obj = bpy.data.objects.new("BinSorterModel", None)
    bpy.context.collection.objects.link(root_obj)

    created_objects = []

    # 1. Main Structural Columns & Overhead Framing
    column_positions_x = [-0.5 + i * bin_w for i in range(num_bins + 1)]
    side_zs = [-bin_depth / 2.0, bin_depth / 2.0]

    for x in column_positions_x:
        for z in side_zs:
            # Vertical Column
            col = add_box(f"Column_X{x:.1f}_Z{z:.1f}", (x, sorter_h / 2.0, z), (0.18, sorter_h, 0.18), mat_green)
            created_objects.append(col)

    # Longitudinal Beams (Top and Lower)
    for z in side_zs:
        beam_top = add_box(f"TopBeam_Z{z:.1f}", (total_len / 2.0 - 0.5, sorter_h, z), (total_len, 0.22, 0.18), mat_green)
        beam_mid = add_box(f"MidBeam_Z{z:.1f}", (total_len / 2.0 - 0.5, sorter_h - 1.2, z), (total_len, 0.18, 0.14), mat_green)
        created_objects.append(beam_top)
        created_objects.append(beam_mid)

    # Cross Beams at Top
    for x in column_positions_x:
        cross_beam = add_box(f"CrossBeam_X{x:.1f}", (x, sorter_h, 0), (0.18, 0.22, bin_depth), mat_green)
        created_objects.append(cross_beam)

    # Overhead Chain Track Housings
    track_zs = [-bin_depth * 0.35, -bin_depth * 0.15, 0.0, bin_depth * 0.15, bin_depth * 0.35]
    for idx, tz in enumerate(track_zs):
        track = add_box(f"ChainTrack_{idx}", (total_len / 2.0 - 0.5, sorter_h + 0.15, tz), (total_len + 0.4, 0.12, 0.10), mat_dark_steel)
        created_objects.append(track)

    # 2. Catwalk & Safety Handrails
    catwalk_z = side_zs[1] + 0.6
    catwalk_floor = add_box("CatwalkFloor", (total_len / 2.0 - 0.5, sorter_h - 0.4, catwalk_z), (total_len + 0.6, 0.06, 0.8), mat_dark_steel)
    toe_kick = add_box("CatwalkToeKick", (total_len / 2.0 - 0.5, sorter_h - 0.32, catwalk_z + 0.38), (total_len + 0.6, 0.12, 0.03), mat_yellow)
    created_objects.append(catwalk_floor)
    created_objects.append(toe_kick)

    # Handrail posts & rails
    rail_z = catwalk_z + 0.38
    rail_top = add_cylinder("HandrailTop", (total_len / 2.0 - 0.5, sorter_h + 0.5, rail_z), 0.02, total_len + 0.6, rotation=(0, math.pi/2, 0), material=mat_yellow)
    rail_mid = add_cylinder("HandrailMid", (total_len / 2.0 - 0.5, sorter_h + 0.0, rail_z), 0.018, total_len + 0.6, rotation=(0, math.pi/2, 0), material=mat_yellow)
    created_objects.append(rail_top)
    created_objects.append(rail_mid)

    for x in column_positions_x:
        post = add_cylinder(f"HandrailPost_X{x:.1f}", (x, sorter_h + 0.05, rail_z), 0.022, 0.95, material=mat_yellow)
        created_objects.append(post)

    # 3. Bin Bays & Drop Gate Diverters
    for b in range(num_bins):
        bay_x = b * bin_w
        # Drop Gate Diverter Paddle
        gate_paddle = add_box(f"DropGate_Bay{b}", (bay_x + 0.35, sorter_h - 0.25, 0), (0.65, 0.05, bin_depth - 0.4), mat_orange)
        # Pneumatic Actuator Cylinder
        actuator = add_cylinder(f"GateActuator_Bay{b}", (bay_x + 0.35, sorter_h + 0.3, 0), 0.04, 0.45, material=mat_chrome)
        created_objects.append(gate_paddle)
        created_objects.append(actuator)

        # Bin Divider Guide Walls below top deck
        wall_l = add_box(f"BinWall_Left_Bay{b}", (bay_x, sorter_h / 2.0 - 0.5, 0), (0.04, sorter_h - 1.2, bin_depth - 0.2), mat_dark_steel)
        created_objects.append(wall_l)

    # Parent all objects to root_obj
    for obj in created_objects:
        obj.parent = root_obj

    # Export to GLTF/GLB
    output_dir = "/home/deck/new-game-project/models"
    os.makedirs(output_dir, exist_ok=True)
    output_filepath = os.path.join(output_dir, "bin_sorter.glb")

    bpy.ops.object.select_all(action='DESELECT')
    root_obj.select_set(True)
    for child in root_obj.children:
        child.select_set(True)

    print(f"Exporting Bin Sorter GLB to: {output_filepath}")
    bpy.ops.export_scene.gltf(
        filepath=output_filepath,
        export_format='GLB',
        use_selection=True
    )
    print("Export complete!")

if __name__ == "__main__":
    build_bin_sorter()
