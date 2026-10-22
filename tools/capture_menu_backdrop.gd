extends Node
## Dev tool: renders the main menu's backdrop (assets/ui/menu/backdrop.jpg): the real
## World offline at dusk, seen from a camera on the grounds with the HUD, the minimap
## and the player hidden (needs a window; not --headless).
##   godot --path . tools/capture_menu_backdrop.tscn -- [--out=/absolute/file.jpg]
##     [--hours=19.5] [--from=x,y,z] [--at=x,y,z]
## The defaults are the shipped shot; --out elsewhere tries a framing without touching it.

const WORLD := preload("res://core/world.tscn")
const OUT := "res://assets/ui/menu/backdrop.jpg"
const SIZE := Vector2i(1920, 1080)

var _out := OUT
var _hours := 19.5
var _from := Vector3(-120, 7, 165)
var _at := Vector3(-75, 30, 20)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--hours="):
			_hours = float(arg.trim_prefix("--hours="))
		elif arg.begins_with("--from="):
			_from = _vec(arg.trim_prefix("--from="))
		elif arg.begins_with("--at="):
			_at = _vec(arg.trim_prefix("--at="))
	get_window().size = SIZE
	# The best look for this run only; the player's saved settings stay as they are.
	GameSettings.values.merge(GameSettings.PRESET_VALUES["ultra"], true)
	GameSettings.apply(get_tree())
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(30)
	var hud := world.get_node_or_null("HUD")
	if hud != null and hud.has_method("set_shown"):
		hud.set_shown(false)
	for path in ["Minimap", "ChatPanel"]:
		var layer := world.get_node_or_null(path) as CanvasLayer
		if layer != null:
			layer.visible = false
	for cycle in get_tree().root.find_children("*", "DayNightCycle", true, false):
		(cycle as DayNightCycle).time_override = _hours
		(cycle as DayNightCycle).refresh()
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player != null:
		player.visible = false
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = _from
	cam.look_at(_at)
	cam.make_current()
	# Let GI, fog and the streamed set pieces settle.
	await _frames(240)
	var img := get_viewport().get_texture().get_image()
	if _out.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
		img.save_jpg(ProjectSettings.globalize_path(_out), 0.88)
	else:
		img.save_jpg(_out, 0.88)
	print("saved ", _out)
	get_tree().quit()


func _vec(text: String) -> Vector3:
	var p := text.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3.ZERO


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
