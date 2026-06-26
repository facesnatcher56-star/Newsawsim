# Codex Project Instructions

- At the start of new sessions in this repository, check whether the Ziva Godot MCP is available by calling `mcp__ziva_godot.get_project_info`.
- If the Ziva MCP check fails or the tool is not exposed, report that to the user before doing Godot project work.
- Prefer Ziva Godot MCP tools for Godot project inspection, documentation lookup, and validated edits when available.
- Do not use screenshot-based validation tools in this project. Avoid Ziva `get_screenshot` and screenshot-backed `playtest`; validate with scene/script inspection, logs, headless loads, and non-visual runtime checks instead.

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
