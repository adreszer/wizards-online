class_name RiddlePanel
extends FeaturePanel
## The common-room door's riddle of the week (server feature "riddle"): the question,
## an answer box and the server's verdict. A right answer opens the door that asked
## (GameEvents.panel_requested("riddle", {door})) and stays good for the week.

var door: Node
var _question: Label
var _answer: LineEdit


func _ready() -> void:
	half_size = Vector2(300, 170)
	super()
	GameEvents.panel_requested.connect(func(panel: String, args: Dictionary) -> void:
		if panel == "riddle":
			door = args.get("door")
			open_panel())


func _build() -> void:
	title_label.text = tr("RIDDLE_TITLE")
	_question = label("", 18)
	body.add_child(_question)
	_answer = LineEdit.new()
	_answer.placeholder_text = tr("RIDDLE_PLACEHOLDER")
	_answer.text_submitted.connect(func(_t: String) -> void: submit())
	body.add_child(_answer)
	body.add_child(button(tr("RIDDLE_ANSWER"), submit))


func refresh() -> void:
	var r := NetworkManager.feature("riddle")
	var q: Variant = r.get("question")
	_question.text = str((q as Dictionary).get(TranslationServer.get_locale().left(2), (q as Dictionary).get("pl", ""))) if q is Dictionary else ""
	_answer.text = ""
	_answer.grab_focus.call_deferred()


func submit() -> void:
	var r: Dictionary = await NetworkManager.request("riddle_answer", {"answer": _answer.text})
	if r.ok:
		close()
		GameEvents.notify(tr("RIDDLE_RIGHT"), 4.0, ToastStack.Kind.DISCOVERY)
		if is_instance_valid(door) and door.has_method("open"):
			door.open()
	else:
		show_result(r)


## Whether the local member still has to answer before `house`'s door opens.
static func must_answer(house: int) -> bool:
	if not NetworkManager.is_in_world():
		return false
	var r := NetworkManager.feature("riddle")
	return int(r.get("house", -1)) == house and r.get("question") is Dictionary and not r.get("solved", true)
