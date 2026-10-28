class_name ColorSwatch
extends Button
## A colour to pick (skin tones, robe colours, decor dyes): a rounded chip of the
## colour in a thin oak rim; chosen, the rim turns brass and a soft brass halo shows;
## hovered, the rim warms. Toggle it with button_pressed.

const SIZE := Vector2(44, 34)
const RADIUS := 5.0

var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _init(chip: Color = Color.WHITE) -> void:
	color = chip
	toggle_mode = true
	flat = true
	custom_minimum_size = SIZE
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-3.0)
	if button_pressed:
		_rounded(r.grow(3.0), Color(UiTokens.BRASS_BRIGHT, 0.3))
	var rim := UiTokens.BRASS_BRIGHT if button_pressed else UiTokens.BRASS_DIM if is_hovered() else UiTokens.OAK_LINE
	_rounded(r, rim)
	_rounded(r.grow(-2.0), color)
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), UiTokens.BRASS_BRIGHT, false, 1.0)


func _rounded(r: Rect2, fill: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(int(RADIUS))
	box.anti_aliasing = true
	draw_style_box(box, r)
