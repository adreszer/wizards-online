class_name RuneTracer
extends CanvasLayer
## Casting by tracing runes (optional: /runes toggles it, saved in the settings).
## With it on, holding Cast freezes the camera and the mouse draws on the screen;
## releasing casts. A trace that matches the equipped spell's rune (strokes up, down,
## left, right: see RUNES) casts a clean, stronger spell with a golden flash; any other
## trace, or a plain click, casts normally, so nobody is locked out of a spell.
## Local player only (Player adds it).

## Spell id → its rune: the stroke directions in order (U, D, L, R).
const RUNES := {
	"arcane_pulse": "R", "uplift": "U", "galewind": "RLR", "emberkindle": "UDU", "frostbind": "DR",
	"duskveil": "DL", "glowmote": "UR", "wellspring": "DUD", "mendweave": "LDR", "quicksprout": "UL", "unbolt": "RDL",
}
## Pixels of mouse travel that make one stroke.
const STROKE_PIXELS := 45.0
## Strength of a clean cast.
const CLEAN_POWER := 1.3

var tracing := false
var _player: Player
var _strokes := ""
var _carry := Vector2.ZERO
var _line: Line2D
var _cursor := Vector2.ZERO


func setup(player: Player) -> void:
	_player = player
	layer = 2
	_line = Line2D.new()
	_line.width = 5.0
	_line.default_color = Color(1.0, 0.86, 0.45, 0.85)
	add_child(_line)


## The strokes of a mouse path (relative moves): one letter per STROKE_PIXELS of travel
## in the dominant direction, repeats collapsed.
static func strokes_of(moves: Array) -> String:
	var out := ""
	var carry := Vector2.ZERO
	for m: Vector2 in moves:
		carry += m
		if carry.length() >= STROKE_PIXELS:
			var letter := ("R" if carry.x > 0.0 else "L") if absf(carry.x) > absf(carry.y) else ("D" if carry.y > 0.0 else "U")
			if not out.ends_with(letter):
				out += letter
			carry = Vector2.ZERO
	return out


static func matches(spell_id: String, strokes: String) -> bool:
	return strokes != "" and RUNES.get(spell_id, "") == strokes


func _unhandled_input(event: InputEvent) -> void:
	if not GameSession.trace_casting or _player == null or GameSession.ui_input_captured or get_tree().paused:
		return
	if event.is_action_pressed("cast") and not tracing:
		tracing = true
		_strokes = ""
		_carry = Vector2.ZERO
		_cursor = get_viewport().get_visible_rect().size / 2.0
		_line.clear_points()
		_line.add_point(_cursor)
		_player.camera_rig.input_enabled = false
		get_viewport().set_input_as_handled()
	elif event.is_action_released("cast") and tracing:
		_finish()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and tracing:
		var rel := (event as InputEventMouseMotion).relative
		_cursor += rel
		_line.add_point(_cursor)
		_carry += rel
		if _carry.length() >= STROKE_PIXELS:
			var letter := strokes_of([_carry])
			if not _strokes.ends_with(letter):
				_strokes += letter
			_carry = Vector2.ZERO


func _finish() -> void:
	tracing = false
	_player.camera_rig.input_enabled = true
	_line.clear_points()
	var spell := _player.spell_caster.equipped_spell
	var clean := spell != null and matches(String(spell.id), _strokes)
	if _player.spell_caster.try_cast(CLEAN_POWER if clean else 1.0) and clean:
		GameEvents.notification_requested.emit(tr("RUNE_CLEAN"), 1.5)
