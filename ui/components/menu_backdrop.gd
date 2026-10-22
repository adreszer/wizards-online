class_name MenuBackdrop
extends Control
## The front door's backdrop (docs/ui.md, Milestone 68): the castle at dusk
## (assets/ui/menu/backdrop.jpg, rendered by tools/capture_menu_backdrop.gd) drifting
## slowly, darkened towards the left where the menu stands and along the bottom. Still
## under reduced motion.

const IMAGE := "res://assets/ui/menu/backdrop.jpg"
## How much larger than the screen the picture is drawn, so the drift never shows an edge.
const OVERSCAN := 1.08
## Pixels the picture wanders at most, and seconds per sway.
const DRIFT := Vector2(26, 10)
const PERIOD := Vector2(70, 47)

var picture: TextureRect
var _t := 0.0


func _init() -> void:
	name = "MenuBackdrop"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	picture = TextureRect.new()
	picture.texture = load(IMAGE)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	add_child(_shade(Vector2(1, 0), PackedFloat32Array([0.0, 0.42, 0.7]),
		PackedColorArray([Color(0.04, 0.03, 0.02, 0.82), Color(0.04, 0.03, 0.02, 0.45), Color(0.04, 0.03, 0.02, 0.0)])))
	add_child(_shade(Vector2(0, 1), PackedFloat32Array([0.0, 0.7, 1.0]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0.03, 0.02, 0.02, 0.6)])))
	resized.connect(_place)


## A full-screen gradient running along `direction` (from the left, or from the top).
func _shade(direction: Vector2, offsets: PackedFloat32Array, colors: PackedColorArray) -> TextureRect:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_to = direction
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _process(delta: float) -> void:
	if GameSettings.get_value("reduce_motion"):
		return
	_t += delta
	_place()


func _place() -> void:
	picture.size = size * OVERSCAN
	var sway := Vector2(sin(TAU * _t / PERIOD.x), sin(TAU * _t / PERIOD.y)) * DRIFT
	picture.position = (size - picture.size) / 2.0 + sway
