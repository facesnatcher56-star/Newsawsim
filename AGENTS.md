# Codex Project Instructions

- At the start of new sessions in this repository, check whether the Ziva Godot MCP is available by calling `mcp__ziva_godot.get_project_info`.
- If the Ziva MCP check fails or the tool is not exposed, report that to the user before doing Godot project work.
- Prefer Ziva Godot MCP tools for Godot project inspection, documentation lookup, and validated edits when available.
- Screenshot-based validation works (confirmed 2026-10-21 on Windows): Ziva `get_screenshot` and `run_scene` (formerly `playtest`) may be used to check visual results. If one fails, don't retry repeatedly — fall back to scene/script inspection, logs, headless loads, and non-visual runtime checks.
- Agents may use any tools the work needs, including Blender. Use MCP tools whenever possible: Ziva for Godot, the `blender` MCP for Blender.

## MCP Tools: Godot + Blender

Two MCP servers are set up for this project. Tools are often *deferred*: if only their names are listed, load them first (Claude Code: `ToolSearch` with query `ziva` or `blender`) before deciding a tool is unavailable.

### Godot (Ziva, `mcp__ziva-godot__*`)

- Runs inside the open Godot editor (Godot 4.8-dev2, project "Sawmill Sim", main scene `res://game/levels/mill_prototype.tscn`).
- Start every session with `get_project_info` to confirm the connection.
- Inspect: `get_scene_tree`, `read`, `glob`, `grep_code`, `get_godot_errors`, `get_node_warnings`, `search_docs`.
- Edit: `edit_file`, `create_file`, `move_node`, `duplicate_node`, `add_resource`, `update_project_setting` (the only safe way to change `project.godot`).
- Run/verify: `run_scene` (live run + screenshot + console), `get_screenshot`, `run_tests`, `execute_script` (headless GDScript).
- Edit `.gd` scripts that are open in the editor through Ziva `edit_file`, not by writing the file on disk: the editor overwrites disk edits with its in-memory copy.

### Blender (`mcp__blender__*`)

- Official Blender Lab MCP (v1.0.3) for Blender 5.1 (`C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`).
- Server: `C:\Users\lloyd\tools\blender_mcp\.venv\Scripts\blender-mcp.exe`, registered as `blender` in `.mcp.json`. Source checkout: `C:\Users\lloyd\tools\blender_mcp`.
- Requires Blender open with the "MCP" add-on enabled (Preferences > Add-ons, auto-start on). It listens on `localhost:9876`. If the tools error with a connection failure, ask the user to open Blender; check with PowerShell `Get-NetTCPConnection -LocalPort 9876 -State Listen`.
- Inspect: `get_objects_summary`, `get_object_detail_summary`, `get_blendfile_summary_*`, `get_screenshot_of_window_as_json`.
- Visual check: `get_screenshot_of_area_as_image` (e.g. `VIEW_3D`), `get_screenshot_of_window_as_image`, `render_viewport_to_path`.
- Docs: `search_api_docs`, `search_manual_docs`, `get_python_api_docs`.
- Do work: `execute_blender_code` (bpy in the live Blender; assign a JSON-serialisable dict to `result`). The `*_for_cli` variants open a `.blend` in a background Blender instead.
- This executes code with no sandbox; inspect the scene first and don't destructively change objects without confirmation.

### Asset workflow

Model in Blender, export `.glb` into `game/assets/models/` (subfolders per machine, e.g. `bin_sorter/`, `edger_landing_deck/`), then place and verify it in Godot via Ziva (`get_scene_tree`, `run_scene`).

## Ziva MCP Recovery Note

If only `mcp__ziva_godot.start_godot` is exposed, or `start_godot` reports that Godot launched but the Ziva sidecar never came up on `http://localhost:7012/api/mcp`, check for stale listeners first:

```bash
ss -ltnp
```

Known healthy listeners are:

- `godot-bin` on `127.0.0.1:9223`
- Godot MCP addon on `127.0.0.1:6550`
- `zivacode` on `*:7012`

If those ports are held by stale `godot-bin`/`zivacode` processes and Codex still cannot see Ziva tools, kill only those stale PIDs, then launch Godot explicitly against this project:

```bash
/home/deck/.local/bin/godot-flatpak --editor --path /home/deck/new-game-project
```

Do not rely on `mcp__ziva_godot.start_godot` alone when recovering this state; it can launch Godot without loading this project/plugin, leaving the Ziva sidecar absent. After the explicit launch, confirm the latest Ziva log says `MCP server initialized`, `MCP server ready at http://localhost:7012/api/mcp`, and `GodotBridgeClient ... Connected`.

If the Ziva panel inside Godot says `Failed to read MCP server status: Internal server error`, check the Ziva logs for:

```text
ETXTBSY: text file is busy, copyfile .../ziva/zivacode/linux_x86_64/zivacode -> .../data/ziva-local/bin/zivacode
```

That means the Codex-side MCP bridge is currently running from `.../data/ziva-local/bin/zivacode` while Ziva's UI status/client setup RPC is trying to update the same binary. The MCP runtime can still be healthy in this state, but Ziva's UI status call fails. The clean recovery is to stop the Codex MCP bridge process using that binary, let Ziva perform its client/status setup, then start a fresh Codex session so it loads the updated bridge and advertises the full tool list.

## Imported Claude Cowork project instructions
