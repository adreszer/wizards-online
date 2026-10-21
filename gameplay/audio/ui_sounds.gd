extends Node
## Interface sounds. Autoload: `UiSounds`.
##
## Every BaseButton that enters the tree gets a hover tick and a click on press
## (set the meta `ui_sound` on a button to another id, or to &"" for silence:
## a panel's close button leaves the sound to the panel's own close). Panels call
## play(&"panel_open") / play(&"panel_close") (or their own id) from open()/close();
## chat lines, direct messages and HUD notifications are heard from their signals;
## a mystery's clue or solve chimes instead of the notification that carries its text.
## Plays on the UI bus (default_bus_layout.tres), not positional, and keeps
## working while the game is paused.

const SOUNDS := {
	&"hover": preload("res://assets/audio/ui/ui_hover.wav"),
	&"click": preload("res://assets/audio/ui/ui_click.wav"),
	&"back": preload("res://assets/audio/ui/ui_back.wav"),
	&"panel_open": preload("res://assets/audio/ui/ui_panel_open.wav"),
	&"panel_close": preload("res://assets/audio/ui/ui_panel_close.wav"),
	&"map_open": preload("res://assets/audio/ui/ui_map_open.wav"),
	&"inventory_open": preload("res://assets/audio/ui/ui_inventory_open.wav"),
	&"chat_message": preload("res://assets/audio/ui/ui_chat_message.wav"),
	&"dm_received": preload("res://assets/audio/ui/ui_dm_received.wav"),
	&"notification": preload("res://assets/audio/ui/ui_notification.wav"),
	&"error": preload("res://assets/audio/ui/ui_error.wav"),
	&"spell_select": preload("res://assets/audio/ui/ui_spell_select.wav"),
	&"clue_found": preload("res://assets/audio/ui/ui_clue_found.wav"),
	&"mystery_solved": preload("res://assets/audio/ui/ui_mystery_solved.wav"),
}
## Seconds before the same sound may play again (a burst of hovers or chat lines
## plays once).
const MIN_GAP := {&"hover": 0.06, &"chat_message": 0.25, &"notification": 0.8}
## Sounds that vary their pitch slightly so repeats don't sound identical.
const PITCH_JITTER := {&"hover": 0.06, &"click": 0.04, &"back": 0.04, &"chat_message": 0.05}
const VOICES := 6

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
## The last sound played, for tests.
var last_sound: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)
	NetworkManager.chat_line_received.connect(_on_chat_line)
	GameEvents.notification_requested.connect(func(_text: String, _seconds: float) -> void: play(&"notification"))
	GameEvents.mystery_cue.connect(_on_mystery_cue)


func play(id: StringName) -> void:
	if id == &"" or not SOUNDS.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(id, -INF)) < float(MIN_GAP.get(id, 0.0)):
		return
	_last_played[id] = now
	last_sound = id
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	var jitter: float = PITCH_JITTER.get(id, 0.0)
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.stream = SOUNDS[id]
	p.play()


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			play(&"hover"))
	button.pressed.connect(func() -> void: play(button.get_meta(&"ui_sound", &"click")))


func _on_mystery_cue(cue: String) -> void:
	play(&"mystery_solved" if cue == "solved" else &"clue_found")
	# The notification with the clue's text follows; the chime stands for it.
	_last_played[&"notification"] = Time.get_ticks_msec() / 1000.0


func _on_chat_line(line: Dictionary) -> void:
	if line.get("self", false):
		return
	play(&"dm_received" if str(line.get("mode", "")) == "dm" else &"chat_message")
