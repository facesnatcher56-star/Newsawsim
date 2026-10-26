"""Conversation state, background requests, the tool loop and the chat view.

Requests run on a worker thread; results come back through a queue that a
bpy.app.timers callback drains on the main thread, so Blender never blocks.
When the model calls tools, inspection tools run right away; tools that
change things wait for the user's Approve/Deny in the panel. Once every call
in a turn has a result, the results go back to the model in a new request.
The conversation lives only in memory: it is not saved to the .blend file.
"""

import queue
import threading
import time

import blf
import bpy

from . import preferences, providers, scene_summary, tools
from .providers import ChatRequest, ProviderError

POLL_INTERVAL = 0.2
# Model requests allowed per user message before the tool loop is stopped.
MAX_TOOL_ROUNDS = 25

SCENE_CONTEXT = (
    "\n\nBackground: the user's current Blender scene is summarized below. Use it "
    "only when their message is about the scene or needs it. Otherwise ignore it "
    "and just reply to what they said.\n<blender_scene>\n{summary}\n</blender_scene>"
)

TOOLS_NOTE = (
    "\n\nYou have tools to look at and change the user's Blender scene. Looking is "
    "instant. Changes and Python need the user's approval, which they give in the "
    "panel, so when they ask you to do something in Blender, call the tool instead "
    "of describing code for them to run. Only use tools when the user wants "
    "something done or checked in Blender; for normal conversation, just reply."
)


class _State:
    def __init__(self):
        self.history = []  # neutral-format messages (see providers/base.py)
        self.display = []  # (role, text); role in user/assistant/tool/error/info
        self.busy = False
        self.started = 0.0
        # Bumped on cancel/clear so late replies from older requests are dropped.
        self.generation = 0
        self.results = queue.Queue()
        # Tool calls from the latest assistant turn still to run, their results
        # so far, and the call (if any) waiting for Approve/Deny.
        self.pending_calls = []
        self.call_results = []
        self.awaiting = None
        self.awaiting_lines = []  # approval box text, and wrapped to the panel
        self.awaiting_wrapped = []
        self.rounds = 0
        self.wrap_px = 0
        self.rewrap_pending = False


state = _State()


def is_idle():
    return not state.busy and state.awaiting is None


def send(context, text):
    """Start a request for `text`. Returns False (and shows why) if it can't."""
    text = text.strip()
    if not text or not is_idle():
        return False

    state.display.append(("user", text))
    error = _config_error(preferences.get(context))
    if error:
        state.display.append(("error", error))
        refresh(context.window_manager)
        return False

    # History keeps only what the user typed; the scene summary goes into each
    # request's system prompt as background.
    state.history.append({"role": "user", "content": text})
    state.rounds = 0
    _start_request()
    return True


def _config_error(prefs):
    provider = providers.get(prefs.provider)
    api_key, _ = preferences.get_api_key(prefs)
    if not api_key:
        return (
            f"No {provider.label} API key set. Add one in Edit > Preferences > Add-ons > "
            f"AI Chat, or set the {provider.env_var} environment variable, then send again."
        )
    if not api_key.isascii() or not api_key.isprintable() or " " in api_key:
        return "The API key contains invalid characters. Paste it again in the add-on preferences."
    if not preferences.get_model(prefs):
        return "No model ID set. Pick a model in the add-on preferences."
    return None


def _start_request():
    wm = bpy.context.window_manager
    prefs = preferences.get()
    provider = providers.get(prefs.provider)
    api_key, _ = preferences.get_api_key(prefs)

    system = prefs.system_prompt.replace("{version}", bpy.app.version_string)
    if prefs.allow_tools:
        system += TOOLS_NOTE
    if wm.ai_chat_include_scene:
        system += SCENE_CONTEXT.format(summary=scene_summary.build())

    request = ChatRequest(
        api_key=api_key,
        model=preferences.get_model(prefs),
        system=system,
        messages=list(state.history),
        max_tokens=prefs.max_tokens,
        timeout=float(prefs.timeout),
        tools=tools.definitions() if prefs.allow_tools else [],
        options=preferences.get_options(prefs),
    )
    state.busy = True
    state.started = time.monotonic()
    state.generation += 1
    threading.Thread(
        target=_worker, args=(provider, request, state.generation), daemon=True
    ).start()
    if not bpy.app.timers.is_registered(_poll):
        bpy.app.timers.register(_poll, first_interval=POLL_INTERVAL)
    refresh(wm)


def _worker(provider, request, generation):
    try:
        state.results.put((generation, provider.send(request), None))
    except ProviderError as e:
        state.results.put((generation, None, str(e)))
    except Exception as e:  # never let a stray exception kill the thread silently
        message = f"Unexpected error: {type(e).__name__}: {e}".replace(request.api_key, "[key]")
        state.results.put((generation, None, message))


def _poll():
    while True:
        try:
            generation, reply, error = state.results.get_nowait()
        except queue.Empty:
            break
        if generation != state.generation:
            continue
        state.busy = False
        if error:
            _drop_unanswered_user_message()
            state.display.append(("error", error))
        else:
            _handle_reply(reply)
        refresh(bpy.context.window_manager)
    _tag_redraw()  # keeps the elapsed-time label ticking
    return POLL_INTERVAL if state.busy else None


def _handle_reply(reply):
    if not reply.text and not reply.tool_calls:
        _drop_unanswered_user_message()
    else:
        state.history.append({
            "role": "assistant",
            "content": reply.text,
            "tool_calls": reply.tool_calls,
            "raw": reply.raw,
        })
    if reply.text:
        state.display.append(("assistant", reply.text))
    if reply.note:
        state.display.append(("info", reply.note))
    if reply.tool_calls:
        state.pending_calls = list(reply.tool_calls)
        state.call_results = []
        _process_calls()


def _process_calls():
    """Run queued tool calls until one needs approval or all are done."""
    while state.pending_calls:
        call = state.pending_calls[0]
        tool = tools.get(call["name"])
        if tool is None:
            state.pending_calls.pop(0)
            _record_result(call, f"Unknown tool '{call['name']}'", True)
            continue
        if tool.needs_approval:
            state.awaiting = call
            state.awaiting_lines = tool.describe(call["arguments"])
            refresh(bpy.context.window_manager)
            return
        state.pending_calls.pop(0)
        text, is_error = tool.run(bpy.context, call["arguments"])
        _record_result(call, text, is_error)
        state.display.append(("tool", f"{'Failed to ' if is_error else 'Did: '}{tool.label}"))

    state.history.extend(state.call_results)
    state.call_results = []
    state.rounds += 1
    if state.rounds >= MAX_TOOL_ROUNDS:
        state.display.append(("info", f"Stopped after {MAX_TOOL_ROUNDS} tool steps. "
                                      "Send a message to let it continue."))
        refresh(bpy.context.window_manager)
        return
    _start_request()


def _record_result(call, text, is_error):
    state.call_results.append({
        "role": "tool",
        "tool_call_id": call["id"],
        "name": call["name"],
        "content": text,
        "is_error": is_error,
    })


def approve(context):
    """Run the call waiting for approval. Called from an operator with undo."""
    call = state.awaiting
    if call is None:
        return
    tool = tools.get(call["name"])
    state.awaiting = None
    state.pending_calls.pop(0)
    text, is_error = tool.run(context, call["arguments"])
    _record_result(call, text, is_error)
    if is_error:
        state.display.append(("error", f"{tool.label.capitalize()} failed:\n{_preview(text)}"))
    else:
        state.display.append(("tool", f"Approved: {tool.label}\n{_preview(text)}"))
    _process_calls()


def _preview(text, max_lines=12):
    lines = text.splitlines()
    if len(lines) <= max_lines:
        return text
    return "\n".join(lines[:max_lines] + [f"... ({len(lines) - max_lines} more lines)"])


def deny(context):
    call = state.awaiting
    if call is None:
        return
    tool = tools.get(call["name"])
    state.awaiting = None
    state.pending_calls.pop(0)
    _record_result(call, "The user declined this action. Don't retry it unless they ask.", True)
    state.display.append(("info", f"Declined: {tool.label}"))
    _process_calls()


def _drop_unanswered_user_message():
    # Keep the history valid when the first request for a message fails.
    if state.history and state.history[-1]["role"] == "user":
        state.history.pop()


def cancel(context):
    state.generation += 1
    state.busy = False
    if state.awaiting or state.pending_calls:
        # Every tool call needs a result, or the next request is invalid.
        for call in state.pending_calls:
            _record_result(call, "Cancelled by the user.", True)
        state.history.extend(state.call_results)
    else:
        _drop_unanswered_user_message()
    state.pending_calls = []
    state.call_results = []
    state.awaiting = None
    state.display.append(("info", "Cancelled. Any late reply will be ignored."))
    refresh(context.window_manager)


def clear(context):
    state.generation += 1
    state.busy = False
    state.history.clear()
    state.display.clear()
    state.pending_calls = []
    state.call_results = []
    state.awaiting = None
    refresh(context.window_manager)


def awaiting_tool():
    return tools.get(state.awaiting["name"]) if state.awaiting else None


def last_reply():
    for role, text in reversed(state.display):
        if role == "assistant":
            return text
    return ""


def elapsed():
    return time.monotonic() - state.started


# --- Wrapped chat view -----------------------------------------------------

def request_wrap(width_px):
    """Called from panel draw (which can't write data) when the width changes."""
    if width_px != state.wrap_px and not state.rewrap_pending:
        state.wrap_px = width_px
        state.rewrap_pending = True
        bpy.app.timers.register(_rewrap, first_interval=0.0)


def _rewrap():
    state.rewrap_pending = False
    refresh(bpy.context.window_manager)
    return None


def refresh(wm):
    """Rebuild the wrapped line list shown in the panel and scroll to the end."""
    prefs = preferences.get()
    name = providers.get(prefs.provider).assistant_name if prefs else "Assistant"
    labels = {"user": "You", "assistant": name, "tool": "Blender", "error": "Error", "info": "Note"}
    measure = _text_measure()
    max_px = max(state.wrap_px or 250, 80)

    lines = wm.ai_chat_lines
    lines.clear()
    for role, text in state.display:
        _add_line(lines, role, labels[role], header=True)
        for line in wrap(text, max_px, measure):
            _add_line(lines, role, line)
    wm.ai_chat_line_index = len(lines) - 1

    state.awaiting_wrapped = []
    if state.awaiting:
        for text in state.awaiting_lines:
            state.awaiting_wrapped += wrap(text, max_px, measure)
    _tag_redraw()


def _add_line(lines, role, text, header=False):
    item = lines.add()
    item.role = role
    item.text = text
    item.header = header


def _text_measure():
    """Return a function giving the pixel width of a string in the UI font."""
    prefs = bpy.context.preferences
    blf.size(0, prefs.ui_styles[0].widget.points * prefs.system.ui_scale)
    return lambda s: blf.dimensions(0, s)[0]


def wrap(text, max_px, measure):
    out = []
    for paragraph in text.replace("\t", "    ").splitlines():
        if not paragraph.strip():
            out.append("")
            continue
        indent = paragraph[: len(paragraph) - len(paragraph.lstrip())]
        line = ""
        for word in paragraph.split():
            candidate = f"{line} {word}" if line else indent + word
            if measure(candidate) <= max_px:
                line = candidate
                continue
            if line:
                out.append(line)
            line = indent + word
            # A single word wider than the panel (URLs, long identifiers).
            while measure(line) > max_px and len(line) > len(indent) + 1:
                cut = len(line) - 1
                while cut > len(indent) + 1 and measure(line[:cut]) > max_px:
                    cut -= 1
                out.append(line[:cut])
                line = indent + line[cut:]
        out.append(line)
    return out


def _tag_redraw():
    wm = bpy.context.window_manager
    if wm is None:
        return
    for window in wm.windows:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                area.tag_redraw()


def unregister():
    state.generation += 1
    state.busy = False
    for fn in (_poll, _rewrap):
        if bpy.app.timers.is_registered(fn):
            bpy.app.timers.unregister(fn)
