"""Venice.ai chat completions (OpenAI-style API) over urllib."""

import json
import re

from .base import ChatReply, ChatRequest, Provider
from .http import request_json

API_BASE = "https://api.venice.ai/api/v1"

_STATUS_HINTS = {
    400: "Venice rejected the request",
    401: "The API key was rejected. Check it in the add-on preferences",
    402: "Your Venice balance is too low for this request",
    403: "This API key is not allowed to use that model",
    404: "Model not found. Check the model ID or refresh the model list",
    413: "The conversation is too large. Clear the chat and try again",
    429: "Rate limited. Wait a moment and try again",
    500: "Venice API error. Try again",
    503: "The model is busy or unavailable. Try again shortly",
}

# Some reasoning models put their thinking inline in the reply text.
_THINK_RE = re.compile(r"<think>.*?</think>\s*", re.DOTALL)


class VeniceProvider(Provider):
    id = "venice"
    label = "Venice"
    description = "Venice.ai, including its uncensored models"
    env_var = "VENICE_API_KEY"
    assistant_name = "Venice"
    models_refreshable = True
    # Shortlist shown before the live list is fetched (Preferences > Refresh).
    models = (
        ("venice-uncensored-1-2", "Venice Uncensored 1.2", "Venice's most uncensored model"),
        ("venice-uncensored-role-play", "Venice Role Play Uncensored", "Uncensored, tuned for role play"),
        ("gemma-4-uncensored", "Gemma 4 Uncensored", "Uncensored Gemma 4"),
        ("qwen-3-6-plus", "Qwen 3.6 Plus Uncensored", "Uncensored Qwen, 1M context"),
        ("zai-org-glm-5-2", "GLM 5.2", "Venice's default general model"),
        ("grok-4-7", "Grok 4.7", "Venice's most intelligent model"),
    )

    def send(self, request: ChatRequest) -> ChatReply:
        messages = _to_openai(request.messages)
        if request.system:
            messages.insert(0, {"role": "system", "content": request.system})
        body = {
            "model": request.model,
            "messages": messages,
            "max_completion_tokens": request.max_tokens,
            "venice_parameters": {
                "include_venice_system_prompt": bool(
                    request.options.get("include_venice_system_prompt")
                ),
                "strip_thinking_response": True,
            },
        }
        if request.tools:
            body["tools"] = [
                {"type": "function", "function": {
                    "name": t["name"], "description": t["description"], "parameters": t["parameters"],
                }}
                for t in request.tools
            ]
        payload = request_json(
            f"{API_BASE}/chat/completions",
            service="Venice",
            headers={"Authorization": f"Bearer {request.api_key}"},
            body=body,
            timeout=request.timeout,
            error_message=_http_error_message,
        )
        return _parse_reply(payload)

    def list_models(self, timeout=30.0):
        """Fetch the live text model list (public endpoint, no key needed)."""
        payload = request_json(
            f"{API_BASE}/models?type=text",
            service="Venice",
            timeout=timeout,
            error_message=_http_error_message,
        )
        items = []
        for model in payload.get("data", []):
            spec = model.get("model_spec") or {}
            traits = spec.get("traits") or []
            description = ", ".join(t.replace("_", " ") for t in traits)
            items.append((model["id"], spec.get("name") or model["id"], description))
        return items


def _http_error_message(status, payload):
    message = f"{_STATUS_HINTS.get(status, 'Request failed')} (HTTP {status})"
    error = (payload or {}).get("error")
    detail = error.get("message", "") if isinstance(error, dict) else (error or "")
    return f"{message}: {detail}" if detail else message


def _to_openai(messages):
    out = []
    for message in messages:
        role = message["role"]
        if role == "user":
            out.append({"role": "user", "content": message["content"]})
        elif role == "tool":
            out.append({"role": "tool", "tool_call_id": message["tool_call_id"],
                        "content": message["content"]})
        elif role == "assistant":
            entry = {"role": "assistant", "content": message.get("content") or None}
            calls = message.get("tool_calls") or []
            if calls:
                entry["tool_calls"] = [
                    {"id": c["id"], "type": "function",
                     "function": {"name": c["name"], "arguments": json.dumps(c["arguments"])}}
                    for c in calls
                ]
            out.append(entry)
    return out


def _parse_tool_calls(message):
    calls = []
    for i, call in enumerate(message.get("tool_calls") or []):
        function = call.get("function") or {}
        try:
            arguments = json.loads(function.get("arguments") or "{}")
        except json.JSONDecodeError:
            arguments = None
        if not isinstance(arguments, dict):
            # Passed through so the tool reports the bad input to the model.
            arguments = {"_invalid_arguments": function.get("arguments")}
        calls.append({"id": call.get("id") or f"call_{i}", "name": function.get("name", ""),
                      "arguments": arguments})
    return calls


def _parse_reply(payload):
    choice = (payload.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    text = _THINK_RE.sub("", message.get("content") or "").strip()
    finish = choice.get("finish_reason") or ""
    note = "Reply was cut off at the max tokens limit" if finish == "length" else ""
    usage = payload.get("usage") or {}
    return ChatReply(
        text=text,
        model=payload.get("model", ""),
        stop_reason=finish,
        note=note,
        input_tokens=usage.get("prompt_tokens", 0),
        output_tokens=usage.get("completion_tokens", 0),
        tool_calls=_parse_tool_calls(message),
    )
