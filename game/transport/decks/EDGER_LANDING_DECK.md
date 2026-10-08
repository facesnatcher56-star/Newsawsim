# Edger landing deck

Assembly: `game/transport/decks/edger_landing_deck.tscn` (placed in the mill as `landing_deck_frame`).
Script: `game/transport/decks/edger_landing_deck.gd`

**Visuals only.** The deck is a Blender-built frame with five animated roller chains and two sprocket shafts. The script animates the chains (`chain_speed`, `reverse_direction`, `running`, `acceleration`). It has **no collision**: boards are carried across it by collision boxes placed in the level.

Local +X is the edger entry, local +Z is the carry direction, and the origin is the chain-top plane at the landing lane centre. The deck spans x -3.1 to 3.1 and z -0.65 to 3.35. Keep scale at (1, 1, 1).

Regenerate the model with Blender in background: `--python dev/art/build_edger_landing_deck.py`, then reimport the GLBs in Godot.
