"""Background frame render for the tank demo.

blender -b sherman_m4a3.blend --python render_anim.py -- OUT_DIR [SAMPLES] [START] [END] [WIDTH] [HEIGHT]

Frames are written as OUT_DIR/frame_####.png. Existing frames are skipped, so
an interrupted render can simply be restarted.
"""
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_dir = args[0]
samples = int(args[1]) if len(args) > 1 else 64
scene = bpy.context.scene
start = int(args[2]) if len(args) > 2 else scene.frame_start
end = int(args[3]) if len(args) > 3 else scene.frame_end
width = int(args[4]) if len(args) > 4 else 1600
height = int(args[5]) if len(args) > 5 else 900

prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'HIP'
prefs.refresh_devices()
for dev in prefs.devices:
    dev.use = dev.type == 'HIP'

scene.camera = bpy.data.objects["Camera"]
scene.render.engine = 'CYCLES'
scene.cycles.device = 'GPU'
scene.cycles.samples = samples
scene.cycles.use_adaptive_sampling = True
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = width, height
scene.render.resolution_percentage = 100
scene.render.use_motion_blur = True
scene.render.motion_blur_shutter = 0.5
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = out_dir.rstrip("\\/") + "/frame_####"
scene.render.use_overwrite = False
scene.render.use_placeholder = True
scene.frame_start, scene.frame_end = start, end
print("Rendering frames %d-%d at %dx%d, %d samples on %s" % (
    start, end, width, height, samples, [d.name for d in prefs.devices if d.use]))
bpy.ops.render.render(animation=True)
