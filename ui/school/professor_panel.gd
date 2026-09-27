extends CanvasLayer
## Lesson tools for professors and admins. Opens with the `lesson_tools`
## action (only for staff, online), closes with the same action or Esc.
## Lists the students standing in the professor's current classroom (remote
## players inside the AreaZone box) and the spells of the curriculum; a click
## on "teach" asks the server, which validates role, room and target and
## answers with grant_result_received. The panel decides nothing itself.

signal grant_requested(sid: String, spell_id: String)

@onready var _root: Control = %Root
@onready var _area_label: Label = %AreaLabel
@onready var _students: ItemList = %Students
@onready var _spells: ItemList = %Spells
@onready var _grant_button: Button = %GrantButton
@onready var _grant_all_button: Button = %GrantAllButton
@onready var _grant_self_button: Button = %GrantSelfButton
@onready var _result_label: Label = %ResultLabel

var is_open: bool = false
var _player: Node
## Parallel to the Students list: session ids.
var _student_sids: Array[String] = []
var _spell_ids: Array[String] = []
var _refresh_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	GameEvents.local_player_spawned.connect(_bind_player)
	GameEvents.local_player_removed.connect(_unbind_player)
	NetworkManager.grant_result_received.connect(_on_grant_result)
	_grant_button.pressed.connect(_on_grant_pressed)
	_grant_all_button.pressed.connect(_on_grant_all_pressed)
	_grant_self_button.pressed.connect(_on_grant_self_pressed)
	_students.item_selected.connect(func(_i: int) -> void: _update_buttons())
	_spells.item_selected.connect(func(_i: int) -> void: _update_buttons())
	for def in SpellRegistry.all():
		_spell_ids.append(String(def.id))
		_spells.add_item(tr(def.display_name))


func _bind_player(player: Node) -> void:
	_player = player


func _unbind_player(_player: Node) -> void:
	close()
	_player = null


func can_open() -> bool:
	return _player != null and NetworkManager.is_local_staff()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if not is_open and event.is_action_pressed("lesson_tools") and not GameSession.ui_input_captured and can_open():
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("lesson_tools")):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 1.0
		refresh()


func open() -> void:
	if is_open or _player == null:
		return
	is_open = true
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_result_label.text = ""
	refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	GameSession.ui_input_captured = false
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func current_zone() -> AreaZone:
	if _player == null:
		return null
	var tracker: AreaTracker = _player.area_tracker
	return tracker.current_zone if tracker != null else null


func in_classroom() -> bool:
	var zone := current_zone()
	return zone != null and zone.kind == "classroom"


## Remote players standing inside the current zone's box.
func students_present() -> Array[Node]:
	var out: Array[Node] = []
	var zone := current_zone()
	if zone == null:
		return out
	var inverse := zone.global_transform.affine_inverse()
	var half := zone.size / 2.0
	for node in get_tree().get_nodes_in_group("remote_players"):
		var body := node as Node3D
		if body == null:
			continue
		var local := inverse * body.global_position
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			out.append(body)
	return out


func refresh() -> void:
	var zone := current_zone()
	if zone == null:
		_area_label.text = tr("LESSON_NOT_CLASSROOM")
	elif zone.kind != "classroom":
		_area_label.text = tr("LESSON_AREA") % zone.display_name() + "\n" + tr("LESSON_NOT_CLASSROOM")
	else:
		_area_label.text = tr("LESSON_AREA") % zone.display_name()
	var selected_sid := _selected_sid()
	_students.clear()
	_student_sids.clear()
	for student in students_present():
		_student_sids.append(str(student.get("peer_id")))
		_students.add_item(str(student.get("display_name")))
	var keep := _student_sids.find(selected_sid)
	if keep >= 0:
		_students.select(keep)
	elif _students.item_count > 0:
		_students.select(0)
	_update_buttons()


func _selected_sid() -> String:
	var selected := _students.get_selected_items()
	if selected.is_empty() or selected[0] >= _student_sids.size():
		return ""
	return _student_sids[selected[0]]


func selected_spell_id() -> String:
	var selected := _spells.get_selected_items()
	if selected.is_empty():
		return ""
	return _spell_ids[selected[0]]


func _update_buttons() -> void:
	var ok := in_classroom() and not selected_spell_id().is_empty()
	_grant_button.disabled = not (ok and not _selected_sid().is_empty())
	_grant_all_button.disabled = not (ok and not _student_sids.is_empty())
	_grant_self_button.disabled = not ok


func _on_grant_pressed() -> void:
	_request(_selected_sid())


func _on_grant_all_pressed() -> void:
	for sid in _student_sids:
		_request(sid)


func _on_grant_self_pressed() -> void:
	if _player != null:
		_request(NetworkManager.world_session.self_session_id)


func _request(sid: String) -> void:
	var spell_id := selected_spell_id()
	if sid.is_empty() or spell_id.is_empty():
		return
	grant_requested.emit(sid, spell_id)
	NetworkManager.send_grant_spell(sid, spell_id)


func _on_grant_result(ok: bool, sid: String, spell_id: String, reason: String) -> void:
	var def := SpellRegistry.load_definition(spell_id)
	var spell_name := tr(def.display_name) if def != null else spell_id
	var who := NetworkManager.state_synchronizer.get_display_name(sid)
	if who.is_empty():
		who = GameSession.display_name
	if ok:
		_result_label.text = tr("GRANT_OK") % [who, spell_name]
	else:
		var key := "GRANT_REASON_" + reason
		var text := tr(key)
		if text == key:
			text = reason
		_result_label.text = tr("GRANT_FAILED") % text
	if not is_open:
		GameEvents.notification_requested.emit(_result_label.text, 4.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for i in _spell_ids.size():
			_spells.set_item_text(i, tr(SpellRegistry.load_definition(_spell_ids[i]).display_name))
		if is_open:
			refresh()
