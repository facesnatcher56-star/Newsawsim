"""Add-on preferences: provider, API keys, models and request options.

Preferences live in Blender's user preferences (userpref.blend), never in the
scene .blend file. Key fields are PASSWORD-style and are never printed.
"""

import os
import zlib

import bpy
from bpy.props import BoolProperty, EnumProperty, IntProperty, StringProperty

from . import providers

ADDON_ID = __package__

DEFAULT_SYSTEM_PROMPT = (
    "You are chatting with the user in a side panel inside Blender {version}. "
    "Talk naturally and reply to what they actually say: casual messages get a "
    "short, casual reply, and questions get a direct answer. Help with Blender "
    "when they ask. Write plain text, since the panel cannot render Markdown. "
    "When you give Python, target the Blender {version} bpy API."
)

EFFORT_ITEMS = [
    ("NONE", "Model default", "Don't send an effort level"),
    ("low", "Low", "Fastest, fewest tokens"),
    ("medium", "Medium", "Balanced"),
    ("high", "High", "More thorough"),
    ("xhigh", "Extra high", "Very thorough"),
    ("max", "Max", "Most thorough, most tokens"),
]

CUSTOM_MODEL = "CUSTOM"

# Live model lists fetched with "Refresh", by provider id, and the last
# refresh's outcome for the preferences page.
live_models = {}
refresh_status = ""
# Every enum item list handed to Blender stays referenced here, so Blender
# never reads freed strings after a refresh replaces a list.
_model_items_cache = {}


def _model_items_for(provider_id):
    def items(self, context):
        provider = providers.get(provider_id)
        models = live_models.get(provider_id) or provider.models
        key = (provider_id, id(models))
        if key not in _model_items_cache:
            _model_items_cache[key] = [
                (model_id, label, description, _enum_value(model_id))
                for model_id, label, description in models
            ] + [(CUSTOM_MODEL, "Custom...", "Type any model ID", 1)]
        return _model_items_cache[key]

    return items


def _enum_value(model_id):
    # A hash of the model ID, so the selection survives a refresh that
    # reorders the list.
    return zlib.crc32(model_id.encode()) & 0x7FFFFFFF


def _model_property(provider_id):
    return EnumProperty(
        name="Model",
        items=_model_items_for(provider_id),
        default=_enum_value(providers.get(provider_id).models[0][0]),
    )


def _key_property(provider_id):
    provider = providers.get(provider_id)
    return StringProperty(
        name=f"{provider.label} API key",
        description=f"Stored in Blender user preferences. "
        f"If empty, the {provider.env_var} environment variable is used",
        subtype="PASSWORD",
    )


class AIChatPreferences(bpy.types.AddonPreferences):
    bl_idname = ADDON_ID

    provider: EnumProperty(name="Provider", items=providers.PROVIDER_ITEMS)

    venice_api_key: _key_property("venice")
    venice_model: _model_property("venice")
    venice_custom_model: StringProperty(name="Model ID", description="Model ID sent to the API")
    venice_system_prompt: BoolProperty(
        name="Venice system prompt",
        description="Also include Venice's own system prompt alongside the one below",
        default=False,
    )

    anthropic_api_key: _key_property("anthropic")
    anthropic_model: _model_property("anthropic")
    anthropic_custom_model: StringProperty(name="Model ID", description="Model ID sent to the API")
    effort: EnumProperty(
        name="Effort",
        description="How much the model thinks before answering",
        items=EFFORT_ITEMS,
        default="medium",
    )
    refusal_fallback: BoolProperty(
        name="Refusal fallback",
        description="If the model declines a request, let the API retry it on a "
        "fallback model (supported models only)",
        default=True,
    )

    max_tokens: IntProperty(name="Max tokens", default=16000, min=256, max=64000)
    timeout: IntProperty(name="Timeout (s)", default=600, min=10, max=3600)
    system_prompt: StringProperty(
        name="System prompt",
        description="{version} is replaced with the Blender version",
        default=DEFAULT_SYSTEM_PROMPT,
    )
    allow_tools: BoolProperty(
        name="Blender tools",
        description="Let the model look at the scene, and (after you approve each one) "
        "change objects or run Python. Turn off for chat only, or for models "
        "without tool support",
        default=True,
    )
    send_on_enter: BoolProperty(
        name="Send on Enter",
        description="Send the message when you confirm the text field",
        default=True,
    )
    chat_rows: IntProperty(name="Chat rows", default=14, min=4, max=60)

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        provider = providers.get(self.provider)

        col = layout.column(heading="Connection")
        col.prop(self, "provider")
        col.prop(self, f"{provider.id}_api_key")
        _, source = get_api_key(self)
        status = {
            "preferences": "Using the key above",
            "environment": f"Using the {provider.env_var} environment variable",
            None: f"No key. Paste one above or set {provider.env_var}",
        }[source]
        row = col.row()
        row.alert = source is None
        row.label(text=status, icon="CHECKMARK" if source else "ERROR")

        col = layout.column(heading="Model")
        row = col.row(align=True)
        row.prop(self, f"{provider.id}_model")
        if provider.models_refreshable:
            row.operator("ai_chat.refresh_models", text="", icon="FILE_REFRESH")
            if refresh_status:
                col.label(text=refresh_status, icon="INFO")
        if getattr(self, f"{provider.id}_model") == CUSTOM_MODEL:
            col.prop(self, f"{provider.id}_custom_model")
        if provider.supports_effort:
            col.prop(self, "effort")
        if provider.id == "anthropic":
            col.prop(self, "refusal_fallback")
        if provider.id == "venice":
            col.prop(self, "venice_system_prompt")
        col.prop(self, "max_tokens")
        col.prop(self, "timeout")
        col.prop(self, "system_prompt")

        col = layout.column(heading="Panel")
        col.prop(self, "allow_tools")
        col.prop(self, "send_on_enter")
        col.prop(self, "chat_rows")


def get(context=None):
    context = context or bpy.context
    addon = context.preferences.addons.get(ADDON_ID)
    return addon.preferences if addon else None


def get_api_key(prefs):
    """Return (key, source) where source is "preferences", "environment" or None."""
    provider = providers.get(prefs.provider)
    key = getattr(prefs, f"{provider.id}_api_key", "").strip()
    if key:
        return key, "preferences"
    key = os.environ.get(provider.env_var, "").strip()
    if key:
        return key, "environment"
    return "", None


def get_model(prefs):
    provider_id = providers.get(prefs.provider).id
    model = getattr(prefs, f"{provider_id}_model")
    if model == CUSTOM_MODEL:
        return getattr(prefs, f"{provider_id}_custom_model").strip()
    return model


def get_options(prefs):
    """Provider-specific request options for ChatRequest.options."""
    provider = providers.get(prefs.provider)
    if provider.id == "anthropic":
        return {
            "effort": None if prefs.effort == "NONE" else prefs.effort,
            "refusal_fallback": prefs.refusal_fallback,
        }
    if provider.id == "venice":
        return {"include_venice_system_prompt": prefs.venice_system_prompt}
    return {}
