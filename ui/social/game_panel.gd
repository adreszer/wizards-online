class_name GamePanel
extends FeaturePanel
## Star Stones (server feature "game"): the seven-by-six frame, whose turn it is, and the
## column buttons for the player to move. Opens by itself when the local player is
## invited or a game starts; onlookers in the room can open it with /watch.

var _grid: GridContainer
var _cells: Array[ColorRect] = []
var _drops: HBoxContainer
var _info: Label
var _answer: HBoxContainer

const STONE := [Color(0.25, 0.2, 0.15, 0.35), Color(0.85, 0.75, 0.3), Color(0.55, 0.7, 0.95)]


func _ready() -> void:
	half_size = Vector2(250, 260)
	super()
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "game":
			open_panel())
	NetworkManager.pushed.connect(func(kind: String, d: Dictionary) -> void:
		if kind != "game":
			return
		var me := NetworkManager.local_display_name
		if not is_open and (str(d.get("a", "")) == me or str(d.get("b", "")) == me) and str(d.get("state", "")) != "over":
			open_panel()
		elif is_open:
			refresh())


func _build() -> void:
	title_label.text = tr("GAME_TITLE")
	_info = label("", 15)
	body.add_child(_info)
	_answer = HBoxContainer.new()
	_answer.add_child(button(tr("GAME_ACCEPT"), func() -> void: _ask("game_answer", {"accept": true})))
	_answer.add_child(button(tr("GAME_DECLINE"), func() -> void: _ask("game_answer", {"accept": false})))
	body.add_child(_answer)
	_drops = HBoxContainer.new()
	for c in 7:
		var col := c + 1
		var b := button("▼", func() -> void: _ask("game_move", {"col": col}))
		b.custom_minimum_size = Vector2(52, 0)
		_drops.add_child(b)
	body.add_child(_drops)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	for i in 42:
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(52, 40)
		_grid.add_child(cell)
		_cells.append(cell)
	body.add_child(_grid)
	body.add_child(button(tr("GAME_RESIGN"), func() -> void: _ask("game_resign", {})))


func refresh() -> void:
	var g := NetworkManager.feature("game")
	var board: Array = g.get("board", []) if g.get("board", []) is Array else []
	# The grid shows the top row first; the server's row 1 is the bottom.
	for row in 6:
		for col in 7:
			var i := (5 - row) * 7 + col
			var who := int(board[i]) if i < board.size() else 0
			_cells[row * 7 + col].color = STONE[clampi(who, 0, 2)]
	var me := NetworkManager.local_display_name
	var a := str(g.get("a", ""))
	var b := str(g.get("b", ""))
	var mine := 1 if a == me else (2 if b == me else 0)
	var state := str(g.get("state", ""))
	_answer.visible = state == "invited" and b == me
	_drops.visible = state == "playing" and mine > 0 and int(g.get("turn", 0)) == mine
	if g.is_empty():
		_info.text = tr("GAME_NONE")
	elif state == "over":
		var w := int(g.get("winner", 0))
		_info.text = tr("GAME_DRAW") if g.get("draw", false) else tr("GAME_WON") % (a if w == 1 else b)
	elif state == "invited":
		_info.text = tr("GAME_WAITING") % [a, b]
	else:
		_info.text = tr("GAME_TURN") % [a, b, a if int(g.get("turn", 1)) == 1 else b]


func _ask(kind: String, payload: Dictionary) -> void:
	var r: Dictionary = await NetworkManager.request(kind, payload)
	if not r.ok:
		show_result(r)
