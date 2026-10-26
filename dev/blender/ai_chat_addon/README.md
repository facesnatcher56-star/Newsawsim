# AI Chat (Blender add-on)

Chat with an AI model from the 3D viewport sidebar, using your own API key.
Two providers are built in:

- **Venice** (default): Venice.ai's OpenAI-style API, including its uncensored
  models (Venice Uncensored 1.2 is selected by default).
- **Anthropic**: Claude via the Messages API.

Everything goes through Python's standard library, so nothing gets pip-installed
into Blender's Python. Tested on Blender 5.1.

## Install

Option A: zip and install

1. Zip the `ai_chat` folder (the zip must contain `ai_chat/__init__.py`):
   `Compress-Archive -Path dev/blender/ai_chat_addon/ai_chat -DestinationPath ai_chat.zip`
2. Blender: Edit > Preferences > Add-ons > the drop-down arrow (top right) > Install from Disk..., pick `ai_chat.zip`.
3. Enable "AI Chat".

Option B: copy the `ai_chat` folder into
`%APPDATA%\Blender Foundation\Blender\5.1\scripts\addons\`, restart Blender (or Refresh), and enable "AI Chat".

## Where the API key goes

Edit > Preferences > Add-ons > AI Chat. Pick the **Provider**, then paste the key into
its key field (**Venice API key** or **Anthropic (Claude) API key**). Each provider
keeps its own key. The fields are masked, stored in Blender's user preferences (not
in your .blend files), and never printed or logged. Keep "Auto-Save Preferences" on,
or use Save Preferences, so the key persists.

If a key field is empty, the add-on uses an environment variable instead:
`VENICE_API_KEY` for Venice, `ANTHROPIC_API_KEY` for Anthropic. The preferences show
which source is in use.

## Use

3D Viewport > press N > **AI Chat** tab.

- Type in the message box and press Enter (or the play button) to send. Requests run
  on a background thread, so Blender stays responsive; Cancel stops waiting.
- **Scene Context** sends a short summary (object names, types, locations, selection,
  mode) with each message.
- Copy puts the last reply on the clipboard (handy for Python you want to paste into
  the Text Editor). Trash starts a new conversation.

The conversation is kept in memory only and is not saved with the .blend file.

## Tools: letting the model act in Blender

With **Blender tools** on (Preferences, on by default), the model can call tools:

- **Runs immediately** (read-only): scene info, list objects, object details.
- **Needs your approval**: run Python, select objects, set an object's
  location/rotation/scale, delete objects.

When the model wants to change something, an approval box appears in the panel
showing exactly what it will do (for Python, the code; Copy puts all of it on the
clipboard). **Approve** runs it as one undo step, so Ctrl+Z reverts it; **Deny**
skips it and tells the model you declined. Cancel skips everything still pending.
Approved Python has full access to Blender and your files, so read it first.

The model can chain several tool calls for one message (up to 25 steps). Turn
Blender tools off for plain chat, or if a model returns errors about tools.

## Preferences

- **Model**: each provider has its own model list plus "Custom..." for any model ID.
  For Venice, the refresh button next to the model fetches Venice's full current
  text model list (it changes often). The built-in shortlist is Venice's uncensored
  models plus GLM 5.2 and Grok 4.7.
- **Venice system prompt** (Venice only, off by default): also send Venice's own
  system prompt alongside yours. Off sends `include_venice_system_prompt: false`.
- **Effort** and **Refusal fallback** (Anthropic only).
- Blender tools, max tokens, timeout, system prompt, Send on Enter, chat height.

## Adding another provider

Subclass `providers.base.Provider` in a new module under `ai_chat/providers/`
(`providers/http.py` has a JSON request helper), register an instance in
`providers/__init__.py`, and add `<provider_id>_api_key`, `<provider_id>_model` and
`<provider_id>_custom_model` properties to `AIChatPreferences`.
