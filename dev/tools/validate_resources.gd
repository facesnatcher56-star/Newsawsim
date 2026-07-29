extends SceneTree

const ROOTS: PackedStringArray = [
	"res://game",
]

var _checked := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	for root in ROOTS:
		_validate_directory(root)

	if _failures.is_empty():
		print("Resource validation passed: %d files loaded." % _checked)
		quit(0)
		return

	push_error("Resource validation failed for %d file(s):" % _failures.size())
	for failure in _failures:
		push_error("  " + failure)
	quit(1)


func _validate_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_failures.append("%s (directory could not be opened)" % directory_path)
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry == "." or entry == "..":
			entry = directory.get_next()
			continue

		var resource_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_validate_directory(resource_path)
		elif entry.ends_with(".tscn") or entry.ends_with(".gd"):
			_validate_resource(resource_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _validate_resource(resource_path: String) -> void:
	_checked += 1
	var resource := ResourceLoader.load(resource_path)
	if resource == null:
		_failures.append(resource_path)
