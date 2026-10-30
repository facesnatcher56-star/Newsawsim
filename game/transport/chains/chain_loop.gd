extends RefCounted

## chain_loop.gd
## A roller chain loop in a vertical plane: the carrying run follows a polyline of (u, y) points
## (u = distance along the plane's travel axis, y = height, listed in the direction of travel),
## wraps round a sprocket of radius r under each end, and comes back offset 2r underneath.
## sample(s) gives the point and unit tangent at distance s round the loop, so links, carrier bars
## and lug bodies can be laid along it and moved by advancing s.

var points: PackedVector2Array = PackedVector2Array()
var _cum: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
## Sprocket centres (u, y) at the tail (first point) and head (last point).
var tail_centre := Vector2.ZERO
var head_centre := Vector2.ZERO


static func from_path(path: PackedVector2Array, r: float, arc_steps: int = 10) -> RefCounted:
	var loop = load("res://game/transport/chains/chain_loop.gd").new()
	loop._build(path, r, arc_steps)
	return loop


func _build(path: PackedVector2Array, r: float, arc_steps: int) -> void:
	var n0 := _left(path[0], path[1])
	var n1 := _left(path[path.size() - 2], path[path.size() - 1])
	tail_centre = path[0] - n0 * r
	head_centre = path[path.size() - 1] - n1 * r
	var a1 := atan2(n1.y, n1.x)
	var a0 := atan2(n0.y, n0.x)
	var pts := PackedVector2Array(path)
	# Down round the head sprocket.
	for k in range(1, arc_steps):
		var a := a1 - PI * k / arc_steps
		pts.append(head_centre + Vector2(cos(a), sin(a)) * r)
	# Return run, 2r under the carrying run.
	var ret := _offset(path, -2.0 * r)
	ret.reverse()
	pts.append_array(ret)
	# Up round the tail sprocket.
	for k in range(1, arc_steps):
		var a := a0 - PI - PI * k / arc_steps
		pts.append(tail_centre + Vector2(cos(a), sin(a)) * r)
	points = pts
	_cum.resize(points.size() + 1)
	_cum[0] = 0.0
	for i in points.size():
		_cum[i + 1] = _cum[i] + points[i].distance_to(points[(i + 1) % points.size()])
	length = _cum[points.size()]


## Point and unit tangent at distance s round the loop (s wraps).
func sample(s: float) -> Array:
	s = fposmod(s, length)
	var lo := 0
	var hi := points.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var a := points[lo]
	var b := points[(lo + 1) % points.size()]
	var seg := _cum[lo + 1] - _cum[lo]
	var t := (b - a) / maxf(seg, 0.000001)
	return [a + (b - a) * ((s - _cum[lo]) / maxf(seg, 0.000001)), t]


## Pre-bake MultiMesh buffers for `per` links on each of the strands at xs, at `phases` evenly
## spaced offsets within one link spacing. frame(sample, x) -> Transform3D places one link.
## The chain then animates by assigning baked[phase_index(travel)] to the MultiMesh's buffer.
func bake(per: int, xs: Array, frame: Callable, phases: int = 16) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	var spacing := length / per
	for k in phases:
		var buf := PackedFloat32Array()
		buf.resize(per * xs.size() * 12)
		var j := 0
		for i in per:
			var smp: Array = sample(i * spacing + spacing * k / phases)
			for x in xs:
				var t: Transform3D = frame.call(smp, x)
				var b := t.basis
				buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = t.origin.x
				buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = t.origin.y
				buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = t.origin.z
				j += 12
		out.append(buf)
	return out


## Which baked buffer shows the chain moved on by `travel` (`per` links round the loop).
func phase_index(travel: float, per: int, phases: int = 16) -> int:
	var spacing := length / per
	return int(fposmod(travel, spacing) / spacing * phases) % phases


## Distance along the carrying run (from the tail end of the path) of the path's point i.
func path_distance(i: int) -> float:
	return _cum[i]


static func _left(a: Vector2, b: Vector2) -> Vector2:
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)


static func _offset(path: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in path.size():
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, path.size() - 1)]
		out.append(path[i] + _left(a, b) * d)
	return out
