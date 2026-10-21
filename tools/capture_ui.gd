extends Node
## Dev tool: saves a PNG of every main UI surface (the UI gallery's pages, main menu, HUD, pause, settings,
## satchel, journal, map, chat, sorting, timetable, character creator and the feature
## panels) so UI work can be compared before and after (needs a window; not --headless).
##   godot --path . tools/capture_ui.tscn -- --out=/absolute/dir [--size=1280x800] [--lang=en] [--scale=1.5]
## --size sets the window, --lang the language, --scale the interface scale, for this run
## only (the player's saved settings are left alone). tools/capture_ui_matrix.sh runs
## every combination the ship check reviews (docs/ui.md, Milestone 72).

const MENU := preload("res://ui/menus/main_menu.tscn")
const GALLERY := preload("res://levels/dev/ui_gallery.tscn")
const GALLERY_PAGES := ["windows", "play", "icons"]
const WORLD := preload("res://core/world.tscn")
const FEATURE_PANELS := ["settings", "friends", "clubs", "profile", "shop", "cauldron", "decor"]

var _out: String = "user://captures/ui"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			if wh.size() == 2:
				get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		elif arg.begins_with("--lang="):
			TranslationServer.set_locale(arg.trim_prefix("--lang="))
		elif arg.begins_with("--scale="):
			GameSettings.values["ui_scale"] = float(arg.trim_prefix("--scale="))
	GameSettings.apply(get_tree())
	DirAccess.make_dir_recursive_absolute(_out)
	await _frames(5)
	await _run()


func _run() -> void:
	var gallery := GALLERY.instantiate()
	add_child(gallery)
	for i in GALLERY_PAGES.size():
		gallery.show_page(i)
		await _frames(20)
		_save("gallery_" + GALLERY_PAGES[i])
	gallery.show_page(3)
	gallery.show_dialog(false)
	await _frames(20)
	_save("gallery_question")
	gallery.show_dialog(true)
	await _frames(20)
	_save("gallery_error")
	gallery.queue_free()
	UiRouter.close_all()
	await _frames(2)
	var menu := MENU.instantiate()
	add_child(menu)
	await _frames(30)
	_save("main_menu")
	menu.queue_free()
	await _frames(2)
	var world := WORLD.instantiate()
	add_child(world)
	await _frames(90)
	_save("hud")
	# The HUD with everything showing at once: hurt, a prompt, toasts, a banner, the houses.
	var hud := world.get_node_or_null("HUD")
	var me := get_tree().get_first_node_in_group("local_player")
	if hud != null and me != null:
		for id in ["arcane_pulse", "emberkindle", "frostbind", "glowmote", "unbolt"]:
			me.spell_caster.learn_spell(load("res://resources/spells/%s.tres" % id))
		me.spell_caster.select_slot(1)
		me.spell_caster.try_cast()
		hud.set_house_totals(PackedInt32Array([120, 95, 140, 60]))
		hud._on_health_changed(62, 100)
		hud._show_prompt("PROMPT_SIT")
		hud.banner.show_area(tr("AREA_LIBRARY"), tr("MAP_FLOOR_GROUND"), 0.0)
		GameEvents.notify(tr("NOTIFY_SPELL_LEARNED") % tr("SPELL_ARCANE_PULSE_NAME"), 30.0, ToastStack.Kind.LEARNED)
		GameEvents.notify(tr("NOTIFY_DOOR_LOCKED"), 30.0, ToastStack.Kind.WARNING, "locked")
		await _frames(30)
		hud._show_prompt("PROMPT_SIT")
		await _frames(2)
		_save("hud_busy")
		hud.toasts.clear()
		hud._on_health_changed(100, 100)
		hud._show_prompt("")
	for path in ["InventoryPanel", "Journal", "MapPanel", "ChatPanel"]:
		var panel := world.get_node_or_null(path)
		if panel == null or not panel.has_method("open"):
			continue
		panel.open()
		await _frames(20)
		_save(path.to_snake_case())
		panel.close()
		await _frames(2)
	GameEvents.timetable_requested.emit()
	await _frames(20)
	_save("timetable")
	_press_escape()
	await _frames(4)
	GameEvents.sorting_requested.emit()
	await _frames(20)
	_save("sorting")
	_press_escape()
	await _frames(4)
	GameEvents.character_creator_requested.emit()
	await _frames(20)
	_save("character_creator")
	_press_escape()
	await _frames(4)
	for p in FEATURE_PANELS:
		GameEvents.panel_requested.emit(p, {"name": "Tester"})
		await _frames(20)
		_save("panel_" + p)
		_press_escape()
		await _frames(4)
	var pause := world.get_node_or_null("PauseMenu")
	if pause != null:
		pause._set_paused(true)
		await _frames(20)
		_save("pause")
	get_tree().quit()


func _press_escape() -> void:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
