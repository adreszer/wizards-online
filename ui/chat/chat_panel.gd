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
	NetworkManager.chat_line_received.connect(_on_line)
	NetworkManager.lecture_received.connect(_on_lecture)
	NetworkManager.system_message.connect(add_system_line)
	NetworkManager.cheat_result_received.connect(_on_cheat_result)
	NetworkManager.school_clock_changed.connect(_on_school_clock_changed)
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
	var chat := ChatCommands.parse_chat(clean, NetworkManager.chat_manager.last_dm_from)
	if not chat.is_empty():
		_send_chat(chat)
	elif ChatCommands.is_command(clean):
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


## A whisper, shout or direct message typed as a command.
func _send_chat(chat: Dictionary) -> void:
	if not GameSession.is_online():
		add_system_line(tr("CHAT_OFFLINE_COMMANDS_ONLY"))
		return
	if chat.mode == "dm":
		if str(chat.get("to", "")) == "" or str(chat.text) == "":
			add_system_line(tr("CHAT_DM_USAGE"))
		else:
			NetworkManager.send_dm(chat.to, chat.text)
	elif str(chat.text) == "":
		add_system_line(tr("CHAT_MODE_USAGE"))
	else:
		NetworkManager.send_chat(chat.text, chat.mode)


func _on_line(line: Dictionary) -> void:
	_append(line_bbcode(line))


func _on_lecture(by_name: String, text: String) -> void:
	_append("[color=#f0d080][b]%s[/b][/color] %s" % [_escape(tr("LECTURE_SENDER") % by_name), _escape(text)])


## One chat or DM line as BBCode: say "[Name] text", whisper and shout marked, DMs
## "[from Name]" / "[to Name]" (and "from the mailbox" when it waited for us).
static func line_bbcode(line: Dictionary) -> String:
	var name := _escape(str(line.get("name", "?")))
	var text := _escape(str(line.get("text", "")))
	var is_self: bool = line.get("self", false)
	match str(line.get("mode", "say")):
		"whisper":
			return "[color=#a8b4c8][i][%s] %s %s[/i][/color]" % [name, TranslationServer.translate("CHAT_WHISPERS"), text]
		"shout":
			return "[color=#ffcf80][b][%s] %s %s[/b][/color]" % [name, TranslationServer.translate("CHAT_SHOUTS"), text]
		"dm":
			var head: String
			if is_self:
				head = TranslationServer.translate("CHAT_DM_TO") % _escape(str(line.get("to_name", "")))
			else:
				head = TranslationServer.translate("CHAT_DM_FROM") % name
			if line.get("mail", false):
				head += " " + TranslationServer.translate("CHAT_DM_FROM_MAIL")
			return "[color=#f0a8e0][%s][/color] %s" % [head, text]
	var color := "#c9b3ff" if is_self else "#9fd3ff"
	return "[color=%s][%s][/color] %s" % [color, name, text]


func _on_cheat_result(ok: bool, item_id: String, reason: String) -> void:
	add_system_line(ChatCommands.result_line(ok, ItemRegistry.load_definition(item_id), reason))


## Someone moved the school clock with /time (the join snapshot has no name).
func _on_school_clock_changed(by_name: String) -> void:
	if by_name != "":
		add_system_line(tr("CHEAT_TIME_SET_BY") % [SchoolClock.format(NetworkManager.school_hours()), by_name])


func add_system_line(text: String) -> void:
	_append("[color=#a0a0a8][i]%s[/i][/color]" % _escape(text))


func _append(line: String) -> void:
	_log.append_text(line + "\n")
	_panel.visible = true
	if _log.get_line_count() > MAX_LINES:
		_log.remove_paragraph(0)


static func _escape(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")
