class_name DryKiln
extends Node3D

## Double-track, track-through batch dry kiln. Model and layout: dev/blender/dry_kiln/
## kiln_build.py (exported by kiln_export.py). Kiln-local frame: +Z along the tracks (front
## wall at z = 0, green yard at z < 0, rear wall at Z_REAR, dry yard beyond), +X across,
## origin on the floor at the front-left corner.
##
## For now the kiln is a static building: walls and shut doors are solid, the rails are flush
## with the slab. Cart loading, pushing charges through and the door dollies come next.

const MODEL := "res://game/assets/models/dry_kiln/kiln.glb"
const BUILD_W := 8.6832
const WALL_T := 0.20
const Z_REAR := 21.12
const EAVE_Y := 5.80
const DOOR_T := 0.16
const TRACKS: Array[float] = [2.4708, 6.2124]
const YARD_LEN := 20.82


func _ready() -> void:
	add_child(_load_model())
	var body := StaticBody3D.new()
	body.name = "KilnWalls"
	add_child(body)
	# Side walls, and the end walls with their doors shut (a solid face each end).
	_box(body, Vector3(0.0, 0.0, 0.0), Vector3(WALL_T, EAVE_Y, Z_REAR))
	_box(body, Vector3(BUILD_W - WALL_T, 0.0, 0.0), Vector3(BUILD_W, EAVE_Y, Z_REAR))
	_box(body, Vector3(0.0, 0.0, -0.04 - DOOR_T), Vector3(BUILD_W, EAVE_Y, WALL_T))
	_box(body, Vector3(0.0, 0.0, Z_REAR - WALL_T), Vector3(BUILD_W, EAVE_Y, Z_REAR + 0.04 + DOOR_T))


func _box(body: StaticBody3D, p0: Vector3, p1: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = (p1 - p0).abs()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = (p0 + p1) * 0.5
	body.add_child(cs)


## The imported model, or read straight from the .glb when the editor hasn't imported it.
static func _load_model() -> Node3D:
	if ResourceLoader.exists(MODEL):
		return (load(MODEL) as PackedScene).instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(MODEL), state) != OK:
		push_error("DryKiln: can't load " + MODEL)
		return Node3D.new()
	return doc.generate_scene(state) as Node3D
