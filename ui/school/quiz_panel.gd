class_name QuizPanel
extends CanvasLayer
## A professor's question to the room, for a student. When a question arrives it
## opens and takes the keyboard (choices with 1–6 or a click, an open question typed
## into the box); Esc sets it aside and K brings it back while the question is open.
## Once answered it shrinks to a reminder of the answer; when the professor closes the
## question it shows the right choice and whether the student had it, then fades.
## The professor's own copy never opens (they see the answers in the lesson panel).

const RESULT_SECONDS := 8.0

var is_open := false
var view: Dictionary = {}
var _area := ""
var _root: PanelContainer
var _title: Label
var _question: Label
var _choices: VBoxContainer
var _entry: LineEdit
var _send: Button
var _status: Label
var _hide_timer := 0.0


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	NetworkManager.quiz_changed.connect(show_view)
	GameEvents.area_entered.connect(func(area_id: StringName, _z: Node) -> void:
		if str(area_id) != _area and not view.is_empty():
			_dismiss())


func _build() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_top = 0.5
	_root.anchor_bottom = 0.5
	_root.offset_left = -440
	_root.offset_right = -20
	_root.offset_top = -170
	_root.offset_bottom = 170
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.92)
	style.border_color = Color(0.85, 0.7, 0.4, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	_root.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color(0.94, 0.82, 0.55))
	box.add_child(_title)
	_question = Label.new()
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.add_theme_font_size_override("font_size", 20)
	box.add_child(_question)
	_choices = VBoxContainer.new()
	box.add_child(_choices)
	var row := HBoxContainer.new()
	box.add_child(row)
	_entry = LineEdit.new()
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.max_length = 150
	_entry.placeholder_text = "QUIZ_TYPE_ANSWER"
	_entry.text_submitted.connect(func(text: String) -> void: _answer_text(text))
	row.add_child(_entry)
	_send = Button.new()
	_send.text = "QUIZ_SEND"
	_send.pressed.connect(func() -> void: _answer_text(_entry.text))
	row.add_child(_send)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_status)
	_root.visible = false
	add_child(_root)


## Shows the question as the server sent it ({} = gone).
func show_view(p_view: Dictionary) -> void:
	if p_view.is_empty():
		_dismiss()
		return
	if NetworkManager.world_session.self_session_id == str(NetworkManager.get_lessons().get(_current_area(), {}).get("sid", "")):
		return   # our own question: the lesson panel shows the answers
	var is_new := int(p_view.get("id", 0)) != int(view.get("id", -1))
	view = p_view
	_area = _current_area()
	_hide_timer = 0.0
	_title.text = tr("QUIZ_TITLE") % str(view.get("by", ""))
	_question.text = str(view.get("question", ""))
	for child in _choices.get_children():
		child.queue_free()
	var choices: Array = view.get("choices", [])
	var answered: bool = view.has("answer")
	var closed: bool = view.get("open", true) == false
	for i in choices.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, str(choices[i])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = closed
		if answered and int(view.answer) == i:
			b.text = "➤ " + b.text
		if closed and int(view.get("correct", -1)) == i:
			b.text += "  ✓"
		b.pressed.connect(answer.bind(i))
		_choices.add_child(b)
	_entry.get_parent().visible = choices.is_empty() and not closed
	if is_new:
		_entry.text = ""
	_status.text = status_text(view)
	_root.visible = true
	if closed:
		_hide_timer = RESULT_SECONDS
		_release()
	elif is_new and not answered:
		open()
	elif answered:
		_release()


## The line under the question: what to do, what we answered, how it went.
static func status_text(v: Dictionary) -> String:
	var tl := func(key: String) -> String: return TranslationServer.translate(key)
	if v.get("open", true) == false:
		if v.has("right"):
			return tl.call("QUIZ_RIGHT") if v.right else tl.call("QUIZ_WRONG")
		return tl.call("QUIZ_CLOSED_NO_ANSWER") if not v.has("answer") else tl.call("QUIZ_CLOSED_WAITING_MARK")
	if v.has("right"):
		return tl.call("QUIZ_RIGHT") if v.right else tl.call("QUIZ_WRONG")
	if v.has("answer"):
		return tl.call("QUIZ_ANSWERED")
	return tl.call("QUIZ_HINT_CHOICES") if (v.get("choices", []) as Array).size() > 0 else tl.call("QUIZ_HINT_OPEN")


func answer(index: int) -> void:
	if view.get("open", true) == false:
		return
	NetworkManager.answer_quiz(index)


func _answer_text(text: String) -> void:
	var clean := NetworkProtocol.sanitize_chat(text)
	if clean != "":
		NetworkManager.answer_quiz(clean)


func open() -> void:
	is_open = true
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _entry.get_parent().visible:
		_entry.grab_focus()


func _release() -> void:
	if not is_open:
		return
	is_open = false
	_entry.release_focus()
	GameSession.ui_input_captured = false


func _dismiss() -> void:
	_release()
	view = {}
	_root.visible = false


func _process(delta: float) -> void:
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if is_open or view.is_empty() or view.get("open", true) == false or GameSession.ui_input_captured:
		return
	if event.is_action_pressed("lesson_answer"):
		open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause"):
		_release()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and not _entry.has_focus():
		var n := (event as InputEventKey).physical_keycode - KEY_1
		if n >= 0 and n < (view.get("choices", []) as Array).size():
			answer(n)
			get_viewport().set_input_as_handled()


func _current_area() -> String:
	var player := get_tree().get_first_node_in_group(&"local_player")
	if player == null:
		return ""
	return str((player.get("area_tracker") as AreaTracker).current_area_id())
