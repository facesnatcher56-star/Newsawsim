class_name RollSpin
extends RefCounted

## Drawn spin of a live roll, capped per rendered frame. Rolls carry marks a third of a turn
## apart; at fast-forward (or a low frame rate) a roll can turn nearly that far between frames
## and the marks then seem to creep backward (the wagon-wheel effect). Capping each frame's
## step keeps them turning the right way, just slower than true at high speed.
## Call from _process, whose delta is real frame time scaled by Engine.time_scale.

const MAX_STEP := 0.55     # radians per drawn frame, well under half the 2.09 rad mark spacing


## Angle to add this frame for a roll turning at `rate` rad/s.
static func step(rate: float, delta: float) -> float:
	return clampf(rate * delta, -MAX_STEP, MAX_STEP)
