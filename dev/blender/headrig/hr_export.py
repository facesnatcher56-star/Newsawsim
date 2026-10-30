"""Export the band headrig line to glTF for the game (run inside Blender after hr_build).

Every file is in mill coordinates (floor at z = 0), so the game places each one at
y = -1.288 under a node at the origin:

  headrig_frame.glb   HR_Frame: track, drum house, deck frame, band mill frame and guards,
                      outfeed frame, cab and sawyer
  headrig_parts.glb   the moving parts, each its own node: HR_Carriage (> knees > dogs,
                      wheels), HR_UpperWheel, HR_LowerWheel, HR_Band, HR_UpperGuide,
                      HR_Loader1..3, HR_Turner1..2, HR_DeckHead/Tail, HR_OutRoll1..n
  headrig_tooth.glb   HR_Tooth: one band saw tooth, for instancing round the band

The deck chains reuse the log deck's chain links (log_deck_chain.glb).
"""
import os
import time

import bpy

import hr_build as D

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "assets", "models",
                   "headrig")


def _set_viewport_colours():
    for name, (rgb, metal, rough) in D.VIEWPORT.items():
        m = bpy.data.materials.get(name)
        if m is not None:
            alpha = m.diffuse_color[3] if name == "HR_Glass" else 1.0
            m.diffuse_color = (*rgb, alpha)
            m.metallic = metal
            m.roughness = rough


def _export(roots, path):
    bpy.ops.object.select_all(action='DESELECT')
    objs = []
    for root in roots:
        objs += [root] + list(root.children_recursive)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # Export beside the target and swap it in: OneDrive and Godot's importer briefly lock
    # a .glb right after it is written.
    tmp = path[:-4] + ".export.glb"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='VIEWPORT', export_cameras=False,
                              export_lights=False, export_animations=False)
    for _ in range(20):
        try:
            os.replace(tmp, path)
            return len(objs)
        except OSError:
            time.sleep(0.5)
    raise OSError(os.path.basename(path) + " stayed locked; the export is at " + tmp)


def export_all():
    os.makedirs(OUT, exist_ok=True)
    _set_viewport_colours()
    D.pose()
    coll = bpy.data.collections[D.COLL]
    tops = [o for o in coll.objects if o.parent is None and not o.name.startswith("HR_Preview")]
    frame = [o for o in tops if o.name == "HR_Frame"]
    tooth = [o for o in tops if o.name == "HR_Tooth"]
    parts = [o for o in tops if o not in frame and o not in tooth]
    return {
        "headrig_frame.glb": _export(frame, os.path.join(OUT, "headrig_frame.glb")),
        "headrig_parts.glb": _export(parts, os.path.join(OUT, "headrig_parts.glb")),
        "headrig_tooth.glb": _export(tooth, os.path.join(OUT, "headrig_tooth.glb")),
    }
