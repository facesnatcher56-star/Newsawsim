"""Clean, factory-fresh materials for the USNR 4TA36 edger (Cycles)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
from materials_lib import Graph  # noqa: E402

USNR_GREEN = (0.016, 0.075, 0.042)     # USNR forest green machinery enamel


def enamel(name, color, rough=0.32, orange_peel=0.04):
    """Fresh gloss enamel: slight orange-peel texture and a faint brighter edge."""
    g = Graph(name)
    obj = g.coord.outputs['Object']
    var = g.noise(obj, 3.0, 4, 0.5)
    col = g.mix(g.math('MULTIPLY', var.outputs['Fac'], 0.15), color, tuple(min(c * 1.25, 1.0) for c in color))
    edge = g.edge_mask(0.006, 0.02, 0.2)
    col = g.mix(g.math('MULTIPLY', edge, 0.25), col, tuple(min(c * 1.6, 1.0) for c in color))
    g.link(col, g.bsdf.inputs['Base Color'])
    g.bsdf.inputs['Roughness'].default_value = rough
    g.bsdf.inputs['Coat Weight'].default_value = 0.3
    g.bsdf.inputs['Coat Roughness'].default_value = 0.15
    g.link(g.bump(g.noise(obj, 220, 3, 0.5).outputs['Fac'], orange_peel, 0.002), g.bsdf.inputs['Normal'])
    return g.mat


def metal(name, color, rough, aniso_scale=None, bump=0.0, bump_scale=60.0):
    g = Graph(name)
    obj = g.coord.outputs['Object']
    g.bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    g.bsdf.inputs['Metallic'].default_value = 1.0
    if aniso_scale:
        streak = g.noise(g.mapping(obj, scale=aniso_scale), 1.0, 6, 0.6)
        g.link(g.mixf(streak.outputs['Fac'], rough * 0.6, rough * 1.4), g.bsdf.inputs['Roughness'])
    else:
        g.bsdf.inputs['Roughness'].default_value = rough
    if bump:
        g.link(g.bump(g.noise(obj, bump_scale, 4).outputs['Fac'], bump, 0.003), g.bsdf.inputs['Normal'])
    return g.mat


def knurl(name="Edger_KnurledSteel"):
    """Square-pattern knurl on the feed rolls."""
    g = Graph(name)
    obj = g.coord.outputs['Object']
    g.bsdf.inputs['Base Color'].default_value = (0.42, 0.42, 0.42, 1.0)
    g.bsdf.inputs['Metallic'].default_value = 1.0
    g.bsdf.inputs['Roughness'].default_value = 0.38
    chk = g.node('ShaderNodeTexChecker')
    g.link(obj, chk.inputs['Vector'])
    chk.inputs['Scale'].default_value = 140.0
    g.link(g.bump(chk.outputs['Fac'], 0.6, 0.004), g.bsdf.inputs['Normal'])
    return g.mat


def build_all():
    return {
        "green": enamel("Edger_USNRGreen", USNR_GREEN),
        "motor": enamel("Edger_MotorGrey", (0.18, 0.2, 0.22), 0.4),
        "black": enamel("Edger_BlackEnamel", (0.015, 0.015, 0.015), 0.45),
        "chrome": metal("Edger_Chrome", (0.85, 0.86, 0.88), 0.06),
        "steel": metal("Edger_MachinedSteel", (0.6, 0.6, 0.6), 0.25, aniso_scale=(1, 1, 60)),
        "saw": metal("Edger_SawPlate", (0.7, 0.7, 0.72), 0.18, aniso_scale=(40, 40, 1)),
        "carbide": metal("Edger_Carbide", (0.25, 0.25, 0.26), 0.3),
        "babbitt": metal("Edger_Babbitt", (0.65, 0.6, 0.5), 0.35),
        "knurl": knurl(),
        "rubber": enamel("Edger_BeltRubber", (0.012, 0.012, 0.012), 0.7, 0.0),
        "brass": metal("Edger_Brass", (0.75, 0.55, 0.25), 0.25),
        "hydraulic": enamel("Edger_CylinderBlack", (0.02, 0.02, 0.025), 0.35),
        "yellow": enamel("Edger_SafetyYellow", (0.55, 0.3, 0.0), 0.35),
    }
