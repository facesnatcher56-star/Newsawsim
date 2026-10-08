# dev/ - everything that is not the game

Nothing in `game/` depends on this folder. Run any script with
`godot --headless --path . --script res://dev/<folder>/<name>.gd`.

| Folder | Purpose | Pass/fail? |
| --- | --- | --- |
| `tests/` | Regression tests. Each prints `PASS`/`FAIL` or `failures: N`. Run these before committing. | Yes |
| `probes/` | Diagnostics that print measured values (positions, contacts, drive state) to trace a problem. They answer "what is happening?", not "is it correct?". | No (except `full_line_probe`, which reports whether the sorter took the board) |
| `tools/` | Small utilities: dump the scene tree, validate resources, one-off debug scripts. They write `*.log` files in the working directory (git-ignored). | No |
| `performance/` | Frame-time recorder and A/B performance probes. Logs go to `performance/logs/` (git-ignored). | No |
| `art/` | Blender/Python scripts that generate the GLB models in `game/assets/models/`. `legacy/` holds superseded generators. | - |
| `notes/` | Dated status and findings documents. Historical: check the date before trusting them. | - |

No screenshot-based validation: use headless physics, position/contact probes and logs.

## tests/

| Script | Covers |
| --- | --- |
| `board_lug_incline_test.gd` | Lug incline lifts a board from landing deck to sorter infeed |
| `chain_load_idle_test.gd` | Every powered chain starts idle, wakes for lumber, idles 2 s after empty |
| `edger_board_flow_test.gd` | Board leaves the edger and reaches the landing deck |
| `edger_landing_deck_test.gd` | Landing deck transport, stop, reversal, ramp traversal |
| `edger_sorter_integration_test.gd` | Edger line to bin sorter hand-over |
| `incline_idle_pickup_test.gd` | Incline parks its pickup before a board arrives |
| `mill_enclosure_test.gd` | Machines stand on the slab, clear walls, fit under the roof |
| `sorter_physical_board_flow_test.gd` | Rigid boards through overhead sorter and into the cradle |
| `test_chain_drive_kinematics.gd` | Sorter chain loop continuity and drive synchronisation |
| `unscrambler_chain_test.gd` | Unscrambler chain rails, width and rotated belt |
| `verify_sorter_clearance.gd` | 16 ft board clears all 50-bay sorter motion paths |

## probes/

| Script | Traces |
| --- | --- |
| `full_line_probe.gd` | One board: edger outfeed -> landing deck -> incline -> sorter |
| `edger_infeed_handoff_probe.gd` | Initial board from take-away onto the edger infeed |
| `edger_transfer_probe.gd`, `edger_transfer_contacts.gd`, `edger_transfer_variants.gd` | Edger -> landing deck transfer: motion, contact points, controlled variants |
| `pickup_probe.gd`, `pickup_contact_probe.gd`, `pickup_state_probe.gd` | Deck -> incline hand-over: attitude, solver contacts, interlock flags |
| `deck_drive_diagnosis.gd` | Drive state of both machines when a board stalls on the landing deck |

## Notes

- `notes/CHAIN_IDLE_HANDOFF_CHECKPOINT.md` - load-driven chain idle work and the full-line status.
- `notes/PERFORMANCE_FINDINGS_2026-07-29.md` - render/physics cost findings.
