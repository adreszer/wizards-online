extends Node
## Session-scoped state. Autoload: `GameSession`.
##
## Holds the few values that must survive scene swaps and are read by many
## systems: play mode, local display name, language, collectible counters,
## and the "UI has the keyboard" flag. It deliberately contains no gameplay logic.

enum PlayMode { OFFLINE, ONLINE }

const SETTINGS_PATH := "user://settings.cfg"
const MAX_DISPLAY_NAME_LENGTH := 16

var play_mode: PlayMode = PlayMode.OFFLINE
## Empty until settings are loaded; then the saved name or the localized default.
var display_name: String = ""
## Localization.AUTO, "pl" or "en"; persisted. The effective locale is
## TranslationServer.get_locale().
var language: String = Localization.AUTO
## Body used for the local player (see CharacterRegistry). Sent as join metadata online.
var character_id: String = CharacterRegistry.DEFAULT
var nakama_host: String = ProjectSettings.get_setting("game/network/host", "127.0.0.1")
var nakama_port: int = int(ProjectSettings.get_setting("game/network/port", 7350))

## collectible_id -> collected count
var _collected: Dictionary = {}
## collectible_id -> total available in current level
var _totals: Dictionary = {}
## collected instance keys so a collectible is never counted twice
var _collected_keys: Dictionary = {}

var ui_input_captured: bool = false:
	set(value):
		if ui_input_captured == value:
			return
		ui_input_captured = value
		GameEvents.ui_input_capture_changed.emit(value)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_apply_command_line_overrides()
	Localization.apply(language)
	if display_name.is_empty():
		display_name = sanitize_display_name(display_name)


func is_online() -> bool:
	return play_mode == PlayMode.ONLINE


## Keeps ASCII letters/digits, space, "_", "-" and Latin letters with
## diacritics (Latin-1 Supplement + Latin Extended-A/B: Polish, German, Czech…).
## Mirrors sanitize_name in nakama/modules/world_match.lua.
func sanitize_display_name(raw: String) -> String:
	var cleaned := raw.strip_edges()
	var out := ""
	for ch in cleaned:
		if _is_name_char(ch.unicode_at(0)):
			out += ch
	out = out.substr(0, MAX_DISPLAY_NAME_LENGTH).strip_edges()
	if out.is_empty():
		out = tr("PLAYER_DEFAULT_NAME")
	return out


static func _is_name_char(code: int) -> bool:
	if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
		return true
	if code == 32 or code == 95 or code == 45:
		return true
	# Latin-1 Supplement letters (À–ÿ minus × and ÷) and Latin Extended-A/B.
	if code >= 0xC0 and code <= 0x24F:
		return code != 0xD7 and code != 0xF7
	return false


func set_display_name(raw: String) -> void:
	display_name = sanitize_display_name(raw)
	_save_settings()


func set_character(id: String) -> void:
	character_id = CharacterRegistry.sanitize(id)
	_save_settings()


## Switches the game language now and persists the choice.
func set_language(setting: String) -> void:
	language = setting if (setting == Localization.AUTO or Localization.SUPPORTED.has(setting)) else Localization.AUTO
	Localization.apply(language)
	_save_settings()


# --- Collectibles -----------------------------------------------------------

func reset_collectibles() -> void:
	_collected.clear()
	_totals.clear()
	_collected_keys.clear()


func register_collectible(collectible_id: StringName) -> void:
	_totals[collectible_id] = int(_totals.get(collectible_id, 0)) + 1
	GameEvents.collectible_total_changed.emit(collectible_id, _totals[collectible_id])


## Returns false if this instance key was already collected.
func collect(definition: Resource, instance_key: String) -> bool:
	if _collected_keys.has(instance_key):
		return false
	_collected_keys[instance_key] = true
	var id: StringName = definition.id
	_collected[id] = int(_collected.get(id, 0)) + int(definition.value)
	GameEvents.collectible_collected.emit(definition, _collected[id], int(_totals.get(id, 0)))
	return true


func get_collected(collectible_id: StringName) -> int:
	return int(_collected.get(collectible_id, 0))


func get_total(collectible_id: StringName) -> int:
	return int(_totals.get(collectible_id, 0))


# --- Persistence of local preferences ----------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	display_name = str(cfg.get_value("player", "display_name", display_name))
	language = str(cfg.get_value("player", "language", language))
	character_id = CharacterRegistry.sanitize(str(cfg.get_value("player", "character", character_id)))
	nakama_host = str(cfg.get_value("network", "host", nakama_host))
	nakama_port = int(cfg.get_value("network", "port", nakama_port))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "display_name", display_name)
	cfg.set_value("player", "language", language)
	cfg.set_value("player", "character", character_id)
	cfg.set_value("network", "host", nakama_host)
	cfg.set_value("network", "port", nakama_port)
	cfg.save(SETTINGS_PATH)


## Supports launching two clients on one machine:
##   --name=Elara   sets the display name for this run only
##   --host=..., --port=...
##   --lang=pl|en   forces the language for this run (see Localization)
##   --character=apprentice_m|placeholder   body for this run
func _apply_command_line_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--character="):
			character_id = CharacterRegistry.sanitize(arg.trim_prefix("--character="))
		if arg.begins_with("--name="):
			display_name = sanitize_display_name(arg.trim_prefix("--name="))
		elif arg.begins_with("--host="):
			nakama_host = arg.trim_prefix("--host=")
		elif arg.begins_with("--port="):
			nakama_port = int(arg.trim_prefix("--port="))
