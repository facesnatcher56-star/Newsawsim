"""Short plain-text summary of the current scene, sent as background context.

Uses bpy.context's scene and view layer only, so it also works from timers.
"""

import bpy

# Objects listed by name; the selected ones also get their location and size.
MAX_OBJECTS = 25
MAX_DETAILED = 8


def _vec(v):
    return "(" + ", ".join(f"{c:.3g}" for c in v) + ")"


def build():
    scene = bpy.context.scene
    view_layer = bpy.context.view_layer
    active = view_layer.objects.active
    selected = list(view_layer.objects.selected)
    objects = list(scene.objects)
    mode = active.mode.lower().replace("_", " ") if active else "object"

    lines = [
        f"Scene '{scene.name}', {mode} mode, frame {scene.frame_current}, {len(objects)} objects",
        f"Active object: {active.name if active else 'none'}",
    ]
    if selected:
        lines.append(f"Selected ({len(selected)}):")
        for obj in selected[:MAX_DETAILED]:
            detail = f"{obj.type.lower()}, location {_vec(obj.location)}"
            if obj.type == "MESH":
                detail += f", size {_vec(obj.dimensions)}"
            lines.append(f"- {obj.name}: {detail}")
        if len(selected) > MAX_DETAILED:
            lines.append(f"- ... and {len(selected) - MAX_DETAILED} more selected")
    else:
        lines.append("Selected: none")

    names = ", ".join(f"{o.name} ({o.type.lower()})" for o in objects[:MAX_OBJECTS])
    more = f", ... and {len(objects) - MAX_OBJECTS} more" if len(objects) > MAX_OBJECTS else ""
    lines.append(f"Objects: {names}{more}")
    return "\n".join(lines)
