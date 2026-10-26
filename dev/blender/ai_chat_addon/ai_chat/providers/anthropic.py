"""Anthropic Messages API over urllib (no pip packages needed)."""

from .base import ChatReply, ChatRequest, Provider
from .http import request_json

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"

# Server-side refusal fallback: if the model's safety classifier declines a
# request, the API re-runs it on a fallback model it picks. Only these models
# accept `fallbacks: "default"`.
FALLBACK_BETA = "server-side-fallback-2026-07-01"
FALLBACK_MODELS = {"claude-opus-5-5", "claude-fable-5-1", "claude-sonnet-5-5"}

_STATUS_HINTS = {
    400: "The API rejected the request",
    401: "The API key was rejected. Check it in the add-on preferences",
    403: "This API key is not allowed to use that model or feature",
    404: "Model not found. Check the model ID in the add-on preferences",
    413: "The conversation is too large. Clear the chat and try again",
    429: "Rate limited. Wait a moment and try again",
    500: "Anthropic API error. Try again",
    529: "The API is overloaded. Try again shortly",
}


class AnthropicProvider(Provider):
    id = "anthropic"
    label = "Anthropic (Claude)"
    description = "Claude via the Anthropic Messages API"
    env_var = "ANTHROPIC_API_KEY"
    assistant_name = "Claude"
    supports_effort = True
    models = (
        ("claude-opus-5-5", "Claude Opus 5.5", "Default. Strong all-round model"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5", "Faster and cheaper"),
        ("claude-haiku-5-5", "Claude Haiku 5.5", "Fastest and cheapest"),
        ("claude-fable-5-1", "Claude Fable 5.1", "Most capable, highest price"),
    )

    def send(self, request: ChatRequest) -> ChatReply:
        body = {
            "model": request.model,
            "max_tokens": request.max_tokens,
            "messages": _to_anthropic(request.messages),
        }
        if request.system:
            body["system"] = request.system
        if request.tools:
            body["tools"] = [
                {"name": t["name"], "description": t["description"], "input_schema": t["parameters"]}
                for t in request.tools
            ]
        effort = request.options.get("effort")
        if effort:
            body["output_config"] = {"effort": effort}

        headers = {"x-api-key": request.api_key, "anthropic-version": API_VERSION}
        if request.options.get("refusal_fallback") and request.model in FALLBACK_MODELS:
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = FALLBACK_BETA

        payload = request_json(
            API_URL,
            service="Anthropic",
            headers=headers,
            body=body,
            timeout=request.timeout,
            error_message=_http_error_message,
        )
        return _parse_reply(payload)


def _http_error_message(status, payload):
    message = f"{_STATUS_HINTS.get(status, 'Request failed')} (HTTP {status})"
    detail = ((payload or {}).get("error") or {}).get("message", "")
    return f"{message}: {detail}" if detail else message


def _to_anthropic(messages):
    out = []

    def append(role, blocks):
        # Consecutive same-role entries (tool results, then the user's next
        # message) become one message.
        if out and out[-1]["role"] == role:
            out[-1]["content"].extend(blocks)
        else:
            out.append({"role": role, "content": list(blocks)})

    for message in messages:
        role = message["role"]
        if role == "user":
            append("user", [{"type": "text", "text": message["content"]}])
        elif role == "tool":
            block = {"type": "tool_result", "tool_use_id": message["tool_call_id"],
                     "content": message["content"]}
            if message.get("is_error"):
                block["is_error"] = True
            append("user", [block])
        elif role == "assistant":
            raw = message.get("raw")
            if raw and raw[0] == AnthropicProvider.id:
                append("assistant", raw[1])
                continue
            blocks = [{"type": "text", "text": message["content"]}] if message.get("content") else []
            blocks += [{"type": "tool_use", "id": c["id"], "name": c["name"], "input": c["arguments"]}
                       for c in message.get("tool_calls") or []]
            append("assistant", blocks)
    return out


def _parse_reply(payload):
    content = payload.get("content", [])
    # Thinking blocks come back empty by default; only text blocks are shown.
    text = "\n\n".join(
        block.get("text", "") for block in content if block.get("type") == "text"
    ).strip()
    tool_calls = [
        {"id": block["id"], "name": block["name"], "arguments": block.get("input") or {}}
        for block in content
        if block.get("type") == "tool_use"
    ]
    stop_reason = payload.get("stop_reason") or ""
    note = ""
    if stop_reason == "refusal":
        category = (payload.get("stop_details") or {}).get("category")
        note = "The model declined this request" + (f" ({category})" if category else "")
    elif stop_reason == "max_tokens":
        note = "Reply was cut off at the max tokens limit"
    usage = payload.get("usage") or {}
    return ChatReply(
        text=text,
        model=payload.get("model", ""),
        stop_reason=stop_reason,
        note=note,
        input_tokens=usage.get("input_tokens", 0),
        output_tokens=usage.get("output_tokens", 0),
        tool_calls=tool_calls,
        raw=(AnthropicProvider.id, content),
    )
