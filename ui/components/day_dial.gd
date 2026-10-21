class_name DayDial
extends Control
## The HUD's clock face (docs/ui.md, Milestone 67): a brass ring round a window of sky
## that follows the school day (night blue, dawn amber, day blue, dusk ember), with the
## sun or the moon climbing over a dark horizon. Display only.

const SIZE := 64
const NIGHT_SKY := Color("1a2236")
const DAWN_SKY := Color("b8774a")
const DAY_SKY := Color("6d97bd")
const DUSK_SKY := Color("9a4f36")
const HORIZON := Color("120d0a")
const SUN := Color("f6d98a")
const MOON := Color("dfe4f0")

## School hours, 0–24.
var hours := 12.0:
	set(value):
		hours = fposmod(value, 24.0)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The sky colour at `h` hours, blended across dawn and dusk.
static func sky_at(h: float) -> Color:
	if h < SchoolClock.DAWN_START or h >= SchoolClock.NIGHT_START:
		return NIGHT_SKY
	if h < SchoolClock.DAY_START:
		var t := (h - SchoolClock.DAWN_START) / (SchoolClock.DAY_START - SchoolClock.DAWN_START)
		return NIGHT_SKY.lerp(DAWN_SKY, minf(t * 2.0, 1.0)).lerp(DAY_SKY, maxf(t * 2.0 - 1.0, 0.0))
	if h < SchoolClock.DUSK_START:
		return DAY_SKY
	var t := (h - SchoolClock.DUSK_START) / (SchoolClock.NIGHT_START - SchoolClock.DUSK_START)
	return DAY_SKY.lerp(DUSK_SKY, minf(t * 2.0, 1.0)).lerp(NIGHT_SKY, maxf(t * 2.0 - 1.0, 0.0))


## Where the sun (by day) or the moon (by night) stands along its arc: 0 rising in the
## east (left), 1 setting in the west; and whether it is the sun.
static func body_at(h: float) -> Array:
	var rise := SchoolClock.DAWN_START + 1.0
	var set_at := SchoolClock.NIGHT_START - 1.0
	if h >= rise and h < set_at:
		return [(h - rise) / (set_at - rise), true]
	var night := fposmod(h - set_at, 24.0)
	return [night / (24.0 - (set_at - rise)), false]


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	# The slot ring's outer edge is 30/72 of its texture, its well a dark disc inside.
	draw_texture_rect(UiFrames.texture("slot_ring_normal"), Rect2(c - Vector2(r, r) * 1.2, Vector2(r, r) * 2.4), false)
	var inner := r * 0.8
	draw_circle(c, inner, sky_at(hours))
	var body := body_at(hours)
	var a := PI + PI * float(body[0])
	var p := c + Vector2(cos(a) * inner * 0.62, sin(a) * inner * 0.55 + inner * 0.2)
	if body[1]:
		draw_circle(p, inner * 0.34, Color(SUN, 0.25))
		draw_circle(p, inner * 0.21, SUN)
	else:
		draw_circle(p, inner * 0.2, MOON)
		draw_circle(p + Vector2(inner * 0.09, -inner * 0.05), inner * 0.17, sky_at(hours))
	# The horizon: a low wavy hill line, then round the bottom of the window.
	var rise := 0.3
	var t0 := asin(rise)
	var half := inner * cos(t0)
	var hill := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		hill.append(Vector2(c.x - half + half * 2.0 * t, c.y + inner * rise - sin(t * PI * 2.0 + 0.6) * inner * 0.05 * sin(t * PI)))
	for i in range(1, 16):
		var ang := t0 + (PI - 2.0 * t0) * float(i) / 16.0
		hill.append(c + Vector2(cos(ang), sin(ang)) * inner)
	draw_colored_polygon(hill, HORIZON)
	draw_arc(c, inner, 0.0, TAU, 48, Color(HORIZON, 0.8), 1.5, true)
