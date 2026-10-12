extends SceneTree
## Writes the server's generated content modules (see ServerContentExporter).
##   godot --headless --path . -s tools/export_server_content.gd
## Restart Nakama afterwards to load them.


func _init() -> void:
	var changed := ServerContentExporter.write_all()
	if changed.is_empty():
		print("server content up to date")
	else:
		print("wrote nakama/modules/generated/: ", ", ".join(changed))
	quit(0)
