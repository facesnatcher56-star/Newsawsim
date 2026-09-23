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

Four lug chains run up a straight ramp and over a level crest. They are centered
midway between the landing deck's five chain lanes, so the two separate machines'
roller chains straddle each other instead of overlapping at the transfer.

The local origin is the deck-end crossing on the board carrying plane at
`(50.803027, 0.2271245, 21.647045)`. The actual lower tangent is 0.80 m behind
that point and 0.39 m lower, beneath the landing deck. Incline lugs climb through
four 0.24 m-wide slots in the deck's segmented discharge cross member, collect a
board while it is still supported by the deck chains, and then emerge onto the
exposed ramp.

| Export | Value | Notes |
| --- | --- | --- |
| `slope_angle_deg` | 26.0 | ramp above horizontal |
| `rise` | 2.785 | 0.2271245 to 3.012 - deck chain tops to sorter rail tops |
| `level_length` | 2.153 | level crest that delivers onto the infeed rails |
| `bed_width` | 5.56 | carries a 16 ft board across four incline lanes |
| `track_x_positions` | -2.0625, -0.6875, 0.6875, 2.0625 | midway between deck chains |
| `pickup_overlap` | 0.80 | recessed carrying run beneath the deck |
| `floor_y` | -1.54 | where the subframe legs stop |

Both ends are flush joins rather than steps:

- **Pickup.** The inclined carrying run starts beneath the final 0.80 m of the
  landing deck. Its four lanes occupy the gaps between the deck's five lanes.
  Matching openings split the deck's end cross member so each lug can rise from
  below, catch the waiting board on the deck, and push it across the deck-end
  crossing without either chain loop touching the other.
- **Crest.** The crest's carrying plane is level with the tops of the sorter's
  infeed rails and runs 2.2 cm past where they begin (to `world z = 29.510`), so
  the board is handed over at the height the sorter's scanner zone expects with
  no gap to drop through and no step to climb.

The bed is built as strips with a 0.16 m open channel per chain lane. The
chains sit in those channels with their rollers topping out flush with the
carrying plane, so nothing pokes up into a board and the chains stay visible.

## Lugs and pockets

The lugs are what make this work on a 26 degree ramp. One `AnimatableBody3D`
carries a pusher on all four incline lanes; the station count is capped so the
actual pocket pitch (about 1.02 m) exceeds the clearance corridor at the pickup.
A board is pushed uphill by the lug behind it and, whenever the chain stops,
slides back onto that lug - so boards cannot run down into each other, and a
stopped chain parks its load instead of dropping it.

Each lane is now a closed articulated roller chain: rollers are the joint pins,
and alternating inner/outer side-plate pairs bridge from each pin to the next
with overlap at both ends. Its 81 links per lane wrap both sprockets with no doubled seam
or disconnected plate gaps. The unloaded lower strand follows a catenary with
`return_sag = 0.42 m` rather than being stretched tight against the bed. Lugs
remain visibly bolted to that same path around the sprockets and along the sag;
their collision is disabled off the carrying run and re-enabled at the foot.

Boards are not frozen, teleported or relabelled anywhere in the machine: they
ride on friction and are pushed by real moving lugs.

## Controls

- `chain_speed`: adjustable 0–3 m/s magnitude; 0.45 m/s by default, deliberately
  under the sorter's 0.5 m/s infeed so a board released at the crest pulls clear.
- `reverse_direction`: reverses links, lugs, shafts and sprockets through the same
  closed path. Direction changes accelerate smoothly through zero.
- `return_sag`: adjusts the natural slack in the unloaded lower strand.
- `running`, `external_stop`, `acceleration`, `actual_speed` as on the landing
  deck. `actual_speed` is signed, so it is negative while reversing.
- `sorter_path`: the bin sorter to hand off to. Resolved automatically if left
  empty.
- `upstream_deck_path`: the landing deck. Resolved by name if left empty.
- `hold_zone_length`: depth of the crest zone watched for boards the sorter has
  not accepted yet.

## Handoff and interlocks

When empty, the incline is **already stopped at its pickup index**: its next
lug sits below the deck's carrying plane, and the following lug is beyond the
pickup corridor. The landing deck keeps running and feeds a board to the
handoff position without waiting for the incline to phase itself. Once the
board's trailing edge has advanced far enough for a lug to push its full face,
the incline starts and the deck relinquishes its grip. After the last board
leaves the crest, the incline indexes to the same clear pickup position and
parks again. A board arriving unexpectedly during that indexing can still
trigger the safety hold; sorter backpressure continues to hold both machines.
Manual reverse bypasses automatic idle parking.

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
godot --headless --path . --script res://dev/tests/incline_idle_pickup_test.gd
```

Success prints `BOARD_LUG_INCLINE_TEST PASS failures=0`. It checks the carrying
plane and both flush joins, closed roller-link coverage, lower-return sag, lugs
following that return, forward/reverse drive, a flush surface along ramp and
crest, a board held by its lug with the chains stopped, and then drives a real
board in the mill up the ramp, through the sorter's scanner zone and into bay 19.
Validation is geometry and physics logs, not screenshots.
