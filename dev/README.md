# dev/ - everything that is not the game

Nothing in `game/` depends on this folder. Run any script with
`godot --headless --path . --script res://dev/<folder>/<name>.gd`.

| Folder | Purpose | Pass/fail? |
| --- | --- | --- |
| `tests/` | Regression tests. Each prints `PASS`/`FAIL` or `failures: N`. Run these before committing. | Yes |
| `probes/` | Diagnostics that print measured values (positions, contacts, drive state) to trace a problem. They answer "what is happening?", not "is it correct?". | No (except `full_line_probe`, which reports whether the sorter took the board) |
| `tools/` | Small utilities (`capture_views.gd` and `capture_sorter_bay.gd` take screenshots from set camera angles; need a window, not `--headless`; images go to `dev/captures/`): dump the scene tree, validate resources, one-off debug scripts. They write `*.log` files in the working directory (git-ignored). | No |
| `performance/` | Frame-time recorder and A/B performance probes. Logs go to `performance/logs/` (git-ignored). | No |
| `art/` | Blender/Python scripts that generate the GLB models in `game/assets/models/`. `legacy/` holds superseded generators. | - |
| `notes/` | Dated status and findings documents. Historical: check the date before trusting them. | - |

No screenshot-based validation: use headless physics, position/contact probes and logs.

## tests/

| Script | Covers |
| --- | --- |
| `chain_load_idle_test.gd` | Powered chains start idle, wake for lumber, idle 2 s after empty |
| `mill_enclosure_test.gd` | Machines stand on the slab, clear walls, fit under the roof |
| `test_chain_drive_kinematics.gd` | Sorter chain loop continuity and drive synchronisation |
| `unscrambler_chain_test.gd` | Unscrambler chain rails, width and rotated belt |

The landing deck, board incline and bin sorter no longer have any collision of their own (visuals only), so the tests that checked their old script-built physics were removed. Add tests for the collision boxes placed in the level when they exist.

## probes/

| Script | Traces |
| --- | --- |
| `edger_infeed_handoff_probe.gd` | Initial board from take-away onto the edger infeed |

## Notes

- `notes/CHAIN_IDLE_HANDOFF_CHECKPOINT.md` - load-driven chain idle work and the full-line status.
- `notes/PERFORMANCE_FINDINGS_2026-07-29.md` - render/physics cost findings.
