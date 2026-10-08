# Board lug incline

Assembly: `game/transport/decks/board_lug_incline.tscn`
Script: `game/transport/decks/board_lug_incline.gd`

**Visuals only.** The incline draws its ramp, crest, side rails, hold-down skids, legs, roller chains and lugs from its exports, and animates the chain (`chain_speed`, `reverse_direction`, `running`). It has **no collision**: boards are carried up the ramp by collision boxes placed in the level.

Local origin is the deck-end crossing on the board carrying plane (world 50.803, 0.227, 21.647 in the mill). +Z is uphill, +X is across the boards. Ramp angle 26 degrees, rise 2.785 m, level crest 2.153 m, bed width 5.56 m. Keep the node scale at (1, 1, 1).
