extends CanvasLayer
## Text chat UI. Opens with the `chat` action, closes with `pause` (Esc) or
## after sending. While open it holds the keyboard (UiRouter, not modal).
## Lines starting with "/" are commands (ChatCommands: dev cheats such as
## /broom); they work offline too, where the box takes nothing else.
## Channel tabs (ChatChannels: all, say, whisper, shout, house, DM) filter the log
## and count unread lines; Tab / Shift+Tab switches while typing, and plain text
## typed on a tab goes out in that tab's mode. Names stand in their house colour
## with the house symbol, every line has its time, and the box fades when idle.

const MAX_LINES := 60
## Seconds without a new line before the closed box fades, and how far it fades.
const IDLE_FADE_AFTER := 12.0
const IDLE_ALPHA := 0.0

@onready var _panel: PanelContainer = %Panel
@onready var _tabs: TabBar = %Tabs
@onready var _log: RichTextLabel = %Log
@onready var _input_field: LineEdit = %Input
@onready var _mode_icon: TextureRect = %ModeIcon

var is_open: bool = false
var channels := ChatChannels.new()
var _idle: float = 0.0
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_input_field.max_length = NetworkProtocol.MAX_CHAT_LENGTH
	_input_field.text_submitted.connect(_on_submitted)
	_input_field.focus_exited.connect(_on_focus_exited)
	for tab: int in ChatChannels.Tab.values():
		_tabs.add_tab("", UiIcons.icon(ChatChannels.ICONS[tab], UiTokens.SIZE_BODY))
	_tabs.tab_changed.connect(func(tab: int) -> void: select_tab(tab))
	var hint := KeyChip.hint_row(&"", tr("CHAT_TAB_SWITCH"), &"HintLabel")
	(hint.get_child(0) as KeyChip).key_text = "Tab"
	%InputRow.add_child(hint)
	NetworkManager.chat_line_received.connect(_on_line)
	NetworkManager.lecture_received.connect(_on_lecture)
	NetworkManager.system_message.connect(add_system_line)
	NetworkManager.cheat_result_received.connect(_on_cheat_result)
	NetworkManager.school_clock_changed.connect(_on_school_clock_changed)
	_panel.visible = GameSession.is_online()
	_set_input_visible(false)
	_refresh_tabs()
	if GameSession.is_online():
		add_system_line(tr("CHAT_HINT_OPEN"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_tabs()
		_redraw()


func _process(delta: float) -> void:
	if is_open or not _panel.visible or _panel.modulate.a <= IDLE_ALPHA:
		return
	_idle += delta
	if _idle >= IDLE_FADE_AFTER and _fade == null:
		_fade_to(IDLE_ALPHA, UiTokens.SLOW * 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("chat") and not GameSession.ui_input_captured:
		open()
		get_viewport().set_input_as_handled()


## Tab / Shift+Tab while typing changes the channel instead of moving the focus.
func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.pressed or (event as InputEventKey).keycode != KEY_TAB:
		return
	var step := -1 if (event as InputEventKey).shift_pressed else 1
	select_tab(posmod(channels.current + step, ChatChannels.Tab.size()))
	get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	_panel.visible = true
	_wake()
	_set_input_visible(true)
	_input_field.text = ""
	_input_field.grab_focus()
	UiRouter.opened(self, false)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_set_input_visible(false)
	_input_field.release_focus()
	_idle = 0.0
	UiRouter.closed(self)


## Shows a channel tab: its lines, its send mode, and clears its unread count.
func select_tab(tab: int) -> void:
	channels.select(tab as ChatChannels.Tab)
	if _tabs.current_tab != tab:
		_tabs.set_block_signals(true)
		_tabs.current_tab = tab
		_tabs.set_block_signals(false)
	_mode_icon.texture = UiIcons.icon(ChatChannels.ICONS[tab], UiTokens.SIZE_BODY + 4)
	_refresh_tabs()
	_redraw()


func _on_submitted(text: String) -> void:
	var clean := NetworkProtocol.sanitize_chat(text)
	var chat := ChatCommands.parse_chat(clean, NetworkManager.chat_manager.last_dm_from)
	if not chat.is_empty():
		_send_chat(chat)
	elif ChatCommands.is_command(clean):
		var answer := ChatCommands.run(clean, get_tree().get_first_node_in_group(&"local_player"))
		if answer != "":
			add_system_line(clean)
			add_system_line(answer)
	elif not clean.is_empty():
		if not GameSession.is_online():
			add_system_line(tr("CHAT_OFFLINE_COMMANDS_ONLY"))
		else:
			var mode := ChatChannels.send_mode(channels.current)
			if mode == "dm":
				_send_chat({"mode": "dm", "to": NetworkManager.chat_manager.last_dm_from, "text": clean})
			else:
				NetworkManager.send_chat(clean, mode)
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
	var entry := line.duplicate()
	entry["house"] = _house_of(entry)
	add_line(entry)


func _on_lecture(by_name: String, text: String) -> void:
	add_line({"kind": "lecture", "name": by_name, "text": text})


## The speaker's house as the roster knows it (0 when unknown or unsorted).
func _house_of(line: Dictionary) -> int:
	var players := NetworkManager.get_players()
	if line.get("self", false):
		return int(NetworkManager.get_local_profile().get("house", 0))
	var sid := str(line.get("sid", ""))
	if players.has(sid):
		return int(players[sid].get("house", 0))
	for entry: Dictionary in players.values():
		if str(entry.get("name", "")) == str(line.get("name", "")):
			return int(entry.get("house", 0))
	return 0


## One line as BBCode: its time, then say "◆ Name: text" with the name in the
## speaker's house colour and symbol, whisper and shout marked, DMs "[from Name]" /
## "[to Name]" (and "from the mailbox" when it waited for us), lectures and system
## lines in their own colours.
static func line_bbcode(line: Dictionary) -> String:
	var time := str(line.get("time", ""))
	var stamp := "[color=#%s]%s[/color] " % [UiTokens.CANDLE_DIM.to_html(false), time] if time != "" else ""
	var text := _escape(str(line.get("text", "")))
	match str(line.get("kind", "chat")):
		"system":
			return stamp + "[color=#%s][i]%s[/i][/color]" % [UiTokens.CANDLE_SOFT.to_html(false), text]
		"lecture":
			var by := _escape(TranslationServer.translate("LECTURE_SENDER") % str(line.get("name", "")))
			return stamp + "[color=#%s][b]%s[/b] %s[/color]" % [UiTokens.BRASS_BRIGHT.to_html(false), by, text]
	var name := speaker_bbcode(str(line.get("name", "?")), int(line.get("house", 0)))
	match str(line.get("mode", NetworkProtocol.CHAT_SAY)):
		NetworkProtocol.CHAT_WHISPER:
			return stamp + "%s [color=#%s][i]%s %s[/i][/color]" % [name, UiTokens.CANDLE_SOFT.to_html(false), TranslationServer.translate("CHAT_WHISPERS"), text]
		NetworkProtocol.CHAT_SHOUT:
			return stamp + "%s [color=#%s][b]%s %s[/b][/color]" % [name, UiTokens.BRASS_BRIGHT.to_html(false), TranslationServer.translate("CHAT_SHOUTS"), text]
		"dm":
			var head: String
			if line.get("self", false):
				head = TranslationServer.translate("CHAT_DM_TO") % _escape(str(line.get("to_name", "")))
			else:
				head = TranslationServer.translate("CHAT_DM_FROM") % name
			if line.get("mail", false):
				head += " " + TranslationServer.translate("CHAT_DM_FROM_MAIL")
			return stamp + "[color=#%s][lb]%s[rb][/color] %s" % [UiTokens.BRASS.to_html(false), head, text]
	return stamp + "%s[color=#%s]:[/color] %s" % [name, UiTokens.CANDLE_SOFT.to_html(false), text]


## A speaker's name in bold, in their house colour with the house symbol in front
## (so the colour is never the only sign); candlelight when the house is unknown.
static func speaker_bbcode(speaker: String, house: int) -> String:
	var name := _escape(speaker)
	if house <= 0 or house >= GameSettings.HOUSE_SYMBOLS.size():
		return "[color=#%s][b]%s[/b][/color]" % [UiTokens.CANDLE.to_html(false), name]
	return "[color=#%s]%s [b]%s[/b][/color]" % [CharacterProfile.house_color(house).to_html(false), GameSettings.HOUSE_SYMBOLS[house], name]


func _on_cheat_result(ok: bool, item_id: String, reason: String) -> void:
	add_system_line(ChatCommands.result_line(ok, ItemRegistry.load_definition(item_id), reason))


## Someone moved the school clock with /time (the join snapshot has no name).
func _on_school_clock_changed(by_name: String) -> void:
	if by_name != "":
		add_system_line(tr("CHEAT_TIME_SET_BY") % [SchoolClock.format(NetworkManager.school_hours()), by_name])


func add_system_line(text: String) -> void:
	add_line({"kind": "system", "text": text})


## Stamps a line with the time, files it under its tabs and shows it when the
## current tab takes it.
func add_line(line: Dictionary) -> void:
	if not line.has("time"):
		line["time"] = clock_text(Time.get_time_dict_from_system())
	channels.own_house = int(NetworkManager.get_local_profile().get("house", 0))
	if channels.add(line):
		_log.append_text(line_bbcode(line) + "\n")
		if _log.get_paragraph_count() > MAX_LINES:
			_log.remove_paragraph(0)
	_refresh_tabs()
	_panel.visible = true
	_wake()


## "HH:MM" from a Time dictionary.
static func clock_text(t: Dictionary) -> String:
	return "%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0))]


func _redraw() -> void:
	_log.clear()
	var shown := channels.visible_lines()
	for i in range(maxi(0, shown.size() - MAX_LINES), shown.size()):
		_log.append_text(line_bbcode(shown[i]) + "\n")


func _refresh_tabs() -> void:
	for tab: int in ChatChannels.Tab.values():
		_tabs.set_tab_title(tab, channels.short_title(tab))
		_tabs.set_tab_tooltip(tab, channels.title(tab))


func _set_input_visible(on: bool) -> void:
	%InputRow.visible = on
	_tabs.visible = on or channels.unread.count(0) < channels.unread.size()


## A new line or opening the box brings it back to full strength.
func _wake() -> void:
	_idle = 0.0
	if _fade != null:
		_fade.kill()
		_fade = null
	_panel.modulate.a = 1.0
	_tabs.visible = is_open or channels.unread.count(0) < channels.unread.size()


func _fade_to(alpha: float, seconds: float) -> void:
	_fade = UiMotion.fade(_panel, alpha, seconds)


## Shows brackets literally instead of as BBCode tags.
static func _escape(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")
