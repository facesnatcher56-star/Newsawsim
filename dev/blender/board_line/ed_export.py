"""Export the edger section to glTF (run inside Blender after ed_build).

Mill coordinates like the headrig (each file placed at y = -1.288 under a node at the origin):

  board_edger_frame.glb    ED_Frame: deck extension, skids, infeed frame, rails, picker belt frame, chutes
  board_edger_parts.glb    ED_Pos1..4 (> ED_PosHead), ED_Cush1..4, ED_Ramps, ED_Hold1..3, ED_InfeedTail/Head,
                           ED_BeltTail/Head, ED_Picker1..2
  board_edger_4ta36.glb    ED_Edger (mirrored root) with the edger's own parts: SawArbor, Saws, RemanSection
                           (> ChipHead_Arbor, ChipHead_Segments, ...), PressRoll_* and the rest
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "headrig"))
import hr_export as HE  # noqa: E402

import ed_build as D  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "models", "board_line")

# The edger's procedural materials, as flat viewport colours for the glTF (colour, metallic, roughness).
EDGER_VIEWPORT = {
    "Edger_USNRGreen": ((0.06, 0.24, 0.13), 0.25, 0.5),
    "Edger_MotorGrey": ((0.42, 0.44, 0.45), 0.3, 0.5),
    "Edger_KnurledSteel": ((0.42, 0.42, 0.42), 0.6, 0.45),
    "Edger_MachinedSteel": ((0.6, 0.6, 0.6), 0.7, 0.35),
    "Edger_Chrome": ((0.8, 0.8, 0.82), 0.9, 0.12),
    "Edger_CylinderBlack": ((0.04, 0.04, 0.04), 0.4, 0.4),
    "Edger_Carbide": ((0.25, 0.25, 0.26), 0.7, 0.35),
    "Edger_SawPlate": ((0.7, 0.7, 0.72), 0.8, 0.25),
    "Edger_Babbitt": ((0.65, 0.6, 0.5), 0.6, 0.4),
    "Edger_SafetyYellow": ((0.75, 0.55, 0.02), 0.1, 0.5),
    "Edger_BeltRubber": ((0.03, 0.03, 0.03), 0.0, 0.85),
    "Edger_Brass": ((0.75, 0.55, 0.25), 0.7, 0.35),
    "Edger_BlackEnamel": ((0.03, 0.03, 0.03), 0.2, 0.5),
    "Line_SafetyOrange": ((0.75, 0.13, 0.01), 0.1, 0.5),
    "Line_UHMW": ((0.75, 0.75, 0.72), 0.0, 0.55),
    "Line_ChainSteel": ((0.18, 0.18, 0.19), 0.6, 0.45),
}


def export_all():
    os.makedirs(OUT, exist_ok=True)
    HE._set_viewport_colours()
    for name, (rgb, metal, rough) in EDGER_VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            m.diffuse_color = (*rgb, 1.0)
            m.metallic = metal
            m.roughness = rough
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None]
    frame = [o for o in tops if o.name == "ED_Frame"]
    edger = [o for o in tops if o.name == "ED_Edger"]
    link = [o for o in tops if o.name == "ED_SharpLink"]
    parts = [o for o in tops if o not in frame and o not in edger and o not in link]
    out = {}
    for name, roots in (("frame", frame), ("parts", parts), ("4ta36", edger), ("sharp_link", link)):
        fn = "board_edger_%s.glb" % name
        out[fn] = HE._export(roots, os.path.join(OUT, fn))
    return out
