"""Join a PNG frame sequence into an H.264 MP4 with Blender's built-in FFmpeg.

blender -b --factory-startup --python encode_mp4.py -- FRAMES_DIR OUT.mp4 [FPS]
"""
import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
frames_dir, out_path = args[0], args[1]
fps = int(args[2]) if len(args) > 2 else 24

files = sorted(f for f in os.listdir(frames_dir) if f.lower().endswith(".png"))
scene = bpy.context.scene
img = bpy.data.images.load(os.path.join(frames_dir, files[0]))
scene.render.resolution_x, scene.render.resolution_y = img.size
scene.render.resolution_percentage = 100
scene.render.fps = fps
scene.frame_start, scene.frame_end = 1, len(files)

seq = scene.sequence_editor_create()
strips = seq.strips if hasattr(seq, "strips") else seq.sequences
strip = strips.new_image("frames", os.path.join(frames_dir, files[0]), 1, 1)
for name in files[1:]:
    strip.elements.append(name)
scene.render.use_sequencer = True

settings = scene.render.image_settings
if hasattr(settings, "media_type"):
    settings.media_type = 'VIDEO'
settings.file_format = 'FFMPEG'
ff = scene.render.ffmpeg
ff.format = 'MPEG4'
ff.codec = 'H264'
ff.constant_rate_factor = 'HIGH'
ff.ffmpeg_preset = 'GOOD'
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = out_path
print("Encoding %d frames to %s" % (len(files), out_path))
bpy.ops.render.render(animation=True)
