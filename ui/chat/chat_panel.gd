extends CanvasLayer
## Text chat UI. Opens with the `chat` action, closes with `pause` (Esc) or
## after sending. While open it captures keyboard input (GameSession.ui_input_captured).
## Lines starting with "/" are commands (ChatCommands: dev cheats such as
## /broom); they work offline too, where the box takes nothing else.

const MAX_LINES := 60

@onready var _panel: PanelContainer = %Panel
@onready var _log: RichTextLabel = %Log
@onready var _input_field: LineEdit = %Input

var is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_input_field.max_length = NetworkProtocol.MAX_CHAT_LENGTH
	_input_field.text_submitted.connect(_on_submitted)
	_input_field.focus_exited.connect(_on_focus_exited)
	NetworkManager.chat_message_received.connect(_on_message)
	NetworkManager.system_message.connect(add_system_line)
	NetworkManager.cheat_result_received.connect(_on_cheat_result)
	_panel.visible = GameSession.is_online()
	_input_field.visible = false
	if GameSession.is_online():
		add_system_line(tr("CHAT_HINT_OPEN"))


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("chat") and not GameSession.ui_input_captured:
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	_panel.visible = true
	_input_field.visible = true
	_input_field.text = ""
	_input_field.grab_focus()
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open:
		return
	is_open = false
	_input_field.visible = false
	_input_field.release_focus()
	GameSession.ui_input_captured = false
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_submitted(text: String) -> void:
	var clean := NetworkProtocol.sanitize_chat(text)
	if ChatCommands.is_command(clean):
		add_system_line(clean)
		add_system_line(ChatCommands.run(clean, get_tree().get_first_node_in_group(&"local_player")))
	elif not clean.is_empty():
		if GameSession.is_online():
			NetworkManager.send_chat(clean)
		else:
			add_system_line(tr("CHAT_OFFLINE_COMMANDS_ONLY"))
	close()


func _on_focus_exited() -> void:
	if is_open:
		close()


func _on_message(sender_name: String, text: String, is_self: bool) -> void:
	var color := "#c9b3ff" if is_self else "#9fd3ff"
	_append("[color=%s][%s][/color] %s" % [color, _escape(sender_name), _escape(text)])


func _on_cheat_result(ok: bool, item_id: String, reason: String) -> void:
	add_system_line(ChatCommands.result_line(ok, ItemRegistry.load_definition(item_id), reason))


func add_system_line(text: String) -> void:
	_append("[color=#a0a0a8][i]%s[/i][/color]" % _escape(text))


func _append(line: String) -> void:
	_log.append_text(line + "\n")
	_panel.visible = true
	if _log.get_line_count() > MAX_LINES:
		_log.remove_paragraph(0)


static func _escape(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")
