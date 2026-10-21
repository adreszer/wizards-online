class_name HouseCrystals
extends HBoxContainer
## The house points at a glance (docs/ui.md, Milestone 67): four crystals in the house
## colours, each filled by its share of the leader's points, the points under it; the
## leading house's crystal glows. The tooltip names the house.

const CRYSTAL := Vector2(16, 34)

var _crystals: Array[Control] = []
var _labels: Array[Label] = []
var _totals := PackedInt32Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	for h in range(1, CharacterProfile.MAX_HOUSE + 1):
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_theme_constant_override("separation", 1)
		var crystal := Control.new()
		crystal.custom_minimum_size = CRYSTAL
		crystal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		crystal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crystal.draw.connect(_draw_crystal.bind(crystal, h))
		column.add_child(crystal)
		var label := Label.new()
		label.theme_type_variation = &"HudCount"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 30
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		column.add_child(label)
		add_child(column)
		_crystals.append(crystal)
		_labels.append(label)


## Points per house (index 0 = house 1).
func set_totals(totals: PackedInt32Array) -> void:
	_totals = totals
	for i in _labels.size():
		var points := totals[i] if i < totals.size() else 0
		_labels[i].text = str(points)
		(_labels[i].get_parent() as Control).tooltip_text = tr("HUD_HOUSE_POINTS") % [CharacterProfile.house_name(i + 1), points]
		_crystals[i].queue_redraw()


## The points as shown, "5 10 15 20" (tests).
func text() -> String:
	var parts := PackedStringArray()
	for label in _labels:
		parts.append(label.text)
	return " ".join(parts)


## How full house `h`'s crystal is: its points over the leader's, never quite empty.
func fill_of(h: int) -> float:
	var best := 0
	for p in _totals:
		best = maxi(best, p)
	if best <= 0 or h - 1 >= _totals.size():
		return 0.08
	return clampf(maxf(_totals[h - 1], 0) / float(best), 0.08, 1.0)


func _draw_crystal(c: Control, h: int) -> void:
	var w := c.size.x
	var ht := c.size.y
	var pts := PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w, ht * 0.22), Vector2(w, ht * 0.8),
		Vector2(w * 0.5, ht), Vector2(0, ht * 0.8), Vector2(0, ht * 0.22)])
	var colour := CharacterProfile.house_color(h)
	var fill := fill_of(h)
	if fill >= 1.0 and _totals.size() >= h and _totals[h - 1] > 0:
		c.draw_circle(Vector2(w * 0.5, ht * 0.5), w * 1.05, Color(colour, 0.18))
	c.draw_colored_polygon(pts, Color(UiTokens.OAK_INSET, 0.85))
	# The filled part: the crystal cut off at the fill line.
	var line := ht * (1.0 - fill)
	var filled := Geometry2D.clip_polygons(pts, PackedVector2Array([Vector2(-1, -1), Vector2(w + 1, -1), Vector2(w + 1, line), Vector2(-1, line)]))
	for poly in filled:
		c.draw_colored_polygon(poly, colour.darkened(0.15))
	# A lit facet down the left side.
	c.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w * 0.5, ht), Vector2(0, ht * 0.8), Vector2(0, ht * 0.22)]), Color(1, 1, 1, 0.1))
	pts.append(pts[0])
	c.draw_polyline(pts, UiTokens.BRASS, 1.2, true)
