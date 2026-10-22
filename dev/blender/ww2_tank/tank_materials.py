"""Procedural weathered materials for the WW2 tank (Cycles; degrades gracefully in EEVEE)."""
import bpy


def _rgba(c):
    return tuple(c) + (1.0,) if len(c) == 3 else tuple(c)


class Graph:
    def __init__(self, name):
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes = True
        self.mat = mat
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.node('ShaderNodeOutputMaterial')
        self.bsdf = self.node('ShaderNodeBsdfPrincipled')
        self.link(self.bsdf.outputs['BSDF'], self.out.inputs['Surface'])
        self.geo = self.node('ShaderNodeNewGeometry')
        self.coord = self.node('ShaderNodeTexCoord')

    def node(self, kind, **props):
        nd = self.nt.nodes.new(kind)
        for key, value in props.items():
            setattr(nd, key, value)
        return nd

    def link(self, a, b):
        self.nt.links.new(a, b)

    def put(self, value, target):
        if isinstance(value, bpy.types.NodeSocket):
            self.link(value, target)
        elif isinstance(value, (tuple, list)) and len(value) in (3, 4) and target.type == 'RGBA':
            target.default_value = _rgba(value)
        else:
            target.default_value = value

    def math(self, op, a, b=0.0, clamp=False):
        nd = self.node('ShaderNodeMath', operation=op, use_clamp=clamp)
        self.put(a, nd.inputs[0])
        self.put(b, nd.inputs[1])
        return nd.outputs[0]

    def mix(self, f, a, b, blend='MIX'):
        nd = self.node('ShaderNodeMix', data_type='RGBA', blend_type=blend, clamp_factor=True)
        self.put(f, nd.inputs[0])
        self.put(a, nd.inputs[6])
        self.put(b, nd.inputs[7])
        return nd.outputs[2]

    def mixf(self, f, a, b):
        nd = self.node('ShaderNodeMix', data_type='FLOAT', clamp_factor=True)
        self.put(f, nd.inputs[0])
        self.put(a, nd.inputs[2])
        self.put(b, nd.inputs[3])
        return nd.outputs[0]

    def maprange(self, v, fmin, fmax, tmin=0.0, tmax=1.0):
        nd = self.node('ShaderNodeMapRange', clamp=True)
        self.put(v, nd.inputs[0])
        for i, val in zip(range(1, 5), (fmin, fmax, tmin, tmax)):
            nd.inputs[i].default_value = val
        return nd.outputs[0]

    def mapping(self, vec, scale=(1, 1, 1), loc=(0, 0, 0)):
        nd = self.node('ShaderNodeMapping')
        self.put(vec, nd.inputs['Vector'])
        nd.inputs['Scale'].default_value = scale
        nd.inputs['Location'].default_value = loc
        return nd.outputs['Vector']

    def noise(self, vec, scale, detail=4.0, rough=0.55, distortion=0.0):
        nd = self.node('ShaderNodeTexNoise')
        self.put(vec, nd.inputs['Vector'])
        nd.inputs['Scale'].default_value = scale
        nd.inputs['Detail'].default_value = detail
        nd.inputs['Roughness'].default_value = rough
        nd.inputs['Distortion'].default_value = distortion
        return nd

    def voronoi(self, vec, scale, feature='F1'):
        nd = self.node('ShaderNodeTexVoronoi', feature=feature)
        self.put(vec, nd.inputs['Vector'])
        nd.inputs['Scale'].default_value = scale
        return nd

    def ramp(self, fac, stops, interp='LINEAR'):
        nd = self.node('ShaderNodeValToRGB')
        self.put(fac, nd.inputs['Fac'])
        cr = nd.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (pos, col) in zip(cr.elements, stops):
            el.position = pos
            el.color = _rgba(col)
        return nd.outputs['Color']

    def edge_mask(self, radius=0.012, low=0.02, high=0.25):
        bev = self.node('ShaderNodeBevel', samples=8)
        bev.inputs['Radius'].default_value = radius
        dot = self.node('ShaderNodeVectorMath', operation='DOT_PRODUCT')
        self.link(bev.outputs['Normal'], dot.inputs[0])
        self.link(self.geo.outputs['Normal'], dot.inputs[1])
        edge = self.math('SUBTRACT', 1.0, dot.outputs['Value'])
        return self.maprange(edge, low, high)

    def ao(self, distance, inside=False):
        nd = self.node('ShaderNodeAmbientOcclusion', inside=inside, only_local=True, samples=8)
        nd.inputs['Distance'].default_value = distance
        return nd.outputs['AO']

    def bump(self, height, strength, distance=0.02, normal=None):
        nd = self.node('ShaderNodeBump')
        self.put(height, nd.inputs['Height'])
        nd.inputs['Strength'].default_value = strength
        nd.inputs['Distance'].default_value = distance
        if normal is not None:
            self.link(normal, nd.inputs['Normal'])
        return nd.outputs['Normal']


def painted_steel(name, dark, mid, light, cast=False, chip_amount=0.55, dirt_height=1.25):
    """Faded, chipped, dusty and mud-splashed paint over steel."""
    g = Graph(name)
    pos = g.geo.outputs['Position']
    obj = g.coord.outputs['Object']

    # Paint tone: large blotchy fade plus fine mottling, shifted per part so
    # replaced or repainted pieces don't match exactly.
    big = g.noise(pos, 0.9, 6, 0.6)
    fine = g.noise(pos, 9.0, 8, 0.65)
    info = g.node('ShaderNodeObjectInfo')
    tone = g.math('ADD', g.math('MULTIPLY', big.outputs['Fac'], 0.75), g.math('MULTIPLY', fine.outputs['Fac'], 0.25))
    tone = g.math('ADD', tone, g.math('MULTIPLY', g.math('SUBTRACT', info.outputs['Random'], 0.5), 0.18))
    paint = g.ramp(tone, [(0.35, dark), (0.55, mid), (0.72, light)])
    # Sun-bleached upward faces.
    nsep = g.node('ShaderNodeSeparateXYZ')
    g.link(g.geo.outputs['Normal'], nsep.inputs[0])
    up = g.maprange(nsep.outputs['Z'], 0.3, 1.0)
    paint = g.mix(g.math('MULTIPLY', up, 0.35), paint, light)

    # Vertical rain/grime streaks.
    streak_n = g.noise(g.mapping(pos, scale=(14, 14, 0.7)), 1.0, 3, 0.5)
    streak = g.maprange(streak_n.outputs['Fac'], 0.52, 0.68)
    paint = g.mix(g.math('MULTIPLY', streak, 0.45), paint, g.mix(0.5, paint, (0.03, 0.03, 0.02)))

    # Cavity grime from ambient occlusion.
    cavity = g.math('SUBTRACT', 1.0, g.ao(0.25))
    grime = (0.035, 0.03, 0.02)
    paint = g.mix(g.math('MULTIPLY', cavity, 0.85, clamp=True), paint, grime)

    # Chipped edges exposing dark steel, plus scattered scratches.
    edge = g.edge_mask(0.035, 0.004, 0.06)
    chip_n = g.noise(obj, 22.0, 10, 0.7)
    chip_field = g.math('ADD', g.math('MULTIPLY', edge, chip_amount), chip_n.outputs['Fac'])
    chips = g.maprange(chip_field, 0.8, 0.84)
    # Lighter worn paint halo around the chips.
    worn = g.maprange(chip_field, 0.68, 0.8)
    paint = g.mix(g.math('MULTIPLY', worn, 0.5), paint, (0.16, 0.15, 0.1))
    scratch_n = g.noise(g.mapping(obj, scale=(60, 4, 60)), 1.0, 2, 0.5)
    scratches = g.maprange(scratch_n.outputs['Fac'], 0.78, 0.8)
    metal_mask = g.math('MAXIMUM', chips, g.math('MULTIPLY', scratches, 0.6))
    metal_col = g.ramp(g.noise(obj, 40, 4).outputs['Fac'], [(0.3, (0.08, 0.075, 0.07)), (0.7, (0.2, 0.19, 0.17))])
    rust = g.maprange(g.noise(obj, 15, 6).outputs['Fac'], 0.5, 0.65)
    metal_col = g.mix(g.math('MULTIPLY', rust, 0.8), metal_col, (0.18, 0.07, 0.025))

    # Mud splashed up from the ground and dust settled on top.
    height = g.node('ShaderNodeSeparateXYZ')
    g.link(pos, height.inputs[0])
    low = g.maprange(height.outputs['Z'], dirt_height, 0.3)
    mud_n = g.noise(pos, 4.0, 10, 0.7, distortion=0.4)
    mud = g.maprange(g.math('ADD', g.math('MULTIPLY', low, 1.0), g.math('MULTIPLY', mud_n.outputs['Fac'], 0.55)), 0.75, 0.88)
    # Splatter thrown up by the tracks, thinning out with height.
    splat_v = g.voronoi(pos, 35.0)
    splat_reach = g.math('MULTIPLY', g.maprange(height.outputs['Z'], dirt_height + 0.5, 0.5), mud_n.outputs['Fac'])
    splat = g.math('MULTIPLY', g.maprange(splat_v.outputs['Distance'], 0.28, 0.12), g.maprange(splat_reach, 0.25, 0.55))
    mud = g.math('MAXIMUM', mud, splat)
    # Dust everywhere, heavier low down and on upward faces.
    dust_n = g.noise(pos, 2.0, 6, 0.6)
    dust_amt = g.math('ADD', g.math('ADD', 0.2, g.math('MULTIPLY', up, 0.45)), g.math('MULTIPLY', low, 0.4))
    dust = g.math('MULTIPLY', g.maprange(dust_n.outputs['Fac'], 0.35, 0.7), dust_amt, clamp=True)
    mud_col = g.ramp(mud_n.outputs['Fac'], [(0.4, (0.05, 0.035, 0.022)), (0.7, (0.13, 0.095, 0.06))])

    col = g.mix(metal_mask, paint, metal_col)
    col = g.mix(g.math('MULTIPLY', dust, 0.7), col, (0.2, 0.165, 0.115))
    col = g.mix(mud, col, mud_col)
    g.link(col, g.bsdf.inputs['Base Color'])

    rough = g.mixf(fine.outputs['Fac'], 0.55, 0.8)
    rough = g.mixf(metal_mask, rough, 0.38)
    rough = g.mixf(mud, rough, 0.95)
    g.link(rough, g.bsdf.inputs['Roughness'])
    g.link(g.math('MULTIPLY', metal_mask, 0.9), g.bsdf.inputs['Metallic'])

    # Surface relief: rolled plate or rough casting, chips slightly recessed, mud raised.
    if cast:
        h1 = g.noise(obj, 14.0, 8, 0.7).outputs['Fac']
        h2 = g.noise(obj, 70.0, 4, 0.6).outputs['Fac']
        height_val = g.math('ADD', h1, g.math('MULTIPLY', h2, 0.4))
        strength = 0.35
    else:
        height_val = g.noise(obj, 45.0, 6, 0.6).outputs['Fac']
        strength = 0.08
    height_val = g.math('SUBTRACT', height_val, g.math('MULTIPLY', metal_mask, 0.3))
    height_val = g.math('ADD', height_val, g.math('MULTIPLY', mud, 0.6))
    g.link(g.bump(height_val, strength, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def track_steel(name="Tank_TrackSteel"):
    g = Graph(name)
    obj = g.coord.outputs['Object']
    pos = g.geo.outputs['Position']
    edge = g.edge_mask(0.006, 0.02, 0.2)
    base = g.ramp(g.noise(obj, 30, 6).outputs['Fac'], [(0.3, (0.03, 0.026, 0.022)), (0.7, (0.075, 0.05, 0.032))])
    shiny = (0.35, 0.33, 0.3)
    sep = g.node('ShaderNodeSeparateXYZ')
    g.link(g.geo.outputs['Normal'], sep.inputs[0])
    mud_n = g.noise(pos, 6.0, 10, 0.7, distortion=0.5)
    cavity = g.math('SUBTRACT', 1.0, g.ao(0.08))
    mud = g.maprange(g.math('ADD', mud_n.outputs['Fac'], g.math('MULTIPLY', cavity, 0.6)), 0.6, 0.72)
    worn = g.math('MULTIPLY', edge, g.maprange(mud, 0.5, 0.0))
    col = g.mix(worn, base, shiny)
    col = g.mix(mud, col, g.ramp(mud_n.outputs['Fac'], [(0.4, (0.04, 0.03, 0.02)), (0.7, (0.12, 0.09, 0.06))]))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.link(g.mixf(mud, g.mixf(worn, 0.75, 0.9), 0.0), g.bsdf.inputs['Metallic'])
    g.link(g.mixf(mud, g.mixf(worn, 0.7, 0.3), 0.95), g.bsdf.inputs['Roughness'])
    h = g.math('ADD', g.noise(obj, 80, 6).outputs['Fac'], g.math('MULTIPLY', mud, 0.8))
    g.link(g.bump(h, 0.3, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def rubber(name="Tank_Rubber"):
    g = Graph(name)
    pos = g.geo.outputs['Position']
    dust = g.maprange(g.noise(pos, 5, 8, 0.6).outputs['Fac'], 0.5, 0.8)
    col = g.mix(g.math('MULTIPLY', dust, 0.7), (0.012, 0.012, 0.012), (0.09, 0.07, 0.05))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.link(g.mixf(dust, 0.75, 0.95), g.bsdf.inputs['Roughness'])
    g.link(g.bump(g.noise(g.coord.outputs['Object'], 120, 4).outputs['Fac'], 0.15, 0.005), g.bsdf.inputs['Normal'])
    return g.mat


def simple(name, color, rough=0.5, metallic=0.0, bump_scale=None, bump_strength=0.1, transmission=0.0):
    g = Graph(name)
    g.bsdf.inputs['Base Color'].default_value = _rgba(color)
    g.bsdf.inputs['Roughness'].default_value = rough
    g.bsdf.inputs['Metallic'].default_value = metallic
    if transmission:
        g.bsdf.inputs['Transmission Weight'].default_value = transmission
    if bump_scale:
        n = g.noise(g.coord.outputs['Object'], bump_scale, 6)
        col = g.mix(g.math('MULTIPLY', n.outputs['Fac'], 0.6), color, tuple(c * 0.55 for c in color[:3]))
        g.link(col, g.bsdf.inputs['Base Color'])
        g.link(g.bump(n.outputs['Fac'], bump_strength, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def canvas(name="Tank_Canvas"):
    g = Graph(name)
    obj = g.coord.outputs['Object']
    weave = g.node('ShaderNodeTexWave', wave_type='BANDS')
    g.link(obj, weave.inputs['Vector'])
    weave.inputs['Scale'].default_value = 400
    folds = g.noise(obj, 6, 6, 0.6)
    col = g.ramp(folds.outputs['Fac'], [(0.3, (0.12, 0.1, 0.06)), (0.7, (0.24, 0.2, 0.12))])
    col = g.mix(g.math('MULTIPLY', g.math('SUBTRACT', 1.0, g.ao(0.1)), 0.9), col, (0.03, 0.025, 0.015))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = 0.95
    h = g.math('ADD', g.math('MULTIPLY', weave.outputs['Fac'], 0.1), folds.outputs['Fac'])
    g.link(g.bump(h, 0.5, 0.02), g.bsdf.inputs['Normal'])
    return g.mat


def wood(name="Tank_Wood"):
    g = Graph(name)
    obj = g.coord.outputs['Object']
    grain = g.node('ShaderNodeTexWave', wave_type='RINGS')
    g.link(g.mapping(obj, scale=(1, 30, 30)), grain.inputs['Vector'])
    grain.inputs['Scale'].default_value = 2
    grain.inputs['Distortion'].default_value = 6
    col = g.ramp(grain.outputs['Fac'], [(0.2, (0.08, 0.045, 0.02)), (0.8, (0.22, 0.13, 0.06))])
    g.link(col, g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = 0.8
    return g.mat


def ground(name="Tank_Ground"):
    g = Graph(name)
    pos = g.geo.outputs['Position']
    big = g.noise(pos, 0.35, 8, 0.6, distortion=0.3)
    mid = g.noise(pos, 3.0, 10, 0.65)
    gravel = g.voronoi(pos, 60.0)
    col = g.ramp(big.outputs['Fac'], [(0.35, (0.07, 0.045, 0.025)), (0.55, (0.17, 0.115, 0.065)), (0.75, (0.26, 0.19, 0.115))])
    col = g.mix(g.math('MULTIPLY', mid.outputs['Fac'], 0.5), col, (0.1, 0.07, 0.04))
    stones = g.maprange(gravel.outputs['Distance'], 0.08, 0.02)
    stones = g.math('MULTIPLY', stones, g.maprange(mid.outputs['Fac'], 0.45, 0.6))
    col = g.mix(stones, col, (0.22, 0.2, 0.17))
    wet = g.maprange(big.outputs['Fac'], 0.42, 0.34)
    col = g.mix(g.math('MULTIPLY', wet, 0.5), col, (0.02, 0.015, 0.01))

    # Track ruts (mesh attribute 'rut'): churned dark mud, chevron imprints, puddles.
    rut = g.node('ShaderNodeAttribute', attribute_name='rut').outputs['Fac']
    sep = g.node('ShaderNodeSeparateXYZ')
    g.link(pos, sep.inputs[0])
    ylocal = g.math('ABSOLUTE', g.math('SUBTRACT', g.math('ABSOLUTE', sep.outputs['Y']), 1.10))
    phase = g.math('MULTIPLY', g.math('ADD', sep.outputs['X'], g.math('MULTIPLY', ylocal, 0.47)), 6.2832 / 0.152)
    chevron = g.math('MULTIPLY', g.maprange(g.math('SINE', phase), 0.2, 0.9), g.maprange(ylocal, 0.2, 0.17))
    col = g.mix(g.math('MULTIPLY', rut, 0.75), col, g.ramp(mid.outputs['Fac'], [(0.3, (0.035, 0.026, 0.017)), (0.7, (0.08, 0.058, 0.038))]))
    puddle = g.math('MULTIPLY', g.maprange(rut, 0.8, 1.0), g.maprange(g.noise(pos, 0.3, 4, 0.5).outputs['Fac'], 0.58, 0.61))
    col = g.mix(g.math('MULTIPLY', puddle, 0.8), col, (0.025, 0.02, 0.014))
    g.link(col, g.bsdf.inputs['Base Color'])
    rough = g.mixf(wet, 0.95, 0.6)
    rough = g.mixf(g.math('MULTIPLY', rut, 0.6), rough, 0.5)
    rough = g.mixf(puddle, rough, 0.12)
    g.link(rough, g.bsdf.inputs['Roughness'])
    h = g.math('ADD', mid.outputs['Fac'], g.math('MULTIPLY', stones, 0.5))
    h = g.math('ADD', h, g.math('MULTIPLY', g.math('MULTIPLY', chevron, rut), 1.5))
    h = g.mixf(puddle, h, 0.5)
    g.link(g.bump(h, 0.6, 0.05), g.bsdf.inputs['Normal'])
    return g.mat


def grass(name="Tank_Grass"):
    g = Graph(name)
    hair = g.node('ShaderNodeHairInfo')
    col = g.ramp(hair.outputs['Intercept'], [(0.0, (0.02, 0.022, 0.008)), (0.5, (0.12, 0.11, 0.04)), (1.0, (0.3, 0.26, 0.13))])
    tint = g.ramp(hair.outputs['Random'], [(0.0, (0.75, 0.8, 0.6)), (0.6, (1.0, 1.0, 1.0)), (1.0, (1.2, 1.0, 0.8))])
    g.link(g.mix(1.0, col, tint, blend='MULTIPLY'), g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = 0.6
    g.bsdf.inputs['Transmission Weight'].default_value = 0.0
    return g.mat


def stone(name="Tank_Stone"):
    g = Graph(name)
    n = g.noise(g.coord.outputs['Object'], 12, 8, 0.6)
    info = g.node('ShaderNodeObjectInfo')
    col = g.ramp(n.outputs['Fac'], [(0.3, (0.08, 0.07, 0.06)), (0.7, (0.25, 0.22, 0.18))])
    col = g.mix(g.math('MULTIPLY', info.outputs['Random'], 0.5), col, (0.14, 0.1, 0.07))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = 0.85
    g.link(g.bump(n.outputs['Fac'], 0.4, 0.01), g.bsdf.inputs['Normal'])
    return g.mat


def build_all():
    od = ((0.035, 0.04, 0.016), (0.062, 0.068, 0.028), (0.11, 0.108, 0.058))
    mats = {
        "paint": painted_steel("Tank_Paint_OD", *od),
        "cast": painted_steel("Tank_Paint_OD_Cast", *od, cast=True),
        "star": painted_steel("Tank_Paint_Star", (0.45, 0.43, 0.36), (0.58, 0.56, 0.48), (0.66, 0.64, 0.56), chip_amount=0.8),
        "track": track_steel(),
        "rubber": rubber(),
        "gunmetal": simple("Tank_Gunmetal", (0.03, 0.03, 0.03), 0.45, 0.85, 60, 0.1),
        "glass": simple("Tank_Glass", (0.01, 0.015, 0.012), 0.05, 0.0),
        "brass": simple("Tank_Lamp", (0.08, 0.08, 0.075), 0.08, 0.0),
        "canvas": canvas(),
        "wood": wood(),
        "ground": ground(),
        "grass": grass(),
        "stone": stone(),
    }
    return mats
