"""Provider interface shared by every chat backend.

A provider turns a ChatRequest into a ChatReply. It runs on a background
thread, so it must not touch bpy.

Messages use one provider-neutral format, which each provider converts:
    {"role": "user", "content": str}
    {"role": "assistant", "content": str, "tool_calls": [ToolCall dict], "raw": (provider_id, native)}
    {"role": "tool", "tool_call_id": str, "name": str, "content": str, "is_error": bool}
A ToolCall dict is {"id": str, "name": str, "arguments": dict}. "raw" keeps the
provider's own assistant content so it can be replayed unchanged (Claude needs
its thinking blocks back during tool use).
"""

from dataclasses import dataclass, field


class ProviderError(Exception):
    """An error whose message is safe to show in the UI (never contains the key)."""


@dataclass
class ChatRequest:
    api_key: str
    model: str
    system: str
    # Neutral-format messages, oldest first.
    messages: list
    max_tokens: int = 16000
    timeout: float = 600.0
    # [{"name", "description", "parameters": JSON schema}]; empty disables tools.
    tools: list = field(default_factory=list)
    # Provider-specific knobs, e.g. {"effort": "medium"}.
    options: dict = field(default_factory=dict)


@dataclass
class ChatReply:
    text: str
    model: str = ""
    stop_reason: str = ""
    # Extra information for the UI, e.g. "Reply was cut off at max tokens".
    note: str = ""
    input_tokens: int = 0
    output_tokens: int = 0
    tool_calls: list = field(default_factory=list)
    # (provider_id, native assistant content) for replaying this turn.
    raw: object = None


class Provider:
    id = ""
    label = ""
    description = ""
    # Environment variable used when no key is set in the preferences.
    env_var = ""
    # Name shown above replies in the chat view.
    assistant_name = "Assistant"
    # Whether the preferences' Effort setting applies to this provider.
    supports_effort = False
    # Whether list_models() can fetch the live model list.
    models_refreshable = False
    # ((model_id, label, description), ...); the first one is the default.
    models = ()

    def send(self, request: ChatRequest) -> ChatReply:
        raise NotImplementedError

    def list_models(self, timeout=30.0):
        """Return the live model list in the same shape as `models`."""
        raise NotImplementedError
