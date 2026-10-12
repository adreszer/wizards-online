extends CanvasLayer
## Lesson tools for professors and admins. Opens with the `lesson_tools`
## action (only for staff, online), closes with the same action or Esc.
## In a classroom the professor opens a lesson of that room's subject; while
## it runs the panel lists the students standing in the room (remote players
## inside the AreaZone box) and the subject's spells, sends lecture lines
## (typed, or read line by line from a stored lesson plan) and awards or
## deducts house points. Every action is a request: the server validates role,
## room, lesson, subject and target and answers; the panel decides nothing.

signal grant_requested(sid: String, spell_id: String)

@onready var _root: Control = %Root
@onready var _area_label: Label = %AreaLabel
@onready var _students: ItemList = %Students
@onready var _spells: ItemList = %Spells
@onready var _grant_button: Button = %GrantButton
@onready var _grant_all_button: Button = %GrantAllButton
@onready var _grant_self_button: Button = %GrantSelfButton
@onready var _result_label: Label = %ResultLabel
@onready var _lesson_label: Label = %LessonLabel
@onready var _lesson_button: Button = %LessonButton
@onready var _house_option: OptionButton = %HouseOption
@onready var _amount: SpinBox = %Amount
@onready var _reason: LineEdit = %Reason
@onready var _award_button: Button = %AwardButton
@onready var _deduct_button: Button = %DeductButton
@onready var _lecture_line: LineEdit = %LectureLine
@onready var _send_lecture_button: Button = %SendLectureButton
@onready var _plan_option: OptionButton = %PlanOption
@onready var _plan_title: LineEdit = %PlanTitle
@onready var _plan_text: TextEdit = %PlanText
@onready var _save_plan_button: Button = %SavePlanButton
@onready var _next_line_button: Button = %NextLineButton

var is_open: bool = false
var _player: Node
## Parallel to the Students list: session ids.
var _student_sids: Array[String] = []
var _spell_ids: Array[String] = []
## Subject whose spells the Spells list shows ("" = every spell).
var _listed_subject: String = "-"
var _refresh_timer: float = 0.0
## Stored lesson plans [{id, title, lines}], parallel to PlanOption items 1.. (0 = new plan).
var _plans: Array = []
## Next plan line "Next line" sends.
var _plan_cursor: int = 0


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
	NetworkManager.lessons_changed.connect(func(_l: Dictionary) -> void: if is_open: refresh())
	NetworkManager.lesson_result_received.connect(_on_lesson_result)
	NetworkManager.house_points_result_received.connect(_on_points_result)
	_lesson_button.pressed.connect(_on_lesson_pressed)
	_award_button.pressed.connect(func() -> void: _request_points(1))
	_deduct_button.pressed.connect(func() -> void: _request_points(-1))
	_send_lecture_button.pressed.connect(func() -> void: send_lecture(_lecture_line.text))
	_lecture_line.text_submitted.connect(send_lecture)
	_next_line_button.pressed.connect(send_next_plan_line)
	_save_plan_button.pressed.connect(save_plan)
	_plan_option.item_selected.connect(_on_plan_selected)
	_plan_text.text_changed.connect(func() -> void: _plan_cursor = 0)
	for h in range(1, CharacterProfile.MAX_HOUSE + 1):
		_house_option.add_item(CharacterProfile.house_name(h), h)
	_list_spells("")


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
	_load_plans()


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


## Subject id taught in the current room ("" outside a subject's classroom).
func current_subject() -> String:
	var zone := current_zone()
	if zone == null:
		return ""
	var def := SubjectRegistry.for_area(str(zone.area_id))
	return str(def.id) if def != null else ""


## The open lesson in the current room ({subject, by, sid}) or {}.
func current_lesson() -> Dictionary:
	var zone := current_zone()
	if zone == null:
		return {}
	return NetworkManager.get_lessons().get(str(zone.area_id), {})


## True when the local player runs the lesson in this room (or is an admin there).
func runs_lesson() -> bool:
	var lesson := current_lesson()
	if lesson.is_empty():
		return false
	return str(lesson.get("sid", "")) == NetworkManager.world_session.self_session_id or NetworkManager.get_local_role() == CharacterProfile.ROLE_ADMIN


## Index of a spell in the Spells list (-1 when the room's subject does not teach it).
func spell_index(spell_id: String) -> int:
	return _spell_ids.find(spell_id)


func _list_spells(subject: String) -> void:
	if subject == _listed_subject:
		return
	_listed_subject = subject
	var keep := selected_spell_id()
	_spell_ids.clear()
	_spells.clear()
	var def := SubjectRegistry.load_definition(subject)
	for spell in SpellRegistry.all():
		if def == null or def.spells().has(String(spell.id)):
			_spell_ids.append(String(spell.id))
			_spells.add_item(tr(spell.display_name))
	if _spell_ids.has(keep):
		_spells.select(_spell_ids.find(keep))


func refresh() -> void:
	var subject := current_subject()
	_list_spells(subject)
	var lesson := current_lesson()
	var subject_def := SubjectRegistry.load_definition(subject)
	if not lesson.is_empty():
		var running := SubjectRegistry.load_definition(str(lesson.get("subject", "")))
		_lesson_label.text = tr("LESSON_RUNNING") % [tr(running.display_name) if running != null else "?", str(lesson.get("by", ""))]
	elif subject_def != null:
		_lesson_label.text = tr("LESSON_READY") % tr(subject_def.display_name)
	else:
		_lesson_label.text = tr("LESSON_NO_SUBJECT")
	_lesson_button.text = tr("LESSON_CLOSE") if runs_lesson() else tr("LESSON_OPEN")
	_lesson_button.disabled = subject_def == null or (not lesson.is_empty() and not runs_lesson())
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
	# Online, teaching needs a lesson the player runs (the server checks it too).
	var teaching := in_classroom() and (not NetworkManager.is_online() or runs_lesson())
	var ok := teaching and not selected_spell_id().is_empty()
	_grant_button.disabled = not (ok and not _selected_sid().is_empty())
	_grant_all_button.disabled = not (ok and not _student_sids.is_empty())
	_grant_self_button.disabled = not ok
	_send_lecture_button.disabled = not runs_lesson()
	_next_line_button.disabled = not runs_lesson() or _plan_lines().is_empty()
	_award_button.disabled = not NetworkManager.is_local_staff()
	_deduct_button.disabled = _award_button.disabled


func _on_lesson_pressed() -> void:
	NetworkManager.send_lesson("close" if runs_lesson() else "open")


func _on_lesson_result(ok: bool, action: String, reason: String) -> void:
	if ok:
		_show(tr("LESSON_OPENED") if action == "open" else tr("LESSON_CLOSED"))
	else:
		_show(tr("LESSON_FAILED") % _reason_text("LESSON_REASON_", reason))
	if is_open:
		refresh()


## Award (sign 1) or deduct (sign -1) the Amount for the selected house.
func _request_points(sign: int) -> void:
	var reason := _reason.text.strip_edges()
	if reason.is_empty():
		_show(tr("POINTS_FAILED") % tr("POINTS_REASON_no_reason"))
		return
	var house := _house_option.get_selected_id()
	NetworkManager.send_house_points(house, sign * int(_amount.value), reason)


func _on_points_result(ok: bool, house: int, delta: int, reason: String) -> void:
	if ok:
		_reason.text = ""
		var key := "POINTS_AWARDED" if delta > 0 else "POINTS_DEDUCTED"
		_show(tr(key) % [absi(delta), CharacterProfile.house_name(house)])
	else:
		_show(tr("POINTS_FAILED") % _reason_text("POINTS_REASON_", reason))


## Sends one line of lecture text to the room (needs a lesson the player runs).
func send_lecture(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty() or not runs_lesson():
		return
	NetworkManager.send_lecture(clean)
	if text == _lecture_line.text:
		_lecture_line.text = ""


func _plan_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for line in _plan_text.text.split("\n"):
		if not line.strip_edges().is_empty():
			out.append(line.strip_edges())
	return out


## Sends the plan's next line and moves on (wraps to the start at the end).
func send_next_plan_line() -> void:
	var lines := _plan_lines()
	if lines.is_empty():
		return
	if _plan_cursor >= lines.size():
		_plan_cursor = 0
	send_lecture(lines[_plan_cursor])
	_plan_cursor += 1
	_show(tr("PLAN_LINE_SENT") % [_plan_cursor, lines.size()])


func save_plan() -> void:
	var title := _plan_title.text.strip_edges()
	if title.is_empty():
		_show(tr("PLAN_NEEDS_TITLE"))
		return
	var index := _plan_option.selected
	var id: String = str(_plans[index - 1]["id"]) if index >= 1 and index - 1 < _plans.size() and str(_plans[index - 1]["title"]) == title else ""
	var answer: Dictionary = await NetworkManager.save_lesson_plan(id, title, _plan_lines())
	if answer.has("error"):
		_show(tr("PLAN_SAVE_FAILED") % str(answer["error"]))
		return
	_show(tr("PLAN_SAVED") % title)
	await _load_plans(str(answer.get("id", "")))


func _load_plans(select_id: String = "") -> void:
	if not NetworkManager.is_online():
		return
	_plans = await NetworkManager.list_lesson_plans()
	_plan_option.clear()
	_plan_option.add_item(tr("PLAN_NEW"))
	for plan: Dictionary in _plans:
		_plan_option.add_item(str(plan.get("title", "")))
		if str(plan.get("id", "")) == select_id:
			_plan_option.select(_plan_option.item_count - 1)


func _on_plan_selected(index: int) -> void:
	_plan_cursor = 0
	if index == 0 or index - 1 >= _plans.size():
		_plan_title.text = ""
		_plan_text.text = ""
	else:
		var plan: Dictionary = _plans[index - 1]
		_plan_title.text = str(plan.get("title", ""))
		_plan_text.text = "\n".join(PackedStringArray(plan.get("lines", [])))
	_update_buttons()


func _reason_text(prefix: String, reason: String) -> String:
	var key := prefix + reason
	var text := tr(key)
	return reason if text == key else text


func _show(text: String) -> void:
	_result_label.text = text
	if not is_open:
		GameEvents.notification_requested.emit(text, 4.0)


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
		_result_label.text = tr("GRANT_FAILED") % _reason_text("GRANT_REASON_", reason)
	if not is_open:
		GameEvents.notification_requested.emit(_result_label.text, 4.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for i in _spell_ids.size():
			_spells.set_item_text(i, tr(SpellRegistry.load_definition(_spell_ids[i]).display_name))
		for i in _house_option.item_count:
			_house_option.set_item_text(i, CharacterProfile.house_name(_house_option.get_item_id(i)))
		if is_open:
			refresh()
