"""Animated review of the green stacker (run inside Blender after stacker_build.build(M, animated=True)).

A kinematic run of the line, worked out step by step and played back frame by frame through a
frame-change handler:
- the unscrambler lug chains climb with a board on every lug; each lug tips its board over the
  head onto the infeed chains;
- the line-up rolls drive each board endwise against the fence; boards gather against the
  layer stops (and queue at the hold stops while the forks are busy);
- a full layer: stops drop, forks lift and carry the layer out over the package, the pull-back
  fence drops behind it, the forks pull back and the layer falls onto the package;
- the stick gates open and a stick falls onto every stick line; the hoist lowers one board plus
  one stick; the fence rises, the forks lower, the hold stops drop and the next layer forms.

Render: python -c in a background Blender, see render_animation().
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "bin_sorter"))
sys.path.insert(0, HERE)
import mesh_lib as L  # noqa: E402
import sorter_build as S  # noqa: E402
import stacker_build as B  # noqa: E402

G = S.G
FPS = 24
STEP = 1.0 / 240.0
V_UNS = 0.6                  # unscrambler chain, m/s: one lug (one board) per second
V_INF = 1.0                  # stacker infeed chain, m/s
LINEUP_V = 0.5               # endwise speed the line-up rolls give a board
T, W, N = B.PREVIEW_T, B.PREVIEW_W, B.PREVIEW_PER_LAYER
BOARD_LEN = 4.877
LUG_FACE = B.UNS_PITCH * 0.62 + 0.002
GAP = 0.002
FENCE_FACE = B.FENCE_X + 0.02
FORK_TIP_HOME = B.FORK_X0 + B.FORK_LEN
TIP_DOWN_TIME = 0.25         # head transfer: board lays down flat over this time
CYCLE = (("stops_down", 0.25), ("lift", 0.4), ("extend", 1.5), ("fence_down", 0.35), ("retract", 1.5),
         ("settle", 0.2), ("sticks", 0.45), ("lower", 0.6), ("reset", 0.4))


def ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


class Board:
    def __init__(self, idx, z0):
        self.idx = idx
        self.z0 = z0
        self.state = "incline"       # incline -> tip -> feed -> layer -> falling -> package
        self.s = 0.0
        self.x = 0.0
        self.y = B.INFEED_TOP
        self.angle = 0.0
        self.tip_t = 0.0
        self.rel_y = 0.0             # height on the package, relative to the hoist offset
        self.fall_t = 0.0


class Sim:
    def __init__(self):
        path, total = B.uns_loop()
        self.uns_total = total
        count = int(round(total / B.UNS_PITCH))
        self.uns_pitch = total / count
        self.lug_ks = [k for k in range(count) if k % B.UNS_LUG_EVERY == 0]
        self.span = (B.UNS_HEAD - B.UNS_FOOT).length
        self.lug_board = {}          # lug k -> Board while it rides that lug
        self.boards = []
        self.sticks = []             # (z, y_now, rel_y or None, fall_t)
        self.t = 0.0
        self.fork_dx = self.fork_dy = 0.0
        self.fence = B.FENCE_RAISE
        self.layer_stop = 0.0        # 0 up, 1 down
        self.hold_stop = 1.0
        self.gate = 0.0
        self.hoist_dy0 = -B.PREVIEW_LAYERS * (T + B.STICK_T)
        self.hoist_dy = self.hoist_dy0
        self.cycle = None            # (phase index, time in phase, layer boards)
        self.layers_done = 0
        self.seed = 7

    def rand(self):
        self.seed = (self.seed * 1103515245 + 12345) & 0x7FFFFFFF
        return self.seed / 0x7FFFFFFF

    def lug_s(self, k):
        return (V_UNS * self.t + k * self.uns_pitch) % self.uns_total

    def step(self):
        dt = STEP
        self.t += dt
        # Unscrambler: a board appears on each lug as it leaves the pocket pile, and goes over the head.
        for k in self.lug_ks:
            s = self.lug_s(k)
            b = self.lug_board.get(k)
            if b is None and 0.25 < s < 0.6:
                b = Board(len(self.boards), -2.42 + 0.06 * self.rand())
                self.boards.append(b)
                self.lug_board[k] = b
            if b is not None:
                b.s = s + LUG_FACE
                if b.s >= self.span or s > self.span:
                    b.state = "tip"
                    b.tip_t = 0.0
                    top = B.UNS_FOOT + B.UNS_NORMAL * (B.UNS_SPR + B.UNS_PLATE_H) + B.UNS_DIR * self.span
                    b.x = top.x
                    del self.lug_board[k]
        feed = sorted((b for b in self.boards if b.state in ("tip", "feed")), key=lambda b: -b.x)
        ahead_front = None
        for b in feed:
            if b.state == "tip":
                b.tip_t += dt
                b.angle = B.UNS_ANGLE * (1.0 - ease(b.tip_t / TIP_DOWN_TIME))
                if b.tip_t >= TIP_DOWN_TIME:
                    b.state = "feed"
            limit = 1e9
            if ahead_front is not None:
                limit = ahead_front - GAP - W
            if self.layer_stop < 0.5:
                limit = min(limit, B.LAYER_STOP_X - W)
            if self.hold_stop < 0.5 and b.x + W <= B.HOLD_STOP_X + 0.01:
                limit = min(limit, B.HOLD_STOP_X - W)
            b.x = min(b.x + V_INF * dt, max(limit, b.x))
            if 25.8 < b.x < 27.2:
                b.z0 = max(B.LINEUP_FENCE_Z, b.z0 - LINEUP_V * dt)
            ahead_front = b.x
        # Hold stops rise once a full layer is past them (and nothing straddles them).
        past = [b for b in feed if b.state == "feed" and b.x > B.HOLD_STOP_X + 0.04]
        straddle = any(b.x < B.HOLD_STOP_X + 0.035 < b.x + W for b in feed)
        if self.cycle is None and len(past) >= N and not straddle:
            self.hold_stop = max(0.0, self.hold_stop - dt / 0.25)
        if self.cycle is None and len(past) >= N and self.hold_stop <= 0.0:
            front = sorted(past, key=lambda b: -b.x)[:N]
            if all(abs(front[i].x - (B.LAYER_STOP_X - W - i * (W + GAP))) < 0.01 for i in range(N)):
                for b in front:
                    b.state = "layer"
                self.cycle = [0, 0.0, front]
        if self.cycle is not None:
            self.run_cycle(dt)
        for b in self.boards:
            if b.state == "falling":
                b.fall_t += dt
                b.y = max(B.HOIST_TOP + b.rel_y_target, b.y - 9.81 * b.fall_t * dt)
                if b.y <= B.HOIST_TOP + b.rel_y_target + 1e-4:
                    b.state = "package"
                    b.rel_y = b.y - self.hoist_dy
        for st in self.sticks:
            if st[2] is None:
                st[3] += dt
                st[1] = max(B.HOIST_TOP + T, st[1] - 9.81 * st[3] * dt)
                if st[1] <= B.HOIST_TOP + T + 1e-4:
                    st[2] = st[1] - self.hoist_dy

    def run_cycle(self, dt):
        phase, tp, layer = self.cycle
        name, dur = CYCLE[phase]
        tp += dt
        u = ease(tp / dur)
        if name == "stops_down":
            self.layer_stop = u
        elif name == "lift":
            self.fork_dy = B.FORK_LIFT * u
            for b in layer:
                b.y = max(B.INFEED_TOP, B.FORK_HOME_TOP + self.fork_dy)
        elif name == "extend":
            old = self.fork_dx
            self.fork_dx = B.FORK_STROKE * u
            for b in layer:
                b.x += self.fork_dx - old
            if u >= 1.0:
                self.layer_stop = 0.0
        elif name == "fence_down":
            self.fence = B.FENCE_RAISE * (1.0 - u)
        elif name == "retract":
            old = self.fork_dx
            self.fork_dx = B.FORK_STROKE * (1.0 - u)
            move = self.fork_dx - old
            upstream = min(b.x for b in layer)
            back = max(move, FENCE_FACE - upstream)          # dragged back until the layer meets the fence
            tip = FORK_TIP_HOME + self.fork_dx
            for b in layer:
                if b.state == "layer":
                    b.x += min(back, 0.0)
                    if tip < b.x + W * 0.5:
                        b.state = "falling"
                        b.fall_t = 0.0
                        b.rel_y_target = 0.0
        elif name == "settle":
            pass
        elif name == "sticks":
            self.gate = min(1.0, tp / 0.12) if tp < 0.3 else max(0.0, 1.0 - (tp - 0.3) / 0.12)
            if not any(st[4] == self.layers_done for st in self.sticks):
                for z in B.STICK_Z:
                    self.sticks.append([z, B.MAG_BOTTOM - B.STICK_T, None, 0.0, self.layers_done])
        elif name == "lower":
            step_h = T + B.STICK_T
            target = self.hoist_dy0 - (self.layers_done + 1) * step_h
            start = target + step_h
            self.hoist_dy = start + (target - start) * u
            self.fence = B.FENCE_RAISE * u
        elif name == "reset":
            self.fork_dy = B.FORK_LIFT * (1.0 - u)
            self.hold_stop = u
        if tp >= dur:
            phase += 1
            tp = 0.0
            if phase >= len(CYCLE):
                self.layers_done += 1
                self.cycle = None
                return
        self.cycle = [phase, tp, layer]

    def snapshot(self):
        boards = []
        for b in self.boards:
            if b.state == "incline":
                boards.append((b.idx, "incline", b.s, 0.0, b.z0, 0.0))
            elif b.state in ("tip", "feed", "layer", "falling"):
                boards.append((b.idx, "flat", b.x, b.y, b.z0, b.angle))
            else:
                boards.append((b.idx, "flat", b.x, b.rel_y + self.hoist_dy, b.z0, 0.0))
        sticks = [(i, st[0], st[1] if st[2] is None else st[2] + self.hoist_dy) for i, st in enumerate(self.sticks)]
        return {"t": self.t, "boards": boards, "sticks": sticks, "fork": (self.fork_dx, self.fork_dy), "fence": self.fence,
                "layer_stop": self.layer_stop, "hold_stop": self.hold_stop, "gate": self.gate, "hoist": self.hoist_dy}


PREROLL = 7.0               # seconds run before the first frame, so the lugs are already loaded


def simulate(seconds):
    sim = Sim()
    frames = []
    per_frame = int(round(1.0 / (FPS * STEP)))
    for _ in range(int(PREROLL / STEP)):
        sim.step()
    for f in range(int(seconds * FPS)):
        for _ in range(per_frame):
            sim.step()
        frames.append(sim.snapshot())
    return frames


# ---------------------------------------------------------------- playback

FRAMES = []
COLL = "StackerAnim"


def _box_mesh(name, sx, sy, sz, material):
    """Shared box mesh; each pooled object gets its own grain from its object random value."""
    me = bpy.data.meshes.get(name)
    if me is None:
        bm = bmesh.new()
        L.add_box(bm, (sx, sy, sz))
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(bpy.data.materials[material])
    return me


def _pool(prefix, mesh, count):
    coll = bpy.data.collections.get(COLL) or L.collection(COLL)
    objs = []
    for i in range(count):
        name = "%s_%03d" % (prefix, i)
        o = bpy.data.objects.get(name)
        if o is None:
            o = bpy.data.objects.new(name, mesh)
            coll.objects.link(o)
        objs.append(o)
    return objs


def board_matrix(kind, a, y, z0, angle):
    if kind == "incline":
        p0 = B.UNS_FOOT + B.UNS_NORMAL * (B.UNS_SPR + B.UNS_PLATE_H) + B.UNS_DIR * a
        return S.gmat(p0.x, p0.y, z0, (0, -math.degrees(B.UNS_ANGLE), 0)) @ L.mat((W / 2, -BOARD_LEN / 2, T / 2))
    return S.gmat(a, y, z0, (0, -math.degrees(angle), 0)) @ L.mat((W / 2, -BOARD_LEN / 2, T / 2))


def rebuild_chain(name, src_name, loop, pitch, strands, every, phase):
    path, total = loop
    count = int(round(total / pitch))
    pitch = total / count
    src = bpy.data.objects[src_name].data
    bm = bmesh.new()
    for k in range(count):
        if every and k % every:
            continue
        s = phase + k * pitch
        p1, p2 = path(s), path(s + pitch)
        for z in strands:
            m = S.link_matrix(p1, p2, z)
            start = len(bm.verts)
            bm.from_mesh(src)
            bm.verts.ensure_lookup_table()
            for v in bm.verts[start:]:
                v.co = m @ v.co
    o = bpy.data.objects[name]
    old = o.data
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for mat in old.materials:
        me.materials.append(mat)
    o.data = me
    bpy.data.meshes.remove(old)


def apply_frame(f):
    if not FRAMES:
        return
    snap = FRAMES[min(max(f - 1, 0), len(FRAMES) - 1)]
    t = snap["t"]
    boards = _pool("AnimBoard", _box_mesh("AnimBoardMesh", W, BOARD_LEN, T, "Sorter_Lumber"), MAX_BOARDS)
    seen = set()
    for idx, kind, a, y, z0, angle in snap["boards"]:
        o = boards[idx % MAX_BOARDS]
        o.matrix_world = board_matrix(kind, a, y, z0, angle)
        o.hide_render = o.hide_viewport = False
        seen.add(idx % MAX_BOARDS)
    for i, o in enumerate(boards):
        if i not in seen:
            o.hide_render = o.hide_viewport = True
    sticks = _pool("AnimStick", _box_mesh("AnimStickMesh", B.STICK_LEN, B.STICK_W, B.STICK_T, "Stacker_Sticks"), MAX_STICKS)
    seen = set()
    for i, z, y in snap["sticks"]:
        o = sticks[i % MAX_STICKS]
        o.matrix_world = S.gmat(B.STICK_X0 + B.STICK_LEN / 2, y + B.STICK_T / 2, z)
        o.hide_render = o.hide_viewport = False
        seen.add(i % MAX_STICKS)
    for i, o in enumerate(sticks):
        if i not in seen:
            o.hide_render = o.hide_viewport = True
    dx, dy = snap["fork"]
    for n in ("Forks", "ForkWear"):
        bpy.data.objects[n].location = G(dx, dy, 0)
    for n in ("ForkTrolley", "ForkTrolleyGear"):
        bpy.data.objects[n].location = G(dx, 0, 0)
    bpy.data.objects["PullbackFence"].location = G(0, snap["fence"], 0)
    bpy.data.objects["LayerStops"].location = G(0, -B.STOP_DROP * snap["layer_stop"], 0)
    bpy.data.objects["HoldStops"].location = G(0, -B.STOP_DROP * snap["hold_stop"], 0)
    bpy.data.objects["StickGates"].location = G(0.05 * snap["gate"], 0, 0)
    bpy.data.objects["Hoist"].location = G(0, snap["hoist"], 0)
    bpy.data.objects["PreviewPackage"].location = G(0, snap["hoist"] - (-B.PREVIEW_LAYERS * (T + B.STICK_T)), 0)
    # Chains and shafts.
    rebuild_chain("PreviewUnscramblerChain", "BarChainLink", B.uns_loop(), B.UNS_PITCH, B.UNS_Z, None, V_UNS * t)
    rebuild_chain("PreviewUnscramblerLugs", "UnscramblerLug", B.uns_loop(), B.UNS_PITCH, B.UNS_Z, B.UNS_LUG_EVERY, V_UNS * t)
    rebuild_chain("PreviewInfeedChain", "BarChainLink", B.infeed_loop(), B.INF_PITCH, B.INF_Z, None, V_INF * t)
    for n, v, r in (("UnscramblerHeadShaft", V_UNS, B.UNS_SPR), ("UnscramblerFootShaft", V_UNS, B.UNS_SPR),
                    ("InfeedHeadShaft", V_INF, B.INF_SPR), ("InfeedTailSprockets", V_INF, B.INF_SPR)):
        bpy.data.objects[n].rotation_euler = (0.0, v * t / r, 0.0)        # clockwise seen from +Z (Blender -Y)
    for o in bpy.data.objects:
        if o.name.startswith("LineupRoll_"):
            o.rotation_euler = (-LINEUP_V * t / B.ROLL_R, 0.0, 0.0)


MAX_BOARDS = 80
MAX_STICKS = 80


def _on_frame(scene, depsgraph=None):
    apply_frame(scene.frame_current)


def setup(seconds=30.0):
    global FRAMES
    FRAMES = simulate(seconds)
    for h in list(bpy.app.handlers.frame_change_pre):
        if getattr(h, "__name__", "") == "_on_frame":
            bpy.app.handlers.frame_change_pre.remove(h)
    bpy.app.handlers.frame_change_pre.append(_on_frame)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, len(FRAMES)
    scene.render.use_lock_interface = True
    apply_frame(1)
    return {"frames": len(FRAMES), "boards": max(len(fr["boards"]) for fr in FRAMES),
            "layers": FRAMES[-1]["hoist"]}


def camera_cuts(wide, close):
    """Timeline markers that cut to the close camera for each stacker cycle and back to the
    wide one while the next layer forms."""
    scene = bpy.context.scene
    scene.timeline_markers.clear()
    m = scene.timeline_markers.new("wide", frame=1)
    m.camera = bpy.data.objects[wide]
    busy = [f["layer_stop"] > 0.01 or f["fork"][0] > 0.001 or f["fence"] < B.FENCE_RAISE - 1e-3 or f["gate"] > 0.0
            for f in FRAMES]
    f = 0
    while f < len(busy):
        if busy[f]:
            start = f
            while f < len(busy) and (busy[f] or any(busy[f:f + 30])):
                f += 1
            m = scene.timeline_markers.new("close", frame=max(1, start - 6))
            m.camera = bpy.data.objects[close]
            m = scene.timeline_markers.new("wide", frame=min(len(busy), f + 24))
            m.camera = bpy.data.objects[wide]
        f += 1


def render_animation(out_path, camera, seconds=30.0, res=(1280, 720), close=None):
    info = setup(seconds)
    scene = bpy.context.scene
    if close:
        camera_cuts(camera, close)
    try:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.camera = bpy.data.objects[camera]
    fmt = scene.render.image_settings
    if hasattr(fmt, "media_type"):
        fmt.media_type = 'VIDEO'
    fmt.file_format = 'FFMPEG'
    scene.render.ffmpeg.format = 'MPEG4'
    scene.render.ffmpeg.codec = 'H264'
    scene.render.ffmpeg.constant_rate_factor = 'HIGH'
    scene.render.filepath = out_path
    bpy.ops.render.render(animation=True)
    return info
