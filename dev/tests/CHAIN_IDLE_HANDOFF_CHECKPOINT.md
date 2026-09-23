# Checkpoint: board unscrambler width and load-driven chain idle

**Status: work in progress, NOT a verified end-to-end fix.** Stop point requested by user. Do not claim the full line works until the final regression below is resolved and retested. No screenshots; use headless physics tests and position/contact probes.

## Changes in this checkpoint

- The mill's `InclineOutfeed/BoardUnscrambler` sets `machine_width = 4.2`, but its chain layout uses 11 rails spanning 5 m. Its five flights extend past the **negative local Z** side plate. `unscrambler_frame_builder.gd` now extends the frame plate, cross members and carrying tray on that side without moving the chain or flight lanes, positive edge, or grooves. `unscrambler_chain_test.gd` verifies the offsets.
- `board_unscrambler.gd` starts parked, uses a contact-height `WorkingSurfaceSensor` to wake on physical cut boards, stops 2 seconds after its surface empties, and synchronizes belt, flights and chain visuals. Velocity now follows the rotated machine's world-space local X. Runtime rebuild frees old generated nodes before adding replacements to avoid name collisions.
- Added `ConveyorLoadSensor` for local carrying-envelope detection. It now projects a BoxShape3D lumber body's half-extents into machine space; this *latest extent change is unverified* (the attempted full-line run was aborted when the user requested a stop).
- `chain_trough_conveyor.gd`, generic `conveyor.gd` (including chain-log-deck instances), `incline_chain_conveyor.gd`, and `chain_deck_visuals.gd` now stop physical drive **and** visual chains when empty, resume for physical loads, and time out after 2 seconds. Existing downstream backpressure still has priority. `edger_landing_deck.gd` similarly wakes for boards and idles when empty. Existing level/simple/incline-log decks already had load-driven idle and were left intact; edger internal infeed already stops without delivery.
- `bin_sorter.gd` separately idles overhead and haul-out chains. Overhead chains index to a repeatable inlet lug gap before parking; otherwise an arbitrary stopped lug can flip the next board. `board_lug_incline.gd` no longer mistakes a board *already tracked by the sorter* for sorter backpressure (the sorter's duplicate-acceptance check rejects it).
- Existing prior-turn board-lug incline idle pickup work and its tests are still uncommitted and included in this checkpoint.

## Headless results **before the final, unverified extent change**

- PASS: `dev/tests/unscrambler_chain_test.gd` (`failures: 0`, includes width, occupancy and rotated belt checks).
- PASS: `dev/tests/chain_load_idle_test.gd` (empty/wake/timeout for mill chain-log deck, trough, incline chain; sorter/unscrambler/landing startup idle).
- PASS: `dev/tests/incline_idle_pickup_test.gd`, `board_lug_incline_test.gd`, `edger_landing_deck_test.gd`, `edger_board_flow_test.gd`, `sorter_physical_board_flow_test.gd`, and `test_chain_drive_kinematics.gd`.
- PASS: `edger_infeed_handoff_probe.gd` reported `touched_feed=true fell_to_floor=false`.
- **FAIL: `full_line_probe.gd`** before the last extent change: the actual mill board arrived on the deck at world X about 50.18 with ~18° yaw, climbed the board-lug incline skewed, and became stuck at incline-local Z about 1.87 (no sorter takeover by frame 2999). The same failure repeated. The controlled `board_lug_incline_test.gd` passes with a freshly placed centred board, so this failure is specifically the full upstream-to-downstream flow. The final extent-aware load detection was intended to wake the landing deck sooner when the *leading end* of a long board physically rests on it but its centre has not yet entered the sensor box. **Its full-line test was aborted, not passed.**

## Resume here

1. Re-run `godot --headless --path . --script res://dev/tests/full_line_probe.gd` once to determine whether the latest extent-aware deck wake corrected the yaw/stall; report the result honestly. Do not use screenshots.
2. If still stuck, compare deck and edger transfer timing, board yaw and contact probes (`pickup_state_probe.gd`, `pickup_contact_probe.gd`) against the earlier working full-line run. Do not weaken safety interlocks merely to pass a test.
3. Re-run `chain_load_idle_test.gd`, `unscrambler_chain_test.gd`, `incline_idle_pickup_test.gd`, `board_lug_incline_test.gd`, `edger_board_flow_test.gd`, `sorter_physical_board_flow_test.gd`, and `test_chain_drive_kinematics.gd` after the extent change. Check for syntax/runtime errors and `git diff --check`.
4. `game/levels/mill_prototype.tscn` also has an unrelated `Ground/Visuals` transform change made in the open editor. It is intentionally **not** part of this checkpoint commit; do not discard the user's working-tree change.
