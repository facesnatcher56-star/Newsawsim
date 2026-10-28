"""Weathered sawmill materials for the bin sorter (Cycles)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
from materials_lib import Graph, simple  # noqa: E402

SAWDUST = (0.42, 0.31, 0.18)


def mill_paint(name, dark, mid, light, chip=0.6, dust=1.0, grease_height=0.9):
    """Industrial paint: faded, chipped, grimy low down, sawdust on every ledge."""
    g = Graph(name)
    pos = g.geo.outputs['Position']
    obj = g.coord.outputs['Object']
    info = g.node('ShaderNodeObjectInfo')

    big = g.noise(pos, 0.6, 6, 0.6)
    fine = g.noise(pos, 7.0, 8, 0.65)
    tone = g.math('ADD', g.math('MULTIPLY', big.outputs['Fac'], 0.7), g.math('MULTIPLY', fine.outputs['Fac'], 0.3))
    tone = g.math('ADD', tone, g.math('MULTIPLY', g.math('SUBTRACT', info.outputs['Random'], 0.5), 0.15))
    paint = g.ramp(tone, [(0.35, dark), (0.55, mid), (0.72, light)])

    nsep = g.node('ShaderNodeSeparateXYZ')
    g.link(g.geo.outputs['Normal'], nsep.inputs[0])
    up = g.maprange(nsep.outputs['Z'], 0.45, 0.95)

    # Drip streaks and cavity grime.
    streak = g.maprange(g.noise(g.mapping(pos, scale=(16, 16, 0.6)), 1.0, 3, 0.5).outputs['Fac'], 0.55, 0.7)
    paint = g.mix(g.math('MULTIPLY', streak, 0.4), paint, g.mix(0.6, paint, (0.02, 0.02, 0.015)))
    cavity = g.math('SUBTRACT', 1.0, g.ao(0.2))
    paint = g.mix(g.math('MULTIPLY', cavity, 0.9, clamp=True), paint, (0.03, 0.025, 0.018))

    # Grease and oil, heavier near the floor.
    hsep = g.node('ShaderNodeSeparateXYZ')
    g.link(pos, hsep.inputs[0])
    low = g.maprange(hsep.outputs['Z'], grease_height, 0.0)
    grease_n = g.noise(pos, 3.0, 8, 0.65, distortion=0.5)
    grease = g.maprange(g.math('ADD', g.math('MULTIPLY', low, 0.7), g.math('MULTIPLY', grease_n.outputs['Fac'], 0.6)), 0.7, 0.85)
    paint = g.mix(g.math('MULTIPLY', grease, 0.85), paint, (0.02, 0.018, 0.014))

    # Chipped edges to bare/rusty steel.
    edge = g.edge_mask(0.025, 0.004, 0.06)
    chip_n = g.noise(obj, 18.0, 10, 0.7)
    field = g.math('ADD', g.math('MULTIPLY', edge, chip), chip_n.outputs['Fac'])
    chips = g.maprange(field, 0.8, 0.84)
    worn = g.maprange(field, 0.68, 0.8)
    paint = g.mix(g.math('MULTIPLY', worn, 0.45), paint, light)
    metal = g.ramp(g.noise(obj, 35, 4).outputs['Fac'], [(0.3, (0.07, 0.065, 0.06)), (0.7, (0.22, 0.2, 0.18))])
    rust = g.maprange(g.noise(obj, 12, 6).outputs['Fac'], 0.52, 0.66)
    metal = g.mix(g.math('MULTIPLY', rust, 0.85), metal, (0.2, 0.08, 0.03))

    # Sawdust piled on upward faces and caught in corners.
    dust_n = g.noise(pos, 2.5, 8, 0.6)
    dust_amt = g.math('ADD', g.math('MULTIPLY', up, 0.9), g.math('MULTIPLY', cavity, 0.4))
    sawdust = g.math('MULTIPLY', g.maprange(dust_n.outputs['Fac'], 0.32, 0.62), g.math('MULTIPLY', dust_amt, dust), clamp=True)
    dust_col = g.ramp(g.noise(pos, 30, 4).outputs['Fac'], [(0.3, (0.3, 0.22, 0.12)), (0.7, SAWDUST)])

    col = g.mix(chips, paint, metal)
    col = g.mix(sawdust, col, dust_col)
    g.link(col, g.bsdf.inputs['Base Color'])
    rough = g.mixf(fine.outputs['Fac'], 0.45, 0.7)
    rough = g.mixf(grease, rough, 0.3)
    rough = g.mixf(chips, rough, 0.4)
    rough = g.mixf(sawdust, rough, 0.95)
    g.link(rough, g.bsdf.inputs['Roughness'])
    g.link(g.math('MULTIPLY', chips, 0.9), g.bsdf.inputs['Metallic'])
    h = g.noise(obj, 50.0, 6, 0.6).outputs['Fac']
    h = g.math('SUBTRACT', h, g.math('MULTIPLY', chips, 0.4))
    h = g.math('ADD', h, g.math('MULTIPLY', sawdust, 0.8))
    g.link(g.bump(h, 0.12, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def worn_deck(name="Sorter_DeckSteel"):
    """Steel plate polished bright along the board travel direction (+X)."""
    g = Graph(name)
    pos = g.geo.outputs['Position']
    obj = g.coord.outputs['Object']
    streaks = g.noise(g.mapping(obj, scale=(0.4, 40, 40)), 1.0, 6, 0.6)
    polish = g.maprange(streaks.outputs['Fac'], 0.35, 0.65)
    base = g.ramp(g.noise(obj, 6, 6).outputs['Fac'], [(0.3, (0.05, 0.045, 0.04)), (0.7, (0.12, 0.1, 0.08))])
    col = g.mix(g.math('MULTIPLY', polish, 0.8), base, (0.42, 0.42, 0.4))
    dust = g.maprange(g.noise(pos, 3, 8).outputs['Fac'], 0.55, 0.75)
    col = g.mix(dust, col, SAWDUST)
    g.link(col, g.bsdf.inputs['Base Color'])
    g.link(g.mixf(dust, g.mixf(polish, 0.55, 0.85), 0.0), g.bsdf.inputs['Metallic'])
    g.link(g.mixf(dust, g.mixf(polish, 0.5, 0.22), 0.95), g.bsdf.inputs['Roughness'])
    g.link(g.bump(streaks.outputs['Fac'], 0.08, 0.005), g.bsdf.inputs['Normal'])
    return g.mat


def chain_steel(name="Sorter_ChainSteel"):
    g = Graph(name)
    obj = g.coord.outputs['Object']
    edge = g.edge_mask(0.006, 0.02, 0.2)
    base = g.ramp(g.noise(obj, 40, 6).outputs['Fac'], [(0.3, (0.025, 0.024, 0.022)), (0.7, (0.07, 0.055, 0.04))])
    col = g.mix(g.math('MULTIPLY', edge, 0.9), base, (0.4, 0.38, 0.35))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.link(g.mixf(edge, 0.8, 1.0), g.bsdf.inputs['Metallic'])
    g.link(g.mixf(edge, 0.35, 0.18), g.bsdf.inputs['Roughness'])
    return g.mat


def concrete(name="Sorter_Concrete"):
    g = Graph(name)
    pos = g.geo.outputs['Position']
    n = g.noise(pos, 1.2, 8, 0.6)
    col = g.ramp(n.outputs['Fac'], [(0.3, (0.18, 0.17, 0.16)), (0.7, (0.32, 0.3, 0.27))])
    stain = g.maprange(g.noise(pos, 0.35, 6).outputs['Fac'], 0.5, 0.62)
    col = g.mix(g.math('MULTIPLY', stain, 0.6), col, (0.06, 0.05, 0.04))
    dust = g.maprange(g.noise(pos, 4, 8).outputs['Fac'], 0.5, 0.7)
    col = g.mix(g.math('MULTIPLY', dust, 0.7), col, SAWDUST)
    g.link(col, g.bsdf.inputs['Base Color'])
    g.link(g.mixf(stain, 0.85, 0.5), g.bsdf.inputs['Roughness'])
    g.link(g.bump(g.noise(pos, 60, 4).outputs['Fac'], 0.15, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def _board_space(g):
    """Texture space unique to each board: object coordinates shifted by the board's own
    'board_off' attribute (set per board when boards are merged into one mesh) and by the
    object's random value (boards that are separate objects). Returns (vector, per-board 0-1)."""
    obj = g.coord.outputs['Object']
    info = g.node('ShaderNodeObjectInfo')
    off = g.node('ShaderNodeAttribute', attribute_name='board_off')
    seed = g.node('ShaderNodeAttribute', attribute_name='board_seed')
    rnd = g.math('FRACT', g.math('ADD', seed.outputs['Fac'], info.outputs['Random']))
    # Separate board objects (no attribute) get their pith shifted a little sideways and down
    # from the board's centre by their own random value.
    shift = g.node('ShaderNodeCombineXYZ')
    r = info.outputs['Random']
    g.link(g.math('MULTIPLY', g.math('SUBTRACT', g.math('FRACT', g.math('MULTIPLY', r, 37.0)), 0.5), 0.3), shift.inputs[0])
    g.link(g.math('MULTIPLY', r, 53.0), shift.inputs[1])
    g.link(g.math('ADD', g.math('MULTIPLY', g.math('FRACT', g.math('MULTIPLY', r, 71.0)), 0.25), 0.06), shift.inputs[2])
    v = g.node('ShaderNodeVectorMath', operation='ADD')
    g.link(obj, v.inputs[0])
    g.link(off.outputs['Vector'], v.inputs[1])
    v2 = g.node('ShaderNodeVectorMath', operation='ADD')
    g.link(v.outputs['Vector'], v2.inputs[0])
    g.link(shift.outputs['Vector'], v2.inputs[1])
    return v2.outputs['Vector'], rnd


def lumber(name="Sorter_Lumber"):
    """Freshly sawn green softwood (fir/pine), different on every board: each board gets its
    own colour (pale sapwood through pinkish heartwood), its own flat-sawn grain figure, its own
    scatter of knots, faint saw-mark banding across the face and a damp rough-sawn finish.
    Board long axis is Blender Y (game Z)."""
    g = Graph(name)
    vec, rnd = _board_space(g)
    # Grain: growth rings round the long axis, stretched along it; ring spacing and figure vary
    # per board.
    grain = g.node('ShaderNodeTexWave', wave_type='RINGS', rings_direction='Y', wave_profile='SAW')
    g.link(g.mapping(vec, scale=(1, 0.06, 1)), grain.inputs['Vector'])
    g.link(g.math('ADD', g.math('MULTIPLY', rnd, 160.0), 120.0), grain.inputs['Scale'])        # 3-8 mm rings
    g.link(g.math('ADD', g.math('MULTIPLY', rnd, 3.0), 2.0), grain.inputs['Distortion'])
    grain.inputs['Detail'].default_value = 3
    grain.inputs['Detail Scale'].default_value = 0.6
    late = g.maprange(grain.outputs['Fac'], 0.70, 0.97)                 # dark latewood lines
    fine = g.noise(g.mapping(vec, scale=(60, 2, 60)), 1.0, 6, 0.6).outputs['Fac']
    # Board colour (linear): pale sapwood, clear, pinkish heartwood, darker heart.
    base = g.ramp(rnd, [(0.0, (0.62, 0.43, 0.21)), (0.3, (0.56, 0.37, 0.17)), (0.6, (0.55, 0.30, 0.16)),
                        (0.82, (0.47, 0.27, 0.13)), (1.0, (0.38, 0.22, 0.10))])
    patch = g.noise(g.mapping(vec, scale=(3, 0.25, 3)), 1.0, 3, 0.5).outputs['Fac']   # heart/sap streaks along the length
    col = g.mix(g.maprange(patch, 0.45, 0.75, 0.0, 0.4), base, (0.50, 0.26, 0.14))
    col = g.mix(g.math('MULTIPLY', fine, 0.2), col, (0.68, 0.50, 0.28))
    col = g.mix(g.math('MULTIPLY', late, 0.7), col, (0.24, 0.13, 0.05))
    # Knots on the face: some 2D Voronoi cells (across x along) hold a knot, a dark core with a
    # darker ring of grain round it; each board's offset puts them in different places.
    vor = g.node('ShaderNodeTexVoronoi', feature='F1', voronoi_dimensions='2D')
    g.link(g.mapping(vec, scale=(5.0, 1.8, 1.0)), vor.inputs['Vector'])
    vor.inputs['Scale'].default_value = 1.0
    has = g.maprange(vor.outputs['Color'], 0.55, 0.58)
    dist = vor.outputs['Distance']
    core = g.math('MULTIPLY', g.maprange(dist, 0.08, 0.05), has)
    halo = g.math('MULTIPLY', g.maprange(dist, 0.2, 0.08), has)
    col = g.mix(g.math('MULTIPLY', halo, 0.45), col, (0.36, 0.2, 0.08))
    col = g.mix(g.math('MULTIPLY', core, 0.95), col, (0.12, 0.06, 0.02))
    # Saw marks: faint bands across the face, spaced along the length.
    saw = g.node('ShaderNodeTexWave', wave_type='BANDS', bands_direction='Y')
    g.link(vec, saw.inputs['Vector'])
    saw.inputs['Scale'].default_value = 18
    saw.inputs['Distortion'].default_value = 2
    marks = g.maprange(saw.outputs['Fac'], 0.6, 1.0, 0.0, 0.12)
    col = g.mix(marks, col, (0.32, 0.2, 0.1))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.link(g.mixf(fine, 0.62, 0.85), g.bsdf.inputs['Roughness'])
    h = g.math('ADD', g.math('MULTIPLY', late, 0.4), g.math('MULTIPLY', marks, 2.0))
    h = g.math('SUBTRACT', h, g.math('MULTIPLY', core, 0.6))
    g.link(g.bump(h, 0.25, 0.004), g.bsdf.inputs['Normal'])
    return g.mat


def sticks(name="Stacker_Sticks"):
    """Kiln sticks: dried and reused, so much darker and greyer than green lumber."""
    g = Graph(name)
    vec, rnd = _board_space(g)
    grain = g.node('ShaderNodeTexWave', wave_type='RINGS', rings_direction='X')
    g.link(g.mapping(vec, scale=(0.04, 1, 1)), grain.inputs['Vector'])
    grain.inputs['Scale'].default_value = 12
    grain.inputs['Distortion'].default_value = 5
    base = g.ramp(rnd, [(0.0, (0.16, 0.11, 0.07)), (0.5, (0.12, 0.085, 0.055)), (1.0, (0.09, 0.07, 0.05))])
    col = g.mix(g.math('MULTIPLY', g.maprange(grain.outputs['Fac'], 0.6, 0.95), 0.6), base, (0.05, 0.035, 0.025))
    grime = g.noise(vec, 6, 6, 0.6).outputs['Fac']
    col = g.mix(g.maprange(grime, 0.5, 0.75, 0.0, 0.5), col, (0.11, 0.105, 0.1))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = 0.9
    g.link(g.bump(grain.outputs['Fac'], 0.15, 0.003), g.bsdf.inputs['Normal'])
    return g.mat


def build_all():
    return {
        "green": mill_paint("Sorter_FrameGreen", (0.012, 0.035, 0.022), (0.022, 0.06, 0.038), (0.05, 0.1, 0.07)),
        "orange": mill_paint("Sorter_SafetyOrange", (0.32, 0.07, 0.01), (0.55, 0.14, 0.02), (0.7, 0.26, 0.06), chip=0.75),
        "yellow": mill_paint("Sorter_SafetyYellow", (0.38, 0.26, 0.01), (0.6, 0.42, 0.02), (0.72, 0.56, 0.12), chip=0.8),
        "grey": mill_paint("Sorter_MotorGrey", (0.05, 0.06, 0.07), (0.09, 0.1, 0.12), (0.15, 0.16, 0.17)),
        "galv": mill_paint("Sorter_Galvanized", (0.18, 0.18, 0.18), (0.28, 0.28, 0.27), (0.38, 0.38, 0.36), chip=0.2),
        "deck": worn_deck(),
        "chain": chain_steel(),
        "uhmw": simple("Sorter_UHMW", (0.75, 0.74, 0.7), 0.35, 0.0, 30, 0.05),
        "shaft": simple("Sorter_MachinedSteel", (0.5, 0.5, 0.5), 0.3, 1.0),
        "rubber": simple("Sorter_Rubber", (0.015, 0.015, 0.015), 0.8, 0.0),
        "lumber": lumber(),
        "sticks": sticks(),
        "drum": mill_paint("Stacker_DrumShell", (0.03, 0.03, 0.03), (0.06, 0.06, 0.065), (0.12, 0.12, 0.12), chip=0.9),
        "concrete": concrete(),
    }
