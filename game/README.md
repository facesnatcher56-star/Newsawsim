# Game Content Organization

The playable sawmill is assembled in `levels/mill_prototype.tscn`.

## Folder responsibilities

- `assets/`: imported source models and their textures.
- `environment/`: world lighting, cameras, sky, and building shells.
- `levels/`: complete playable level assemblies.
- `lumber/`: logs, boards, slabs, bark, and shared lumber data.
- `machines/`: self-contained production machines and their private builders/components.
- `props/`: passive reusable scene objects.
- `shared/`: small reusable helpers used by multiple features.
- `transport/`: conveyors, decks, roller beds, transfer stations, and transport components.

## Scene boundaries

Create a separate scene when an object has independent behavior, is reused, or benefits from isolated editing. Static geometry can remain together when it is edited and loaded as one unit.

Level scenes should configure scene roots through exported properties. Avoid editing deep children of an instanced machine in the level. If an installation needs structural differences, create a named variant scene beside the base machine and instance that variant in the level.

## Current mill overrides

`mill_prototype.tscn` contains inherited child overrides from the original prototype assembly. They are intentionally preserved during the folder migration so machine placement, collision, and tuning do not change. Convert these to exported root properties or machine variants gradually when each production station is next edited.

## Where each machine lives

The line runs in this order. Each row is a folder under `machines/` or `transport/`; `.tscn` is the instanced scene, `.gd` the controller.

| Stage | Folder | Main files |
| --- | --- | --- |
| Log feed | `machines/log_feed/` | `knuckle_boom_loader`, `log_feed_station` |
| Debarker | `machines/debarker/` | `debarker_station.tscn`, `grip_roller.tscn`, `log_lock_zone.gd` |
| Headrig (sawing) | `machines/headrig/` | `headrig_station.tscn`, `headrig_carriage.gd`, `headrig_rail_system.tscn`, `bandsaw_teeth.gd` |
| Edger | `machines/edger/` | `sawmill_edger.gd` (root), `builders/` (geometry), `components/` (runtime behaviour) |
| Edger landing deck | `transport/decks/` | `edger_landing_deck` - see `EDGER_LANDING_DECK.md` |
| Lug incline | `transport/decks/` | `board_lug_incline` - see `BOARD_LUG_INCLINE.md` |
| Bin sorter | `machines/sorter/` | `bin_sorter.gd` (root), `sorter_chain_system`, `sorter_board_tracker`, `edger_sorter_transfer`, builders |
| Board unscrambler | `machines/unscrambler/` | `board_unscrambler`, `builders/` |

Shared transport pieces:

- `transport/conveyors/` - belt, chain-trough, incline-chain, vibratory and waste conveyors. `builders/` holds the chain-trough geometry builders.
- `transport/decks/` - log decks and board decks. Files ending `_visuals` are visual-only; `_frame_builder` files build static frames.
- `transport/roller_beds/` - roller bed and its sweep chain.
- `transport/stations/` - log transfer station and the incline outfeed assembly.
- `transport/components/` - small reusable behaviours (`conveyor_load_sensor`, `lift_controller`, `rotator`, lock/release zones).

## Naming conventions

- `*_builder.gd` - constructs geometry/nodes at runtime; no per-frame behaviour.
- `*_system.gd` / `components/` - per-frame behaviour split out of a machine root.
- `*_visuals.gd` - rendering only, no collision or physics.
- `ALL_CAPS.md` beside a machine - design notes for that machine.
- `game/assets/models/**/legacy/` - superseded models kept for reference; nothing loads them.
