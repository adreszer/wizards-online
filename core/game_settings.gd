class_name GameSettings
extends RefCounted
## Player settings beyond name and language: graphics (a preset plus render scale, FSR,
## shadows, ambient occlusion, indirect light, global illumination, glow, fog, VSync, an
## FPS cap, full screen; the preset also sets how far light shadows reach, see
## LightQuality), sound (a volume per bus), controls (look speed, invert), accessibility
## (interface size, reduced motion, house symbols beside house colours, captions for
## sounds) and key bindings. Stored in user://settings.cfg next to
## GameSession's own keys; applied at start and whenever changed (SettingsPanel).

const PRESETS := ["low", "medium", "high", "ultra"]
## What each preset sets; individual settings override afterwards.
const PRESET_VALUES := {
	"low": {"render_scale": 0.67, "draw_distance": 0.5, "fsr": true, "shadows": false, "ssao": false, "ssil": false, "gi": false, "glow": false, "fog": false},
	"medium": {"render_scale": 0.85, "draw_distance": 0.75, "fsr": true, "shadows": true, "ssao": false, "ssil": false, "gi": false, "glow": true, "fog": true},
	"high": {"render_scale": 1.0, "draw_distance": 1.0, "fsr": false, "shadows": true, "ssao": true, "ssil": false, "gi": true, "glow": true, "fog": true},
	"ultra": {"render_scale": 1.0, "draw_distance": 1.0, "fsr": false, "shadows": true, "ssao": true, "ssil": true, "gi": true, "glow": true, "fog": true},
}
const DEFAULTS := {
	"preset": "high", "render_scale": 1.0, "draw_distance": 1.0, "fsr": false, "shadows": true, "ssao": true, "ssil": false, "gi": true, "glow": true, "fog": true,
	"vsync": true, "fps_cap": 0, "fullscreen": false,
	"vol_master": 1.0, "vol_music": 0.8, "vol_ambience": 0.9, "vol_ui": 0.9,
	"look_sensitivity": 1.0, "invert_y": false,
	"ui_scale": 1.0, "reduce_motion": false, "house_symbols": false, "captions": false,
}
## Volume settings and the audio bus each one sets (default_bus_layout.tres). A volume
## is linear, 0–1, on top of the bus's own level in the layout; 0 mutes the bus.
const VOLUMES := {"vol_master": &"Master", "vol_music": &"Music", "vol_ambience": &"Ambience", "vol_ui": &"UI"}
## Actions a player may rebind (the rest stay fixed).
const BINDABLE := ["move_forward", "move_backward", "move_left", "move_right", "jump", "sprint", "interact", "cast", "mount",
	"journal", "emote_menu", "raise_hand", "chat", "map", "toggle_hud"]
## House symbols shown beside house colours when house_symbols is on.
const HOUSE_SYMBOLS := ["", "▲", "◆", "●", "■"]

## Meta on a DirectionalLight3D that the shadows setting must leave without shadows.
const NO_SHADOWS := &"no_shadows"

static var values: Dictionary = DEFAULTS.duplicate()
static var bindings: Dictionary = {}
## Each bus's own level in the layout (dB), read once before the first volume is applied.
static var _bus_base: Dictionary = {}


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	values = DEFAULTS.duplicate()
	bindings = {}
	if cfg.load(GameSession.settings_path) == OK:
		for k: String in DEFAULTS:
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
		for action: String in BINDABLE:
			if cfg.has_section_key("keys", action):
				bindings[action] = int(cfg.get_value("keys", action))
	apply_bindings()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(GameSession.settings_path)   # keep GameSession's own keys
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	if cfg.has_section("keys"):
		cfg.erase_section("keys")   # a key put back to its default leaves no entry
	for action: String in bindings:
		cfg.set_value("keys", action, bindings[action])
	cfg.save(GameSession.settings_path)


static func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	values[key] = value
	save_settings()


## Picks a preset: its values replace the graphics settings it covers.
static func set_preset(preset: String) -> void:
	if not PRESET_VALUES.has(preset):
		return
	values["preset"] = preset
	for k: String in PRESET_VALUES[preset]:
		values[k] = PRESET_VALUES[preset][k]
	save_settings()


## The key bound to `action` now (its first key event), or 0.
static func key_of(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			return k.physical_keycode if k.physical_keycode != 0 else k.keycode
	return 0


## Binds `action` to `keycode` (physical), replacing its other keys; mouse and pad stay.
## A bindable action that already had the key takes `action`'s old key instead (a
## swap, so no two actions share a key); returns that action, or "".
static func bind(action: String, keycode: int) -> String:
	if not BINDABLE.has(action) or not InputMap.has_action(action):
		return ""
	var old := key_of(action)
	var swapped := ""
	for other: String in BINDABLE:
		if other != action and key_of(other) == keycode and old != 0 and old != keycode:
			bindings[other] = old
			_apply_binding(other, old)
			swapped = other
	bindings[action] = keycode
	_apply_binding(action, keycode)
	save_settings()
	return swapped


## Back to the keys the game ships with.
static func reset_bindings() -> void:
	bindings = {}
	for action: String in BINDABLE:
		InputMap.action_erase_events(action)
		for e in (ProjectSettings.get_setting("input/" + action, {}) as Dictionary).get("events", []):
			InputMap.action_add_event(action, e)
	save_settings()


static func apply_bindings() -> void:
	for action: String in bindings:
		_apply_binding(action, int(bindings[action]))


static func _apply_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	InputMap.action_add_event(action, ev)


## Applies graphics and interface settings to the running game (`tree`: the scene tree).
static func apply(tree: SceneTree) -> void:
	if tree == null:
		return
	var vp := tree.root
	var scale := clampf(float(get_value("render_scale")), 0.5, 1.0)
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if get_value("fsr") and scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.content_scale_factor = clampf(float(get_value("ui_scale")), 0.75, 1.75)
	_update_frames(vp)
	if not vp.has_meta(&"ui_frames_hooked"):
		vp.set_meta(&"ui_frames_hooked", true)
		vp.size_changed.connect(_update_frames.bind(vp))
	Engine.max_fps = int(get_value("fps_cap"))
	apply_volumes()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
		var mode := DisplayServer.window_get_mode()
		var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if full != bool(get_value("fullscreen")):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED)
	RenderingServer.directional_shadow_atlas_set_size(4096 if get_value("shadows") else 256, true)
	# By group name and an untyped call: naming StaticBatch here would close a class cycle.
	for batch: Node in tree.get_nodes_in_group(&"static_batch"):
		batch.call(&"set_draw_distance", float(get_value("draw_distance")))
	for node in tree.root.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		# A setting only turns off what the level has; turning it on gives back the level's own choice.
		if not env.has_meta("level_effects"):
			env.set_meta("level_effects", {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "glow": env.glow_enabled,
				"fog": env.fog_enabled, "vfog": env.volumetric_fog_enabled, "sdfgi": env.sdfgi_enabled})
		var own: Dictionary = env.get_meta("level_effects")
		env.ssao_enabled = bool(get_value("ssao"))
		env.ssil_enabled = bool(get_value("ssil"))
		# SDFGI only where the level asks for it (the castle), never in portrait studios and the like.
		env.sdfgi_enabled = bool(get_value("gi")) and own.get("sdfgi", false)
		env.glow_enabled = bool(get_value("glow")) and own.glow
		env.fog_enabled = bool(get_value("fog")) and own.fog
		env.volumetric_fog_enabled = bool(get_value("fog")) and own.vfog
	for node in tree.root.find_children("*", "DirectionalLight3D", true, false):
		# Fill lights (DayNightCycle's) stand in for sky light and never cast shadows.
		if not node.has_meta(NO_SHADOWS):
			(node as DirectionalLight3D).shadow_enabled = bool(get_value("shadows"))
	LightQuality.shadow_distance = LightQuality.distance_for(str(get_value("preset")), bool(get_value("shadows")))
	LightQuality.watch(tree)


## Sets each bus from its volume setting.
static func apply_volumes() -> void:
	for key: String in VOLUMES:
		var idx := AudioServer.get_bus_index(VOLUMES[key])
		if idx < 0:
			continue
		if not _bus_base.has(key):
			_bus_base[key] = AudioServer.get_bus_volume_db(idx)
		var v := clampf(float(get_value(key)), 0.0, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, float(_bus_base[key]) + linear_to_db(maxf(v, 0.001)))


## Sharp UI frames when the interface is drawn larger than 1:1 (UiFrames).
static func _update_frames(vp: Window) -> void:
	UiFrames.use_density(UiFrames.draw_scale(vp, vp.content_scale_factor))


## A house's name with its symbol when the player asked for symbols beside colours.
static func house_label(house: int, name: String) -> String:
	if bool(get_value("house_symbols")) and house > 0 and house < HOUSE_SYMBOLS.size():
		return "%s %s" % [HOUSE_SYMBOLS[house], name]
	return name
