class_name GameSettings
extends RefCounted
## Player settings beyond name and language: graphics (a preset plus render scale, FSR,
## shadows, ambient occlusion, indirect light, glow, fog, VSync, an FPS cap),
## accessibility (interface size, reduced motion, house symbols beside house colours,
## captions for sounds) and key bindings. Stored in user://settings.cfg next to
## GameSession's own keys; applied at start and whenever changed (SettingsPanel).

const PATH := GameSession.SETTINGS_PATH
const PRESETS := ["low", "medium", "high", "ultra"]
## What each preset sets; individual settings override afterwards.
const PRESET_VALUES := {
	"low": {"render_scale": 0.67, "fsr": true, "shadows": false, "ssao": false, "ssil": false, "glow": false, "fog": false},
	"medium": {"render_scale": 0.85, "fsr": true, "shadows": true, "ssao": false, "ssil": false, "glow": true, "fog": true},
	"high": {"render_scale": 1.0, "fsr": false, "shadows": true, "ssao": true, "ssil": false, "glow": true, "fog": true},
	"ultra": {"render_scale": 1.0, "fsr": false, "shadows": true, "ssao": true, "ssil": true, "glow": true, "fog": true},
}
const DEFAULTS := {
	"preset": "high", "render_scale": 1.0, "fsr": false, "shadows": true, "ssao": true, "ssil": false, "glow": true, "fog": true,
	"vsync": true, "fps_cap": 0,
	"ui_scale": 1.0, "reduce_motion": false, "house_symbols": false, "captions": false,
}
## Actions a player may rebind (the rest stay fixed).
const BINDABLE := ["move_forward", "move_backward", "move_left", "move_right", "jump", "sprint", "interact", "cast", "mount",
	"journal", "emote_menu", "raise_hand", "chat", "map"]
## House symbols shown beside house colours when house_symbols is on.
const HOUSE_SYMBOLS := ["", "▲", "◆", "●", "■"]

static var values: Dictionary = DEFAULTS.duplicate()
static var bindings: Dictionary = {}


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	values = DEFAULTS.duplicate()
	bindings = {}
	if cfg.load(PATH) == OK:
		for k: String in DEFAULTS:
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
		for action: String in BINDABLE:
			if cfg.has_section_key("keys", action):
				bindings[action] = int(cfg.get_value("keys", action))
	apply_bindings()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # keep GameSession's own keys
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	for action: String in bindings:
		cfg.set_value("keys", action, bindings[action])
	cfg.save(PATH)


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
static func bind(action: String, keycode: int) -> void:
	if not BINDABLE.has(action) or not InputMap.has_action(action):
		return
	bindings[action] = keycode
	_apply_binding(action, keycode)
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
	Engine.max_fps = int(get_value("fps_cap"))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(4096 if get_value("shadows") else 256, true)
	for node in tree.root.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		# A setting only turns off what the level has; turning it on gives back the level's own choice.
		if not env.has_meta("level_effects"):
			env.set_meta("level_effects", {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "glow": env.glow_enabled,
				"fog": env.fog_enabled, "vfog": env.volumetric_fog_enabled})
		var own: Dictionary = env.get_meta("level_effects")
		env.ssao_enabled = bool(get_value("ssao"))
		env.ssil_enabled = bool(get_value("ssil"))
		env.glow_enabled = bool(get_value("glow")) and own.glow
		env.fog_enabled = bool(get_value("fog")) and own.fog
		env.volumetric_fog_enabled = bool(get_value("fog")) and own.vfog
	for node in tree.root.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).shadow_enabled = bool(get_value("shadows"))


## A house's name with its symbol when the player asked for symbols beside colours.
static func house_label(house: int, name: String) -> String:
	if bool(get_value("house_symbols")) and house > 0 and house < HOUSE_SYMBOLS.size():
		return "%s %s" % [HOUSE_SYMBOLS[house], name]
	return name
