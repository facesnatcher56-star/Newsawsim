"""Tools the model can call to look at and change the Blender scene.

Inspection tools run as soon as the model asks. Tools with needs_approval
wait until the user presses Approve in the panel; they then run inside an
operator with an undo step, so Ctrl+Z reverts them.

Handlers run on Blender's main thread, take (context, args) and return text
for the model. They raise ToolError for problems the model should hear about.
"""

import contextlib
import io
import math
import traceback

import bpy

MAX_RESULT_CHARS = 6000


class ToolError(Exception):
    pass


class Tool:
    def __init__(self, name, description, parameters, handler, *, label, needs_approval=False,
                 describe=None):
        self.name = name
        self.description = description
        self.parameters = parameters
        self.handler = handler
        # Short phrase for the chat view, e.g. "list objects".
        self.label = label
        self.needs_approval = needs_approval
        # describe(args) -> lines shown in the approval box.
        self.describe = describe or (lambda args: [f"{k}: {v}" for k, v in args.items()])

    def definition(self):
        return {"name": self.name, "description": self.description, "parameters": self.parameters}

    def run(self, context, args):
        """Return (text, is_error)."""
        try:
            text = self.handler(context, args)
            is_error = False
        except ToolError as e:
            text, is_error = str(e), True
        except Exception as e:
            text, is_error = f"{type(e).__name__}: {e}", True
        if len(text) > MAX_RESULT_CHARS:
            text = text[:MAX_RESULT_CHARS] + f"\n... (truncated, {len(text)} characters total)"
        return text, is_error


def _schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {}, "required": list(required)}


def _vec(v):
    return "(" + ", ".join(f"{c:.4g}" for c in v) + ")"


def _deg(euler):
    return "(" + ", ".join(f"{math.degrees(a):.4g}" for a in euler) + ")"


def _get_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise ToolError(f"No object named '{name}'")
    return obj


def _vector_arg(args, key):
    value = args.get(key)
    if value is None:
        return None
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        raise ToolError(f"'{key}' must be a list of 3 numbers")
    return [float(c) for c in value]


# --- Inspection (no approval) ----------------------------------------------

def _scene_info(context, args):
    scene = bpy.context.scene
    view_layer = bpy.context.view_layer
    active = view_layer.objects.active
    render = scene.render
    lines = [
        f"File: {bpy.data.filepath or '(unsaved)'}",
        f"Scene '{scene.name}', view layer '{view_layer.name}'",
        f"Mode: {active.mode.lower() if active else 'object'}",
        f"Frame {scene.frame_current}, range {scene.frame_start}-{scene.frame_end}, "
        f"{render.fps / render.fps_base:g} fps",
        f"Units: {scene.unit_settings.system}, scale {scene.unit_settings.scale_length:g}",
        f"Render: {render.engine}, {render.resolution_x}x{render.resolution_y} "
        f"at {render.resolution_percentage}%",
        f"Camera: {scene.camera.name if scene.camera else 'none'}, "
        f"world: {scene.world.name if scene.world else 'none'}",
        f"Active object: {active.name if active else 'none'}",
        f"Selected: {', '.join(o.name for o in view_layer.objects.selected) or 'none'}",
        f"Objects: {len(scene.objects)}",
        "Collections:",
    ]

    def walk(collection, depth):
        lines.append(f"{'  ' * depth}- {collection.name} ({len(collection.objects)} objects)")
        for child in collection.children:
            walk(child, depth + 1)

    walk(scene.collection, 1)
    return "\n".join(lines)


def _list_objects(context, args):
    view_layer = bpy.context.view_layer
    type_filter = (args.get("type") or "").upper()
    contains = (args.get("name_contains") or "").lower()
    limit = max(1, min(int(args.get("limit") or 200), 1000))
    active = view_layer.objects.active
    matches = [
        o for o in bpy.context.scene.objects
        if (not type_filter or o.type == type_filter) and contains in o.name.lower()
    ]
    lines = []
    for obj in matches[:limit]:
        flags = []
        if obj == active:
            flags.append("active")
        if obj.select_get():
            flags.append("selected")
        if obj.hide_get() or obj.hide_viewport:
            flags.append("hidden")
        if obj.parent:
            flags.append(f"parent {obj.parent.name}")
        extra = f" [{', '.join(flags)}]" if flags else ""
        lines.append(f"{obj.name} ({obj.type}) at {_vec(obj.location)}{extra}")
    if len(matches) > limit:
        lines.append(f"... {len(matches) - limit} more (raise 'limit' or filter)")
    return "\n".join(lines) or "No matching objects."


def _object_details(context, args):
    obj = _get_object(args.get("name", ""))
    view_layer = bpy.context.view_layer
    lines = [
        f"{obj.name} ({obj.type}), data: {obj.data.name if obj.data else 'none'}",
        f"Location {_vec(obj.location)}, rotation {obj.rotation_mode} {_deg(obj.rotation_euler)} deg, "
        f"scale {_vec(obj.scale)}",
        f"Dimensions {_vec(obj.dimensions)}, world location {_vec(obj.matrix_world.translation)}",
        f"Parent: {obj.parent.name if obj.parent else 'none'}; "
        f"children: {', '.join(c.name for c in obj.children[:30]) or 'none'}",
        f"Collections: {', '.join(c.name for c in obj.users_collection)}",
        f"Selected: {obj.select_get()}, active: {obj == view_layer.objects.active}, "
        f"hidden: {obj.hide_get()}, viewport disabled: {obj.hide_viewport}, "
        f"render disabled: {obj.hide_render}",
    ]
    if obj.modifiers:
        lines.append("Modifiers: " + ", ".join(f"{m.name} ({m.type})" for m in obj.modifiers))
    if obj.material_slots:
        lines.append("Materials: " + ", ".join(s.material.name if s.material else "(empty)"
                                                for s in obj.material_slots))
    if obj.type == "MESH":
        mesh = obj.data
        lines.append(f"Mesh: {len(mesh.vertices)} verts, {len(mesh.edges)} edges, "
                     f"{len(mesh.polygons)} faces, UV maps: "
                     f"{', '.join(uv.name for uv in mesh.uv_layers) or 'none'}")
    elif obj.type == "LIGHT":
        lines.append(f"Light: {obj.data.type}, energy {obj.data.energy:g}, color {_vec(obj.data.color)}")
    elif obj.type == "CAMERA":
        lines.append(f"Camera: {obj.data.type}, lens {obj.data.lens:g} mm, "
                     f"clip {obj.data.clip_start:g}-{obj.data.clip_end:g}")
    custom = [k for k in obj.keys() if not k.startswith("_")]
    if custom:
        lines.append("Custom properties: " + ", ".join(f"{k}={obj[k]!r}" for k in custom[:30]))
    return "\n".join(lines)


# --- Changes (need approval) -----------------------------------------------

def _run_python(context, args):
    code = args.get("code") or ""
    namespace = {"bpy": bpy, "C": context, "D": bpy.data, "__name__": "__ai_chat__"}
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            exec(compile(code, "<ai_chat>", "exec"), namespace)
    except Exception:
        raise ToolError(output.getvalue() + traceback.format_exc(limit=-3)) from None
    text = output.getvalue()
    if "result" in namespace:
        text += f"\nresult = {namespace['result']!r}"
    return text.strip() or "Ran without output."


def _describe_python(args):
    lines = []
    if args.get("explanation"):
        lines += [args["explanation"], ""]
    return lines + (args.get("code") or "").splitlines()


def _select_objects(context, args):
    names = args.get("names") or []
    objects = [_get_object(n) for n in names]
    view_layer = bpy.context.view_layer
    if args.get("deselect_others", True):
        for obj in view_layer.objects.selected:
            obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    if objects:
        view_layer.objects.active = objects[0]
    return f"Selected {len(objects)} objects; active is {objects[0].name if objects else 'unchanged'}."


def _describe_select(args):
    names = args.get("names") or []
    lines = [f"Select {len(names)} objects: {', '.join(names)}"]
    if args.get("deselect_others", True):
        lines.append("and deselect everything else")
    return lines


def _set_transform(context, args):
    obj = _get_object(args.get("name", ""))
    location = _vector_arg(args, "location")
    rotation = _vector_arg(args, "rotation_degrees")
    scale = _vector_arg(args, "scale")
    if location:
        obj.location = location
    if rotation:
        if obj.rotation_mode in {"QUATERNION", "AXIS_ANGLE"}:
            obj.rotation_mode = "XYZ"
        obj.rotation_euler = [math.radians(a) for a in rotation]
    if scale:
        obj.scale = scale
    return (f"{obj.name}: location {_vec(obj.location)}, rotation {_deg(obj.rotation_euler)} deg, "
            f"scale {_vec(obj.scale)}")


def _describe_transform(args):
    lines = [f"Object: {args.get('name')}"]
    for key, label in (("location", "Location"), ("rotation_degrees", "Rotation (deg)"),
                       ("scale", "Scale")):
        if args.get(key) is not None:
            lines.append(f"{label} -> {args[key]}")
    return lines


def _delete_objects(context, args):
    objects = [_get_object(n) for n in (args.get("names") or [])]
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    return f"Deleted {len(objects)} objects."


def _describe_delete(args):
    names = args.get("names") or []
    return [f"Delete {len(names)} objects:", ", ".join(names)]


_NAMES = {"type": "array", "items": {"type": "string"}, "description": "Exact object names"}
_VEC3 = {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}

TOOLS = [
    Tool(
        "get_scene_info",
        "Overview of the open Blender file: scene settings, frame range, units, render "
        "settings, camera, collections, active and selected objects.",
        _schema(),
        _scene_info,
        label="look at the scene",
    ),
    Tool(
        "list_objects",
        "List objects in the scene with type, location and flags (active, selected, "
        "hidden, parent). Optionally filter by type or name.",
        _schema({
            "type": {"type": "string", "description": "Object type, e.g. MESH, LIGHT, CAMERA, EMPTY"},
            "name_contains": {"type": "string", "description": "Case-insensitive name filter"},
            "limit": {"type": "integer", "description": "Maximum objects to return (default 200)"},
        }),
        _list_objects,
        label="list objects",
    ),
    Tool(
        "get_object_details",
        "Details of one object: transform, dimensions, parent and children, collections, "
        "visibility, modifiers, materials, mesh stats, light or camera settings.",
        _schema({"name": {"type": "string", "description": "Exact object name"}}, ["name"]),
        _object_details,
        label="look at an object",
    ),
    Tool(
        "run_python",
        "Run Python in the user's Blender session with bpy available (also C = context, "
        "D = bpy.data). Use for anything the other tools can't do. print() output and a "
        "variable named `result` are returned. The user must approve each run.",
        _schema({
            "code": {"type": "string", "description": "Python source to execute"},
            "explanation": {"type": "string",
                            "description": "One sentence telling the user what the code does"},
        }, ["code", "explanation"]),
        _run_python,
        label="run Python",
        needs_approval=True,
        describe=_describe_python,
    ),
    Tool(
        "select_objects",
        "Select objects by name and make the first one active. The user must approve.",
        _schema({
            "names": _NAMES,
            "deselect_others": {"type": "boolean", "description": "Deselect everything else first (default true)"},
        }, ["names"]),
        _select_objects,
        label="select objects",
        needs_approval=True,
        describe=_describe_select,
    ),
    Tool(
        "set_transform",
        "Set an object's location, rotation (degrees, XYZ Euler) and/or scale. Omit what "
        "should stay unchanged. The user must approve.",
        _schema({
            "name": {"type": "string", "description": "Exact object name"},
            "location": _VEC3,
            "rotation_degrees": _VEC3,
            "scale": _VEC3,
        }, ["name"]),
        _set_transform,
        label="move an object",
        needs_approval=True,
        describe=_describe_transform,
    ),
    Tool(
        "delete_objects",
        "Delete objects by name. The user must approve.",
        _schema({"names": _NAMES}, ["names"]),
        _delete_objects,
        label="delete objects",
        needs_approval=True,
        describe=_describe_delete,
    ),
]

_BY_NAME = {t.name: t for t in TOOLS}


def get(name):
    return _BY_NAME.get(name)


def definitions():
    return [t.definition() for t in TOOLS]
