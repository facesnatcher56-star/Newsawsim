"""Materials for the 3338 line: the edger's set plus the transfer and infeed finishes."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "edger_4ta36"))
import edger_materials as EM  # noqa: E402
import edger_scene as ES  # noqa: E402


def build_all():
    m = EM.build_all()
    m["orange"] = EM.enamel("Line_SafetyOrange", (0.75, 0.13, 0.01), 0.35)
    m["uhmw"] = EM.enamel("Line_UHMW", (0.75, 0.75, 0.72), 0.55, 0.0)
    m["chain"] = EM.metal("Line_ChainSteel", (0.18, 0.18, 0.19), 0.45)
    m["concrete"] = ES.concrete()
    return m
