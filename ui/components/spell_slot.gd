class_name SpellSlot
extends Control
## A hotbar roundel (docs/ui.md, "Components"): a brass ring, the spell as a disc in its
## colour with its icon, a key chip under the ring, a radial sweep while the spell
## cools down and mastery pips over the ring. An empty slot shows the bare ring.

const SIZE := 72
const ROUNDEL := 22.0
const ICON := 30
const PIP_COLOR := UiTokens.BRASS_BRIGHT
const PIP_EMPTY := Color(0, 0, 0, 0.55)

var empty := true:
	set(value):
		empty = value
		queue_redraw()
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var disabled := false:
	set(value):
		disabled = value
		queue_redraw()
var spell_color := UiTokens.BRASS:
	set(value):
		spell_color = value
		queue_redraw()
var icon_id := "spell":
	set(value):
		icon_id = value
		_icon = UiIcons.icon(icon_id, ICON) if icon_id != "" else null
		queue_redraw()
## Fraction of the cooldown still to go: 0 ready, 1 just cast.
var cooldown := 0.0:
	set(value):
		cooldown = clampf(value, 0.0, 1.0)
		queue_redraw()
var mastery := 0:
	set(value):
		mastery = value
		queue_redraw()
var mastery_max := 0:
	set(value):
		mastery_max = value
		queue_redraw()
var key_chip: KeyChip
var _icon: Texture2D


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = UiIcons.icon(icon_id, ICON)
	key_chip = KeyChip.new()
	key_chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	key_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	key_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(key_chip)


## Fills the slot with a spell; `def` null empties it.
func set_spell(def: SpellDefinition) -> void:
	empty = def == null
	if def != null:
		spell_color = def.color


func _draw() -> void:
	var c := Vector2(size.x / 2.0, SIZE / 2.0)
	var ring_state := "disabled" if disabled else "selected" if selected else "normal"
	var ring := UiFrames.texture("slot_ring_" + ring_state)
	draw_texture_rect(ring, Rect2(c - Vector2(SIZE, SIZE) / 2.0, Vector2(SIZE, SIZE)), false)
	if not empty:
		var col := spell_color if not disabled else spell_color.lerp(Color(0.4, 0.4, 0.4), 0.7)
		draw_circle(c, ROUNDEL, col.darkened(0.55))
		draw_circle(c + Vector2(-2, -3), ROUNDEL * 0.78, col.darkened(0.25))
		draw_circle(c + Vector2(-5, -7), ROUNDEL * 0.35, Color(col.lightened(0.4), 0.35))
		if _icon != null:
			var s := Vector2(ICON, ICON)
			draw_texture_rect(_icon, Rect2(c - s / 2.0, s), false, col.lightened(0.75))
		if cooldown > 0.0:
			_draw_sweep(c, ROUNDEL + 0.5, cooldown)
	if mastery_max > 0:
		_draw_pips(c)


## The part of the roundel still cooling down, darkened clockwise from the top.
func _draw_sweep(c: Vector2, r: float, fraction: float) -> void:
	var points := PackedVector2Array([c])
	var steps := maxi(2, int(48 * fraction))
	for i in steps + 1:
		var a := -PI / 2.0 + TAU * (1.0 - fraction) + TAU * fraction * i / steps
		points.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(points, Color(0, 0, 0, 0.62))
	var edge := -PI / 2.0 + TAU * (1.0 - fraction)
	draw_line(c, c + Vector2(cos(edge), sin(edge)) * r, Color(UiTokens.BRASS_BRIGHT, 0.8), 1.5, true)


func _draw_pips(c: Vector2) -> void:
	var spread := 0.32
	for i in mastery_max:
		var t := 0.0 if mastery_max == 1 else (float(i) / (mastery_max - 1) - 0.5) * 2.0
		var a := -PI / 2.0 + t * spread * (mastery_max - 1) / 2.0
		var p := c + Vector2(cos(a), sin(a)) * (SIZE / 2.0 - 1.0)
		var d := PackedVector2Array([p + Vector2(0, -4), p + Vector2(3.2, 0), p + Vector2(0, 4), p + Vector2(-3.2, 0)])
		draw_colored_polygon(d, PIP_COLOR if i < mastery else PIP_EMPTY)
		d.append(d[0])
		draw_polyline(d, UiTokens.OAK_PRESSED, 1.0, true)
