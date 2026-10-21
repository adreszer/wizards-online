class_name UiSpinner
extends Control
## A loading indicator (docs/ui.md, "Components"): eight brass motes in a ring, a light
## running round them. Under reduced motion the ring stays still and only brightens and
## dims as a whole, slowly.

const MOTES := 8
const TURN := 1.1   # seconds per round

var color := UiTokens.BRASS_BRIGHT


func _init() -> void:
	custom_minimum_size = Vector2(32, 32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	var t := Time.get_ticks_msec() / 1000.0
	var still: bool = GameSettings.get_value("reduce_motion")
	var head := fmod(t / TURN, 1.0) * MOTES
	for i in MOTES:
		var a := -PI / 2.0 + TAU * i / MOTES
		var lit: float
		if still:
			lit = 0.55 + 0.25 * sin(t * 2.0)
		else:
			lit = 1.0 - fmod(head - i + MOTES, MOTES) / MOTES
		draw_circle(c + Vector2(cos(a), sin(a)) * r, 2.0 + 1.5 * lit, Color(color, 0.25 + 0.75 * lit))
