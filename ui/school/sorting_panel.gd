extends CanvasLayer
## The sorting ceremony. Opened by GameEvents.sorting_requested (the Choosing Stone):
## the screen falls into a stone-dark vignette, the stone's name stands above a
## parchment card that asks one question at a time (the card slides in afresh for
## each), and the progress shows as marks. Online the answers go to the server,
## which assigns the house and pushes the profile; offline the same rule runs locally
## (HouseSorting.sort_offline) and the player is updated. The reveal: the house's
## crest rises on the card, a wax seal stamps beside it, the house's own sound plays
## and the ceremony music swells. Motion is instant under reduced motion.

signal sorting_completed(house: int)

@onready var _root: Control = %Root
@onready var _progress: Label = %Progress
@onready var _question: Label = %Question
@onready var _answers: VBoxContainer = %Answers
@onready var _result: Label = %Result
@onready var _crest: TextureRect = %Crest
@onready var _close_button: Button = %CloseButton
@onready var _card: PanelContainer = %Card
@onready var _crest_stage: Control = %CrestStage
@onready var _seal: TextureRect = %Seal
@onready var _vignette: TextureRect = %Vignette

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
	_close_button.set_meta(&"ui_sound", &"")
	_close_button.pressed.connect(close)
	_card.theme = load(UiTokens.PARCHMENT_THEME)
	_vignette.texture = vignette()
	_seal.texture = UiFrames.texture("wax_seal_normal")


## Stone-dark at the edges, clear in the middle, so the card reads over any scene.
static func vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, UiTokens.SHADOW)
	g.set_color(1, UiTokens.OAK_PRESSED)
	g.set_offset(1, 1.0)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 1.05)
	t.width = 256
	t.height = 256
	return t


func open() -> void:
	if is_open or _player == null:
		return
	is_open = true
	UiSounds.play(&"panel_open")
	_root.visible = true
	UiRouter.opened(self)
	current_question = 0
	answers.clear()
	_waiting = false
	_result.text = ""
	_crest_stage.visible = false
	_crest.visible = false
	_seal.visible = false
	_close_button.visible = false
	_show_question()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiSounds.play(&"panel_close")
	_root.visible = false
	UiRouter.closed(self)


func _show_question() -> void:
	for child in _answers.get_children():
		_answers.remove_child(child)
		child.queue_free()
	var q: Dictionary = HouseSorting.questions()[current_question]
	_progress.text = progress_marks(current_question, HouseSorting.question_count())
	_progress.tooltip_text = tr("SORT_PROGRESS") % [current_question + 1, HouseSorting.question_count()]
	_slide_in()
	_question.text = tr(q["key"])
	for i in q["answers"].size():
		var button := Button.new()
		button.text = tr(q["answers"][i]["key"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(answer.bind(i + 1))
		_answers.add_child(button)


## The questions as marks: answered ●, the current one ◆, still to come ○.
static func progress_marks(current: int, count: int) -> String:
	var marks := PackedStringArray()
	for i in count:
		marks.append("●" if i < current else "◆" if i == current else "○")
	return "  ".join(marks)


## Each question's card arrives with a short rise and fade.
func _slide_in() -> void:
	if GameSettings.get_value("reduce_motion"):
		return
	_card.modulate.a = 0.0
	_card.pivot_offset_ratio = Vector2(0.5, 0.5)
	_card.scale = Vector2(0.97, 0.97)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_card, "modulate:a", 1.0, UiTokens.NORMAL)
	tween.tween_property(_card, "scale", Vector2.ONE, UiTokens.NORMAL)


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
		_reveal_crest(house)
		UiSounds.play(StringName("sorting_reveal_%d" % house))
		# The ceremony's music swells with the reveal (a one-shot event track).
		var music := get_tree().root.find_child("MusicDirector", true, false) as MusicDirector
		if music != null:
			music.event_track = &"sorting"
		sorting_completed.emit(house)
	else:
		var key := "SORT_REASON_" + reason
		var text := tr(key)
		_question.text = tr("SORT_FAILED") % (text if text != key else reason)
	_close_button.visible = true


## The house crest fades and grows in above the welcome, then the seal stamps down.
func _reveal_crest(house: int) -> void:
	_crest.texture = CharacterProfile.crest(house, CharacterProfile.CREST_CARD)
	_crest.visible = _crest.texture != null
	_crest_stage.visible = _crest.visible
	_seal.visible = _crest.visible
	if GameSettings.get_value("reduce_motion"):
		return
	_crest.modulate.a = 0.0
	_crest.pivot_offset_ratio = Vector2(0.5, 0.5)
	_crest.scale = Vector2(0.85, 0.85)
	_seal.modulate.a = 0.0
	_seal.pivot_offset_ratio = Vector2(0.5, 0.5)
	_seal.scale = Vector2(1.8, 1.8)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	tween.tween_property(_crest, "modulate:a", 1.0, UiTokens.SLOW * 2.0)
	tween.tween_property(_crest, "scale", Vector2.ONE, UiTokens.SLOW * 2.0)
	tween.chain().tween_property(_seal, "modulate:a", 1.0, UiTokens.FAST)
	tween.parallel().tween_property(_seal, "scale", Vector2.ONE, UiTokens.FAST).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_open and not _waiting and current_question < HouseSorting.question_count():
		_show_question()
