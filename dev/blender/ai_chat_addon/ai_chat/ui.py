import bpy

from . import chat, preferences, providers

ROLE_ICONS = {
    "user": "USER",
    "assistant": "OUTLINER_OB_LIGHT",
    "tool": "TOOL_SETTINGS",
    "error": "ERROR",
    "info": "INFO",
}
# Longest proposed action shown in the approval box; Copy gives the rest.
MAX_APPROVAL_LINES = 30


class AIChatLine(bpy.types.PropertyGroup):
    text: bpy.props.StringProperty()
    role: bpy.props.StringProperty()
    header: bpy.props.BoolProperty()


class AI_CHAT_UL_lines(bpy.types.UIList):
    def draw_item(self, context, layout, data, item, icon, active_data, active_propname, index):
        if item.header:
            row = layout.row()
            row.alert = item.role == "error"
            row.label(text=item.text, icon=ROLE_ICONS.get(item.role, "DOT"))
        else:
            layout.label(text=item.text, icon="BLANK1")

    def draw_filter(self, context, layout):
        pass


class VIEW3D_PT_ai_chat(bpy.types.Panel):
    bl_label = "AI Chat"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "AI Chat"

    def draw(self, context):
        layout = self.layout
        wm = context.window_manager
        prefs = preferences.get(context)
        provider = providers.get(prefs.provider)

        # Wrap to the sidebar width, minus the list's icon, padding and scrollbar.
        scale = context.preferences.system.ui_scale
        chat.request_wrap(int(context.region.width - 115 * scale))

        row = layout.row(align=True)
        row.label(text=preferences.get_model(prefs) or "No model", icon="OUTLINER_OB_LIGHT")
        row.operator("ai_chat.open_prefs", text="", icon="PREFERENCES")

        _, source = preferences.get_api_key(prefs)
        if source is None:
            box = layout.box()
            box.alert = True
            box.label(text="No API key set", icon="ERROR")
            box.label(text="Add it in Preferences, or set")
            box.label(text=f"the {provider.env_var} variable")
            box.operator("ai_chat.open_prefs", text="Open Preferences", icon="PREFERENCES")

        # Above the chat list, so the buttons are visible without scrolling.
        tool = chat.awaiting_tool()
        if tool:
            self.draw_approval(layout, provider, tool)

        layout.template_list(
            "AI_CHAT_UL_lines", "", wm, "ai_chat_lines", wm, "ai_chat_line_index",
            rows=prefs.chat_rows,
        )

        if chat.state.busy:
            row = layout.row()
            row.label(text=f"Waiting for reply... {chat.elapsed():.0f}s", icon="SORTTIME")
            row.operator("ai_chat.cancel", text="", icon="CANCEL")

        row = layout.row(align=True)
        row.enabled = chat.is_idle()
        row.prop(wm, "ai_chat_input", text="", icon="GREASEPENCIL")
        row.operator("ai_chat.send", text="", icon="PLAY")

        row = layout.row(align=True)
        row.prop(wm, "ai_chat_include_scene", text="Scene Context", toggle=True, icon="SCENE_DATA")
        row.operator("ai_chat.copy_last", text="", icon="COPYDOWN")
        row.operator("ai_chat.clear", text="", icon="TRASH")

    def draw_approval(self, layout, provider, tool):
        box = layout.box()
        header = box.row()
        header.alert = True
        header.label(text=f"{provider.assistant_name} wants to {tool.label}", icon="QUESTION")
        col = box.column(align=True)
        lines = chat.state.awaiting_wrapped
        for line in lines[:MAX_APPROVAL_LINES]:
            col.label(text=line)
        if len(lines) > MAX_APPROVAL_LINES:
            col.label(text=f"... {len(lines) - MAX_APPROVAL_LINES} more lines (Copy to read all)")
        row = box.row(align=True)
        row.scale_y = 1.3
        row.operator("ai_chat.approve", icon="CHECKMARK")
        row.operator("ai_chat.deny", icon="X")
        if chat.state.awaiting["arguments"].get("code"):
            row.operator("ai_chat.copy_pending", text="", icon="COPYDOWN")


classes = (AIChatLine, AI_CHAT_UL_lines, VIEW3D_PT_ai_chat)
