extends Control
## The front door (docs/ui.md, Milestone 68): the castle at dusk drifting behind the
## wordmark and five choices: play online, practise offline, settings, credits, quit.
## The first time the player plays, a card asks their name and look; "Playing as …"
## opens it again. The server address sits under Advanced, only in the editor
## (GameSession.server_address_locked). A failed connection is a dialog with Retry.

signal start_requested()

const WORDMARK := "res://assets/ui/brand/wordmark_640.png"
const BUTTON := Vector2(320, 48)

var backdrop: MenuBackdrop
var online_button: Button
var offline_button: Button
var settings_button: Button
var credits_button: Button
var quit_button: Button
var playing_as: Label
var status_label: Label
var advanced_button: LinkButton
var advanced: GridContainer
var host_edit: LineEdit
var port_edit: LineEdit
var first_run: UiWindow
## The first-run card's own layer: the router dims and blurs the menu under it.
var first_run_layer: CanvasLayer
var name_edit: LineEdit
var character_option: OptionButton
var settings: SettingsPanel
var credits: CreditsPanel
## What to do once the first-run card is answered: "online", "offline" or "".
var _pending := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_playing_as()
	host_edit.text = GameSession.nakama_host
	port_edit.text = str(GameSession.nakama_port)
	advanced_button.visible = not GameSession.server_address_locked
	advanced.visible = false
	status_label.text = NetworkManager.last_error if NetworkManager.status == NetworkManager.Status.ERROR else ""
	online_button.grab_focus.call_deferred()
	# Command-line automation: --mode=offline|online skips the menu.
	for arg in OS.get_cmdline_user_args():
		if arg == "--mode=offline":
			_start_offline.call_deferred()
		elif arg == "--mode=online":
			_start_online.call_deferred()


func _build() -> void:
	backdrop = MenuBackdrop.new()
	add_child(backdrop)
	var column := UiBox.v(UiTokens.SPACE_3)
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.offset_left = 110
	add_child(column)
	var wordmark := TextureRect.new()
	wordmark.texture = load(WORDMARK)
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.custom_minimum_size = Vector2(420, 140)
	wordmark.tooltip_text = "Arcane Academy"
	wordmark.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(wordmark)
	var subtitle := Label.new()
	subtitle.text = "MENU_SUBTITLE"
	subtitle.theme_type_variation = &"BannerSubLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.custom_minimum_size.x = 420
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = UiTokens.SPACE_5
	column.add_child(spacer)
	var buttons := UiBox.v(UiTokens.SPACE_2)
	buttons.mouse_filter = Control.MOUSE_FILTER_PASS
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(buttons)
	online_button = _button(buttons, "MENU_PLAY_ONLINE", _on_online)
	offline_button = _button(buttons, "MENU_PLAY_OFFLINE", _on_offline)
	settings_button = _button(buttons, "SETTINGS_TITLE", func() -> void: GameEvents.panel_requested.emit("settings", {}))
	credits_button = _button(buttons, "MENU_CREDITS", func() -> void: credits.open_panel())
	quit_button = _button(buttons, "MENU_QUIT", func() -> void: get_tree().quit())
	var who := UiBox.h(UiTokens.SPACE_2, BoxContainer.ALIGNMENT_CENTER)
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(who)
	playing_as = Label.new()
	playing_as.theme_type_variation = &"HudMeta"
	playing_as.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(playing_as)
	var change := LinkButton.new()
	change.text = "MENU_CHANGE"
	change.pressed.connect(_open_first_run.bind(""))
	who.add_child(change)
	status_label = Label.new()
	status_label.theme_type_variation = &"HudStatus"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 420
	column.add_child(status_label)
	# Bottom left: the server address, for development only.
	var corner := UiBox.v(UiTokens.SPACE_1)
	corner.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = UiTokens.SPACE_5
	corner.offset_bottom = -UiTokens.SPACE_4
	add_child(corner)
	advanced = GridContainer.new()
	advanced.columns = 2
	corner.add_child(advanced)
	host_edit = _field(advanced, "MENU_HOST")
	port_edit = _field(advanced, "MENU_PORT")
	advanced_button = LinkButton.new()
	advanced_button.text = "MENU_ADVANCED"
	advanced_button.pressed.connect(func() -> void: advanced.visible = not advanced.visible)
	corner.add_child(advanced_button)
	var version := Label.new()
	var number := str(ProjectSettings.get_setting("application/config/version", ""))
	version.text = "v" + number
	version.visible = number != ""
	version.theme_type_variation = &"HudMeta"
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -UiTokens.SPACE_5
	version.offset_bottom = -UiTokens.SPACE_4
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(version)
	_build_first_run()
	settings = SettingsPanel.new()
	add_child(settings)
	credits = CreditsPanel.new()
	add_child(credits)


func _button(parent: Control, key: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = BUTTON
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _field(grid: GridContainer, key: String) -> LineEdit:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = &"HudMeta"
	grid.add_child(l)
	var e := LineEdit.new()
	e.custom_minimum_size.x = 200
	grid.add_child(e)
	return e


# --- First run ---------------------------------------------------------------------------

func _build_first_run() -> void:
	first_run_layer = CanvasLayer.new()
	first_run_layer.name = "FirstRun"
	first_run_layer.layer = 3
	add_child(first_run_layer)
	first_run = UiWindow.new(UiWindow.Family.PARCHMENT, false)
	first_run.centre(Vector2(300, 135))
	first_run.title_label.text = "FIRST_RUN_TITLE"
	first_run.close_requested.connect(_close_first_run)
	first_run.visible = false
	first_run_layer.add_child(first_run)
	# Esc takes the layer off the router's stack; the card follows.
	UiRouter.changed.connect(func() -> void:
		if first_run.visible and not UiRouter.is_open(first_run_layer):
			_close_first_run())
	var text := Label.new()
	text.text = "FIRST_RUN_TEXT"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	first_run.body.add_child(text)
	var grid := GridContainer.new()
	grid.columns = 2
	first_run.body.add_child(grid)
	var name_label := Label.new()
	name_label.text = "MENU_DISPLAY_NAME"
	grid.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.max_length = GameSession.MAX_DISPLAY_NAME_LENGTH
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t: String) -> void: _confirm_first_run())
	grid.add_child(name_edit)
	var character_label := Label.new()
	character_label.text = "MENU_CHARACTER"
	grid.add_child(character_label)
	character_option = OptionButton.new()
	character_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_characters()
	grid.add_child(character_option)
	var row := UiBox.h(UiTokens.SPACE_3, BoxContainer.ALIGNMENT_END)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	first_run.body.add_child(row)
	var go := Button.new()
	go.text = "FIRST_RUN_CONTINUE"
	go.pressed.connect(_confirm_first_run)
	row.add_child(go)


func _fill_characters() -> void:
	character_option.clear()
	for id in CharacterRegistry.ids():
		character_option.add_item(tr(CharacterRegistry.name_key(id)))
		character_option.set_item_metadata(character_option.item_count - 1, id)
		if id == GameSession.character_id:
			character_option.select(character_option.item_count - 1)


## Static texts are translation keys and follow a language change by themselves; the
## formatted ones are written again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and playing_as != null:
		_refresh_playing_as()
		_fill_characters()


## Asks for the name and look; `then` ("online", "offline" or "") runs after.
func _open_first_run(then: String) -> void:
	_pending = then
	name_edit.text = GameSession.display_name if GameSession.name_chosen else ""
	name_edit.placeholder_text = "PLAYER_DEFAULT_NAME"
	for i in character_option.item_count:
		if character_option.get_item_metadata(i) == GameSession.character_id:
			character_option.select(i)
	first_run.show_window()
	UiRouter.opened(first_run_layer)
	name_edit.grab_focus.call_deferred()


func _confirm_first_run() -> void:
	GameSession.set_display_name(name_edit.text)
	if character_option.selected >= 0:
		GameSession.set_character(str(character_option.get_item_metadata(character_option.selected)))
	var then := _pending
	_close_first_run()
	_refresh_playing_as()
	if then == "online":
		_start_online()
	elif then == "offline":
		_start_offline()


func _close_first_run() -> void:
	_pending = ""
	if first_run.visible:
		first_run.hide_window()
		UiRouter.closed(first_run_layer)


func _refresh_playing_as() -> void:
	playing_as.text = tr("MENU_PLAYING_AS") % GameSession.display_name


# --- Playing -------------------------------------------------------------------------------

func _apply_server_fields() -> void:
	if not GameSession.server_address_locked:
		GameSession.nakama_host = host_edit.text.strip_edges()
		GameSession.nakama_port = int(port_edit.text)


func _on_offline() -> void:
	if not GameSession.name_chosen:
		_open_first_run("offline")
	else:
		_start_offline()


func _on_online() -> void:
	if not GameSession.name_chosen:
		_open_first_run("online")
	else:
		_start_online()


func _start_offline() -> void:
	_apply_server_fields()
	GameSession.play_mode = GameSession.PlayMode.OFFLINE
	start_requested.emit()


func _start_online() -> void:
	_apply_server_fields()
	_set_busy(true)
	status_label.text = tr("MENU_CONNECTING")
	var err: String = await NetworkManager.connect_online(GameSession.display_name)
	if not is_inside_tree():
		return
	_set_busy(false)
	if not err.is_empty():
		status_label.text = ""
		var text := err if GameSession.server_address_locked else err + "\n" + tr("MENU_CONNECT_FAILED_HINT")
		var dialog := UiDialog.error(self, tr("MENU_CONNECT_FAILED"), text)
		dialog.answered.connect(func(retry: bool) -> void:
			if retry:
				_start_online()
			else:
				online_button.grab_focus())
		return
	GameSession.play_mode = GameSession.PlayMode.ONLINE
	start_requested.emit()


func _set_busy(busy: bool) -> void:
	for b: Button in [online_button, offline_button]:
		b.disabled = busy
