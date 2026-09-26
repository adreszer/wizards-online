extends Node
## Loads every script and scene in the project (with autoloads present) and
## reports failures. Run:
##   godot --headless --path . tests/check_scripts.tscn

var _failures: int = 0


func _ready() -> void:
	_scan("res://")
	if _failures == 0:
		print("CHECK_OK: all scripts and scenes loaded")
		get_tree().quit(0)
	else:
		print("CHECK_FAILED: %d resources failed to load" % _failures)
		get_tree().quit(1)


func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons":
				_scan(full)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var res := ResourceLoader.load(full)
			if res == null:
				push_error("FAILED to load %s" % full)
				_failures += 1
			elif res is GDScript and not (res as GDScript).can_instantiate() and not (res as GDScript).is_abstract():
				push_error("Script has errors: %s" % full)
				_failures += 1
		entry = dir.get_next()
	dir.list_dir_end()
