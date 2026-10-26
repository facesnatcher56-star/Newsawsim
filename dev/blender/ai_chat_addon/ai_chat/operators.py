import threading

import bpy

from . import chat, preferences, providers
from .providers import ProviderError


class AI_CHAT_OT_send(bpy.types.Operator):
    bl_idname = "ai_chat.send"
    bl_label = "Send"
    bl_description = "Send the message to the AI model"

    @classmethod
    def poll(cls, context):
        return chat.is_idle()

    def execute(self, context):
        wm = context.window_manager
        text = wm.ai_chat_input.strip()
        if not text:
            # With Send on Enter, clicking Send confirms the field and sends it
            # first, so an empty box here is expected and not worth a warning.
            return {"CANCELLED"}
        wm.ai_chat_input = ""
        chat.send(context, text)
        return {"FINISHED"}


class AI_CHAT_OT_cancel(bpy.types.Operator):
    bl_idname = "ai_chat.cancel"
    bl_label = "Cancel"
    bl_description = "Stop waiting for the current reply and skip any pending actions"

    @classmethod
    def poll(cls, context):
        return not chat.is_idle()

    def execute(self, context):
        chat.cancel(context)
        return {"FINISHED"}


class AI_CHAT_OT_approve(bpy.types.Operator):
    bl_idname = "ai_chat.approve"
    bl_label = "Approve"
    bl_description = "Let the model do this. Ctrl+Z undoes it"
    # UNDO makes Blender record an undo step after the action runs.
    bl_options = {"UNDO"}

    @classmethod
    def poll(cls, context):
        return chat.state.awaiting is not None

    def execute(self, context):
        chat.approve(context)
        return {"FINISHED"}


class AI_CHAT_OT_deny(bpy.types.Operator):
    bl_idname = "ai_chat.deny"
    bl_label = "Deny"
    bl_description = "Don't do this; the model is told you declined"

    @classmethod
    def poll(cls, context):
        return chat.state.awaiting is not None

    def execute(self, context):
        chat.deny(context)
        return {"FINISHED"}


class AI_CHAT_OT_copy_pending(bpy.types.Operator):
    bl_idname = "ai_chat.copy_pending"
    bl_label = "Copy"
    bl_description = "Copy the proposed code to the clipboard to read it in full"

    @classmethod
    def poll(cls, context):
        return bool(chat.state.awaiting and chat.state.awaiting["arguments"].get("code"))

    def execute(self, context):
        context.window_manager.clipboard = chat.state.awaiting["arguments"]["code"]
        self.report({"INFO"}, "Code copied to clipboard")
        return {"FINISHED"}


class AI_CHAT_OT_clear(bpy.types.Operator):
    bl_idname = "ai_chat.clear"
    bl_label = "Clear Chat"
    bl_description = "Start a new conversation"

    def execute(self, context):
        chat.clear(context)
        return {"FINISHED"}


class AI_CHAT_OT_copy_last(bpy.types.Operator):
    bl_idname = "ai_chat.copy_last"
    bl_label = "Copy Reply"
    bl_description = "Copy the last reply to the clipboard"

    @classmethod
    def poll(cls, context):
        return bool(chat.last_reply())

    def execute(self, context):
        context.window_manager.clipboard = chat.last_reply()
        self.report({"INFO"}, "Reply copied to clipboard")
        return {"FINISHED"}


class AI_CHAT_OT_open_prefs(bpy.types.Operator):
    bl_idname = "ai_chat.open_prefs"
    bl_label = "AI Chat Preferences"
    bl_description = "Open the add-on preferences (API key, model)"

    def execute(self, context):
        bpy.ops.screen.userpref_show(section="ADDONS")
        bpy.ops.preferences.addon_show(module=preferences.ADDON_ID)
        return {"FINISHED"}


class AI_CHAT_OT_refresh_models(bpy.types.Operator):
    bl_idname = "ai_chat.refresh_models"
    bl_label = "Refresh Models"
    bl_description = "Fetch the provider's current model list"

    # (provider_id, items, error) once the background fetch finishes.
    _result = None
    _running = False

    @classmethod
    def poll(cls, context):
        prefs = preferences.get(context)
        return prefs and providers.get(prefs.provider).models_refreshable and not cls._running

    def execute(self, context):
        cls = type(self)
        provider = providers.get(preferences.get(context).provider)
        cls._running = True
        cls._result = None
        preferences.refresh_status = "Fetching model list..."

        def fetch():
            try:
                cls._result = (provider.id, provider.list_models(), None)
            except ProviderError as e:
                cls._result = (provider.id, None, str(e))
            except Exception as e:
                cls._result = (provider.id, None, f"Unexpected error: {type(e).__name__}: {e}")

        def poll_result():
            if cls._result is None:
                return 0.2
            provider_id, items, error = cls._result
            cls._running = False
            if items:
                preferences.live_models[provider_id] = items
                preferences.refresh_status = f"Loaded {len(items)} models"
            else:
                preferences.refresh_status = error or "The provider returned no models"
            for window in bpy.context.window_manager.windows:
                for area in window.screen.areas:
                    area.tag_redraw()
            return None

        threading.Thread(target=fetch, daemon=True).start()
        bpy.app.timers.register(poll_result, first_interval=0.2)
        return {"FINISHED"}


classes = (
    AI_CHAT_OT_refresh_models,
    AI_CHAT_OT_send,
    AI_CHAT_OT_cancel,
    AI_CHAT_OT_approve,
    AI_CHAT_OT_deny,
    AI_CHAT_OT_copy_pending,
    AI_CHAT_OT_clear,
    AI_CHAT_OT_copy_last,
    AI_CHAT_OT_open_prefs,
)
