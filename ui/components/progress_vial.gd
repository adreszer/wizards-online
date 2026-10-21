class_name ProgressVial
extends Control
## A fill bar as a glass vial (docs/ui.md, "Components"): a dark glass tube with brass
## end caps and a liquid in `liquid` colour; health, loading, lesson time. Below `low`
## (a fraction) the liquid pulses unless motion is reduced. `show_value` writes
## "value / max" over it.

const CAP := 5.0

var value := 1.0:
	set(v):
		value = v
		queue_redraw()
var max_value := 1.0:
	set(v):
		max_value = v
		queue_redraw()
var liquid := UiTokens.DANGER:
	set(v):
		liquid = v
		queue_redraw()
var low := 0.0
var show_value := false:
	set(v):
		show_value = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(160, 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func fraction() -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


func _process(_delta: float) -> void:
	if low > 0.0 and fraction() < low and not GameSettings.get_value("reduce_motion"):
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var r := h / 2.0
	var tube := Rect2(Vector2(CAP, 0), Vector2(size.x - CAP * 2.0, h))
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.05, 0.04, 0.03, 0.85)
	glass.set_corner_radius_all(int(r))
	glass.border_color = Color(UiTokens.CANDLE, 0.18)
	glass.set_border_width_all(1)
	glass.anti_aliasing = true
	draw_style_box(glass, tube)
	var f := fraction()
	if f > 0.0:
		var col := liquid
		if low > 0.0 and f < low and not GameSettings.get_value("reduce_motion"):
			col = col.lightened(0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)))
		var fill := StyleBoxFlat.new()
		fill.bg_color = col.darkened(0.15)
		fill.set_corner_radius_all(int(r - 2.0))
		fill.anti_aliasing = true
		var inner := tube.grow(-2.0)
		inner.size.x = maxf(inner.size.y, inner.size.x * f)
		draw_style_box(fill, inner)
		# The liquid's lit top and the glass highlight.
		draw_rect(Rect2(inner.position + Vector2(r * 0.5, 1.0), Vector2(maxf(inner.size.x - r, 0.0), maxf(inner.size.y * 0.3, 1.0))), Color(col.lightened(0.45), 0.45))
	draw_line(tube.position + Vector2(r, 2.5), tube.position + Vector2(tube.size.x - r, 2.5), Color(1, 1, 1, 0.12), 1.0)
	for left: bool in [true, false]:
		var cap := Rect2(Vector2(0.0 if left else size.x - CAP, -1.0), Vector2(CAP, h + 2.0))
		draw_rect(cap, UiTokens.BRASS_DIM)
		draw_rect(Rect2(cap.position + Vector2(1, 1), Vector2(CAP - 2.0, 2.0)), UiTokens.BRASS_BRIGHT)
	if show_value:
		var font := get_theme_font("font", "Label")
		var fs := UiTokens.SIZE_SMALL
		var text := "%d / %d" % [roundi(value), roundi(max_value)]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((size.x - w) / 2.0, (h + font.get_ascent(fs) - font.get_descent(fs)) / 2.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiTokens.OAK_SOLID)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.CANDLE)
