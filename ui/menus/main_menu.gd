extends Control
## Startup screen: display name, server address, OFFLINE / ONLINE choice.

signal start_requested()

@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_edit: LineEdit = %HostEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _offline_button: Button = %OfflineButton
@onready var _online_button: Button = %OnlineButton
@onready var _status_label: Label = %StatusLabel
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_name_edit.text = GameSession.display_name
	_host_edit.text = GameSession.nakama_host
	_port_edit.text = str(GameSession.nakama_port)
	_offline_button.pressed.connect(_on_offline)
	_online_button.pressed.connect(_on_online)
	_quit_button.pressed.connect(get_tree().quit)
	_status_label.text = NetworkManager.last_error if NetworkManager.status == NetworkManager.Status.ERROR else ""
	_name_edit.grab_focus()
	# Command-line automation: --mode=offline|online skips the menu.
	for arg in OS.get_cmdline_user_args():
		if arg == "--mode=offline":
			call_deferred("_on_offline")
		elif arg == "--mode=online":
			call_deferred("_on_online")


func _apply_fields() -> void:
	GameSession.set_display_name(_name_edit.text)
	GameSession.nakama_host = _host_edit.text.strip_edges()
	GameSession.nakama_port = int(_port_edit.text)
	_name_edit.text = GameSession.display_name


func _on_offline() -> void:
	_apply_fields()
	GameSession.play_mode = GameSession.PlayMode.OFFLINE
	start_requested.emit()


func _on_online() -> void:
	_apply_fields()
	_set_busy(true)
	_status_label.text = "Connecting…"
	var err: String = await NetworkManager.connect_online(GameSession.display_name)
	if not is_inside_tree():
		return
	if not err.is_empty():
		_status_label.text = err + "\nStart the backend with `docker compose up -d`, or play OFFLINE."
		_set_busy(false)
		return
	GameSession.play_mode = GameSession.PlayMode.ONLINE
	start_requested.emit()


func _set_busy(busy: bool) -> void:
	_offline_button.disabled = busy
	_online_button.disabled = busy
