# Edger landing chain deck

Editable Blender source: `dev/art/edger_landing_deck.blend`.
Reusable Godot assembly: `game/transport/decks/edger_landing_deck.tscn`.
Blender exports: `game/assets/models/edger_landing_deck/`.

## Geometry

Five roller-chain tracks spaced 1.375 m apart across X; 4 m straight chain runs along Z. The receiving span is approximately 6 m, designed around the existing 16 ft boards. Shorter stock needs enough overlap with multiple tracks; change track spacing and rebuild for other stock requirements.

The origin is the chain-top height at the center of the landing lane. Boards enter along local +X. Each 8 mm steel ramp rises 84 mm toward the next chain and ends approximately 6 mm below its top. Ramps occupy only Z = -0.4 to +0.4 m. The remaining chain gaps are open. An additional short ramp leads onto the first chain.

The model includes beveled painted steel framing, anchor feet and bolts, bearings, five complete roller-chain loops, sprockets, common shafts, gearbox, motor and coupling guard. Static geometry is combined by material; 525 moving links use a MultiMesh. Both sprocket shafts rotate with chain travel. No textures or Blender installation are required to run the exported scene in Godot.

## Controls

- `running`: start/stop with acceleration.
- `chain_speed`: target speed in metres per second.
- `reverse_direction`: false carries toward local +Z; true toward local -Z.
- `external_stop`: stop input for a downstream interlock.
- `acceleration`: rate of speed change.
- `actual_speed`: read-only runtime speed for other controllers.

Use unit scale. Rotation is supported. Chains move real rigid bodies through surface friction; the controller does not freeze, teleport, replace or relabel boards. Ramps and frame have separate static collisions. Motion and sprocket rotation stop with the physical conveyor.

The long takeaway side extends to Z = +3.35 m and the near end to Z = -0.65 m. Reversing sends stock toward the near end; arrange a receiver there if using reverse as the delivery direction. No downstream receiver or automatic discharge gate is included.

## Mill placement and integration status

Root position for the current unrotated edger: `(50.803027, 0.2271245, 18.297045)`. Chain tops are 20 mm below the edger output support height. This is provided as `edger_landing_deck_mill_placement.tscn`; `mill_prototype.tscn` instances the deck at that placement as `landing_deck_frame`.

The deck is no longer the end of the line. `game/transport/decks/board_lug_incline.tscn` sits at the deck's discharge (`50.803027, 0.2271245, 21.647045`), starts level with these chain tops at the exact Z they end, and lifts boards to the bin sorter's infeed. The incline holds this deck's `external_stop` whenever it is holding boards for the sorter, so a blocked sorter backs up to the deck instead of piling boards into the infeed. See `BOARD_LUG_INCLINE.md`.

Standalone physical transport, stop, reversal, board identity, rotated transport direction and driven ramp traversal are verified. The edger-to-deck handoff is **still not verified**: `dev/tests/edger_board_flow_test.gd` fails with a board parked at deck local Z = 0.35, speed 0, `_is_board_entering()` true - the chains are held slippery because the board's tail is still over the edger bed at `world x = 47.40` (bed ends at 47.80) and the edger's outfeed has stopped pushing. That failure is unchanged by the downstream incline: it reproduces identically with the incline removed from the mill. Integrating the production line therefore needs coordination with the edger feed/hold-down cycle (or an entry interlock) and a real throughput test. Do not treat the isolated deck tests as proof of a completed production-line handoff.

## Rebuild and test

Run Blender in background with `--python dev/art/build_edger_landing_deck.py` to regenerate source and GLBs. Reimport the GLBs in Godot afterward. Blender source lives under a `.gdignore` directory to avoid a Blender dependency in game imports.

Run Godot headless with `--path . --script dev/tests/edger_landing_deck_test.gd`. Success prints `LANDING_DECK_TEST PASS failures=0`. The ramp probe uses an input force representing continuing edger thrust. Validation uses geometry and physics logs, not screenshots.
