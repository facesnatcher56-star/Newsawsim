# Board lug incline

Assembly: `game/transport/decks/board_lug_incline.tscn`
Controller and geometry: `game/transport/decks/board_lug_incline.gd`

The machine that takes boards off the edger landing deck and puts them onto the
bin sorter's infeed table. It is built entirely from its exports at runtime, so
the scene only stores the root transform.

## Why it exists

The landing deck's chains carry boards along local +Z and stop at
`world z = 21.647`. The sorter's infeed rails are `7.84 m` further on and
`2.785 m` higher, at `world z = 29.488, y = 3.012`. Boards leave the deck
broadside - long axis across local +X - and that is the attitude the sorter's
infeed expects, so the incline only has to raise them.

## Geometry

Five lug chains run up a straight ramp and over a level crest. The local origin
is the board carrying plane at the bottom tangent, which is exactly where the
landing deck's chain tops end, so the level sits at `(50.803027, 0.2271245,
21.647045)` with no rotation.

| Export | Value | Notes |
| --- | --- | --- |
| `slope_angle_deg` | 26.0 | ramp above horizontal |
| `rise` | 2.785 | 0.2271245 to 3.012 - deck chain tops to sorter rail tops |
| `level_length` | 2.153 | level crest that delivers onto the infeed rails |
| `bed_width` | 5.56 | carries a 16 ft board across five lanes |
| `track_x_positions` | -2.64 ... 2.64 | chain lane centres, 1.32 m apart |
| `floor_y` | -1.54 | where the subframe legs stop |

Both ends are flush joins rather than steps:

- **Foot.** The carrying plane starts at the deck's chain-top height and at the
  exact Z the deck's chain run ends, so a board slides from the deck's chains
  onto this machine's strips without meeting a lip. There is no dead plate
  between the two: a board that had to coast across one would stop, because
  board gravity is 4.5x and a steel-on-wood board stops inside a centimetre.
- **Crest.** The crest's carrying plane is level with the tops of the sorter's
  infeed rails and runs 2.2 cm past where they begin (to `world z = 29.510`), so
  the board is handed over at the height the sorter's scanner zone expects with
  no gap to drop through and no step to climb.

The bed is built as strips with a 0.16 m open channel per chain lane. The
chains sit in those channels with their rollers topping out flush with the
carrying plane, so nothing pokes up into a board and the chains stay visible.

## Lugs and pockets

The lugs are what make this work on a 26 degree ramp. One `AnimatableBody3D`
carries a pusher on all five lanes; stations are spaced `lug_pitch` apart around
the whole chain loop (0.74 m by default, 24 stations here). A board is pushed
uphill by the lug behind it and, whenever the chain stops, slides back onto that
lug - so boards cannot run down into each other, and a stopped chain parks its
load instead of dropping it. Stations on the return run are dropped below the
bed with their collision disabled, and come back into play at the foot.

Boards are not frozen, teleported or relabelled anywhere in the machine: they
ride on friction and are pushed by real moving lugs.

## Controls

- `chain_speed`: 0.45 m/s, deliberately under the sorter's 0.5 m/s infeed so a
  board released at the crest pulls clear of its lug.
- `running`, `external_stop`, `acceleration`, `actual_speed` as on the landing
  deck.
- `sorter_path`: the bin sorter to hand off to. Resolved automatically if left
  empty.
- `upstream_deck_path`: the landing deck. Resolved by name if left empty.
- `hold_zone_length`: depth of the crest zone watched for boards the sorter has
  not accepted yet.

## Handoff and interlocks

The sorter's `InfeedScannerZone` reaches back to `world z = 29.191`, which the
lugs push a board's centre past well before the crest ends, so the sorter freezes
and takes the board while it is still fully supported on the crest. It then
routes it to its bay and drops it; the incline is done with it.

While a board is in the crest zone and `can_accept_board()` says no - the sorter
holds one at a time until it has been dropped - the incline holds its chain and
mirrors the hold into the landing deck's `external_stop`, so boards queue on
their lugs instead of piling into the sorter's infeed.

## Test

```
godot --headless --path . --script res://dev/tests/board_lug_incline_test.gd
```

Success prints `BOARD_LUG_INCLINE_TEST PASS failures=0`. It checks the carrying
plane and both flush joins, one pusher per lane with the return stations out of
the way, a flush surface along ramp and crest, a board held by its lug with the
chains stopped, and then drives a real board in the mill up the ramp, through
the sorter's scanner zone and into bay 19. Validation is geometry and physics
logs, not screenshots.
