class_name SpeechBubble
extends Label3D
## What a character just said, floating over their head for a few seconds. Whispers
## are small and only readable up close, shouts large and seen from afar; a lecture
## line (a professor teaching) is the largest and stays longest. Each new line
## replaces the last. Text arrives already filtered by the server's hearing rules.

const STYLE := {
	"whisper": {"size": 26, "range": 6.0, "seconds": 5.0, "color": Color(0.82, 0.86, 0.95)},
	"say": {"size": 34, "range": 22.0, "seconds": 7.0, "color": Color(1, 1, 1)},
	"shout": {"size": 46, "range": 55.0, "seconds": 7.0, "color": Color(1, 0.88, 0.62)},
	"lecture": {"size": 44, "range": 40.0, "seconds": 12.0, "color": Color(1, 0.9, 0.55)},
}
## Long lines wrap at this many characters per row.
const WRAP_CHARACTERS := 34
const FADE_SECONDS := 0.8

var mode: String = ""
var _left: float = 0.0
var _seconds: float = 1.0


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = false
	fixed_size = false
	pixel_size = 0.0035
	outline_size = 12
	outline_modulate = Color(0.04, 0.03, 0.06, 0.85)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	width = 600.0
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	visible = false
	set_process(false)


## Shows `line` in `p_mode` (say, whisper, shout, lecture).
func show_line(line: String, p_mode: String = "say") -> void:
	var style: Dictionary = STYLE.get(p_mode, STYLE.say)
	mode = p_mode if STYLE.has(p_mode) else "say"
	text = line
	font_size = int(style.size)
	modulate = style.color
	visibility_range_end = float(style.range)
	visibility_range_end_margin = 2.0
	visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_seconds = float(style.seconds) + clampf(line.length() / 20.0, 0.0, 6.0)
	_left = _seconds
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_left -= delta
	modulate.a = clampf(_left / FADE_SECONDS, 0.0, 1.0)
	if _left <= 0.0:
		visible = false
		set_process(false)
