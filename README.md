# Sawmill

Godot 4 (Jolt Physics) sawmill simulation. Logs enter at the log feed, are debarked, sawn at the headrig, edged, carried up the lug incline and sorted into bins. Main scene: `game/levels/mill_prototype.tscn`.

| Folder | What lives there |
| --- | --- |
| `game/` | Everything that ships: machines, transport, lumber, environment, level. See [game/README.md](game/README.md). |
| `dev/` | Tests, probes, debug tools, art-generation scripts, performance logs and working notes. See [dev/README.md](dev/README.md). |
| `addons/` | Editor plugins (`godot_mcp`, `global_transform_inspector`; `ziva_agent` is local-only and git-ignored). Not game code. |
| `AGENTS.md` | Instructions for AI coding agents working in this repo. |

## Running

Open `project.godot` in Godot 4, or from a shell:

```bash
godot --path .
```

Headless tests and probes are listed in [dev/README.md](dev/README.md).
