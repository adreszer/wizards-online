class_name HudCrosshair
extends Control
## The aiming mark (docs/ui.md, Milestone 67): a small candle-coloured dot inside four
## short ticks, with a dark halo so it reads on bright stone and in the dark.

const SIZE := 22.0
const GAP := 4.0
const TICK := 4.0

var color := UiTokens.CANDLE


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	for pass_i in 2:
		var halo := pass_i == 0
		var col := Color(0, 0, 0, 0.55) if halo else Color(color, 0.9)
		var w := 3.5 if halo else 1.5
		draw_circle(c, 2.6 if halo else 1.5, col)
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * GAP, c + d * (GAP + TICK), col, w, true)
