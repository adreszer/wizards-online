extends Node
## Writes the server's generated content modules (see ServerContentExporter).
##   godot --headless --path . tools/export_server_content.tscn
## Runs as a scene, not with -s, so autoloads exist and every object script in
## the castle compiles. Restart Nakama afterwards to load the modules.


func _ready() -> void:
	var changed := ServerContentExporter.write_all()
	if changed.is_empty():
		print("server content up to date")
	else:
		print("wrote nakama/modules/generated/: ", ", ".join(changed))
	get_tree().quit(0)
