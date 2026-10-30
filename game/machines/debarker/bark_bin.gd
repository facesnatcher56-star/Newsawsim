extends Area3D

## bark_bin.gd
## The roll-off bark bin at the head of the bark belt. Bark landing in it is collected and
## the heap in the model grows; when the bin is full it is swapped for an empty one.

## Bark pieces a full bin holds (a 16 ft log sheds about 40).
@export var capacity: int = 600
@export var heap_path: NodePath
## Seconds a full bin sits before it is swapped.
@export var swap_delay: float = 20.0

var fill: int = 0
var _heap: Node3D
var _swap_timer: float = -1.0


func _ready() -> void:
	_heap = get_node_or_null(heap_path) as Node3D
	body_entered.connect(_on_body_entered)
	_update_heap()


func _process(delta: float) -> void:
	if _swap_timer >= 0.0:
		_swap_timer -= delta
		if _swap_timer < 0.0:
			fill = 0
			_update_heap()


func is_full() -> bool:
	return fill >= capacity


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("bark_pieces"):
		return
	body.queue_free()
	if fill < capacity:
		fill += 1
		_update_heap()
		if fill >= capacity:
			_swap_timer = swap_delay


func _update_heap() -> void:
	if _heap == null:
		return
	var f := float(fill) / float(capacity)
	_heap.visible = fill > 0
	_heap.scale = Vector3(1.0, maxf(0.02, f), 1.0)
