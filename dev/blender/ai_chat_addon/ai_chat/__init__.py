bl_info = {
    "name": "AI Chat",
    "author": "Facesnatcher",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "3D Viewport > Sidebar (N) > AI Chat",
    "description": "Chat with an AI model (Claude by default) using your own API key",
    "category": "Interface",
}

import bpy
from bpy.app.handlers import persistent

from . import chat, operators, preferences, ui

_classes = (preferences.AIChatPreferences,) + ui.classes + operators.classes


def _on_input_changed(wm, context):
    # Send on Enter: confirming the text field fires this update. Clearing the
    # field fires it again with an empty string, which is ignored.
    text = wm.ai_chat_input.strip()
    prefs = preferences.get(context)
    if text and prefs and prefs.send_on_enter and chat.is_idle():
        wm.ai_chat_input = ""
        chat.send(context, text)


@persistent
def _on_load_post(*_args):
    # Loading a file replaces the window manager's runtime properties.
    chat.refresh(bpy.context.window_manager)


def register():
    for cls in _classes:
        bpy.utils.register_class(cls)
    # Window manager properties are runtime-only and never saved in the .blend.
    wm = bpy.types.WindowManager
    wm.ai_chat_input = bpy.props.StringProperty(
        name="Message", description="Message to send", update=_on_input_changed
    )
    wm.ai_chat_lines = bpy.props.CollectionProperty(type=ui.AIChatLine)
    wm.ai_chat_line_index = bpy.props.IntProperty()
    wm.ai_chat_include_scene = bpy.props.BoolProperty(
        name="Include Scene Context",
        description="Send a short summary of the scene (objects, selection) with each message",
        default=True,
    )
    bpy.app.handlers.load_post.append(_on_load_post)


def unregister():
    chat.unregister()
    if _on_load_post in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.remove(_on_load_post)
    wm = bpy.types.WindowManager
    for name in ("ai_chat_input", "ai_chat_lines", "ai_chat_line_index", "ai_chat_include_scene"):
        delattr(wm, name)
    for cls in reversed(_classes):
        bpy.utils.unregister_class(cls)
