extends CanvasLayer
## The sorting ceremony's questionnaire. Opened by GameEvents.sorting_requested
## (the Choosing Stone), one question at a time. Online the answers go to the
## server, which assigns the house and pushes the profile; offline the same
## rule runs locally (HouseSorting.sort_offline) and the player is updated.

signal sorting_completed(house: int)

@onready var _root: Control = %Root
@onready var _progress: Label = %Progress
@onready var _question: Label = %Question
@onready var _answers: VBoxContainer = %Answers
@onready var _result: Label = %Result
@onready var _close_button: Button = %CloseButton

var is_open: bool = false
var current_question: int = 0
var answers: Array = []
var _player: Node
var _waiting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	GameEvents.local_player_spawned.connect(func(p: Node) -> void: _player = p)
	GameEvents.local_player_removed.connect(func(_p: Node) -> void: close(); _player = null)
	GameEvents.sorting_requested.connect(open)
	NetworkManager.sort_result_received.connect(_on_sort_result)
	_close_button.pressed.connect(close)


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or _player == null:
		return
	is_open = true
	_root.visible = true
	GameSession.ui_input_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	current_question = 0
	answers.clear()
	_waiting = false
	_result.text = ""
	_close_button.visible = false
	_show_question()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	GameSession.ui_input_captured = false
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_question() -> void:
	for child in _answers.get_children():
		_answers.remove_child(child)
		child.queue_free()
	var q: Dictionary = HouseSorting.QUESTIONS[current_question]
	_progress.text = tr("SORT_PROGRESS") % [current_question + 1, HouseSorting.question_count()]
	_question.text = tr(q["key"])
	for i in q["answers"].size():
		var button := Button.new()
		button.text = tr(q["answers"][i]["key"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(answer.bind(i + 1))
		_answers.add_child(button)


## Records a 1-based answer to the current question and advances.
func answer(index: int) -> void:
	if not is_open or _waiting:
		return
	answers.append(index)
	current_question += 1
	if current_question < HouseSorting.question_count():
		_show_question()
		return
	_submit()


func _submit() -> void:
	for child in _answers.get_children():
		child.queue_free()
	_progress.text = ""
	_question.text = tr("SORT_DELIBERATING")
	_waiting = true
	if NetworkManager.is_online():
		NetworkManager.send_sort(answers)
	else:
		var house := HouseSorting.sort_offline(answers)
		if _player != null:
			_player.set_profile(str(_player.get("role")), house)
		_finish(true, house, "")


func _on_sort_result(ok: bool, house: int, reason: String) -> void:
	if _waiting:
		_finish(ok, house, reason)


func _finish(ok: bool, house: int, reason: String) -> void:
	_waiting = false
	if ok:
		_question.text = tr("SORT_RESULT") % CharacterProfile.house_name(house)
		_result.text = tr("SORT_WELCOME")
		sorting_completed.emit(house)
	else:
		var key := "SORT_REASON_" + reason
		var text := tr(key)
		_question.text = tr("SORT_FAILED") % (text if text != key else reason)
	_close_button.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_open and not _waiting and current_question < HouseSorting.question_count():
		_show_question()
