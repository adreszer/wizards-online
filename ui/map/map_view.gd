class_name MapView
extends Control
## Draws a CastleMap: the grounds' relief underneath, then the rooms, stairs,
## place names and player markers of one storey, north up (world -Z is up,
## +X right). The minimap and the full map are both a MapView with different
## zoom and options; neither owns any map data.

const SHADER := preload("res://ui/map/map_terrain.gdshader")

const INK := Color(0.24, 0.17, 0.1)
const PAPER := Color(0.87, 0.81, 0.66)
const BACKGROUND := Color(0.2, 0.22, 0.2)
const FOOTPRINT := Color(0.24, 0.17, 0.1, 0.22)
const CURRENT_ROOM := Color(1.0, 0.86, 0.45)
const KIND_COLORS := {
	"corridor": Color(0.8, 0.74, 0.6),
	"hall": Color(0.9, 0.82, 0.62),
	"classroom": Color(0.78, 0.8, 0.72),
	"library": Color(0.8, 0.72, 0.6),
	"outdoor": Color(0.62, 0.68, 0.5),
	"bridge": Color(0.74, 0.7, 0.62),
	"tower": Color(0.84, 0.78, 0.66),
	"stair_turret": Color(0.7, 0.66, 0.58),
	"shaft": Color(0.6, 0.57, 0.52),
	"secret": Color(0.72, 0.62, 0.78),
	"shop": Color(0.88, 0.72, 0.42),
	"inn": Color(0.82, 0.56, 0.42),
	"post_office": Color(0.6, 0.7, 0.86),
	"station": Color(0.66, 0.74, 0.6),
}
## Kinds whose names are worth printing first; ordinary rooms get one when they fit.
const LABEL_PRIORITY := ["hall", "classroom", "library", "common_room", "dormitory", "outdoor", "secret", "tower", "shaft", "bridge",
	"station", "inn", "post_office", "shop"]

@export var pixels_per_metre: float = 2.0
@export var show_room_labels: bool = true
@export var show_place_labels: bool = true
@export var label_font_size: int = 12
## Prints an "N" at the top edge (the minimap).
@export var show_compass: bool = false

var castle_map: CastleMap:
	set(value):
		if castle_map != null and castle_map.rebuilt.is_connected(_on_map_rebuilt):
			castle_map.rebuilt.disconnect(_on_map_rebuilt)
			castle_map.changed.disconnect(refresh)
		castle_map = value
		if castle_map != null:
			castle_map.rebuilt.connect(_on_map_rebuilt)
			castle_map.changed.connect(refresh)
		_on_map_rebuilt()
## World XZ at the centre of the control.
var centre := Vector2.ZERO
var storey: int = 0
## Room under the mouse (full map), outlined.
var hover_room: Dictionary = {}

var _terrain_rect: ColorRect
var _ink: Control


func _ready() -> void:
	clip_contents = true
	_terrain_rect = ColorRect.new()
	_terrain_rect.name = "Terrain"
	_terrain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_rect.visible = false
	add_child(_terrain_rect)
	_ink = Control.new()
	_ink.name = "Ink"
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.draw.connect(_draw_ink)
	add_child(_ink)
	_on_map_rebuilt()


func world_to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - centre) * pixels_per_metre


func screen_to_world(s: Vector2) -> Vector2:
	return centre + (s - size * 0.5) / pixels_per_metre


func refresh() -> void:
	if _terrain_rect == null:
		return
	if _terrain_rect.visible and castle_map != null and castle_map.terrain != null:
		var ext := castle_map.terrain.extent()
		_terrain_rect.position = world_to_screen(ext.position)
		_terrain_rect.size = ext.size * pixels_per_metre
	_ink.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)


func _on_map_rebuilt() -> void:
	if _terrain_rect == null:
		return
	var terrain := castle_map.terrain if castle_map != null else null
	var heights := terrain.height_image() if terrain != null else null
	_terrain_rect.visible = heights != null
	if heights != null:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var splat: Texture2D = load(terrain.meta["splat"])
		var ext := terrain.extent()
		mat.set_shader_parameter("heights", ImageTexture.create_from_image(heights))
		mat.set_shader_parameter("splat", splat)
		mat.set_shader_parameter("grid_size", Vector2(terrain.size_x, terrain.size_z))
		mat.set_shader_parameter("extent_size", ext.size)
		mat.set_shader_parameter("splat_scale", ext.size / (Vector2(splat.get_width(), splat.get_height()) * float(terrain.meta["splat_spacing"])))
		mat.set_shader_parameter("h_min", terrain.h_min)
		mat.set_shader_parameter("h_scale", terrain.h_scale)
		mat.set_shader_parameter("water_level", terrain.water_level)
		_terrain_rect.material = mat
	refresh()


func _draw_ink() -> void:
	if castle_map == null:
		return
	var view := Rect2(screen_to_world(Vector2.ZERO), size / pixels_per_metre)
	var line := clampf(pixels_per_metre * 0.25, 1.0, 2.0)
	# The castle's whole footprint, faintly, so upper storeys keep their bearings.
	for r in castle_map.rooms:
		if castle_map.is_known(r) and view.intersects(r["rect"]):
			_ink.draw_rect(_to_screen(r["rect"]), FOOTPRINT)
	var rooms := castle_map.rooms_on(storey)
	for r in rooms:
		if view.intersects(r["rect"]):
			_ink.draw_rect(_to_screen(r["rect"]), _room_color(r))
	for r in rooms:
		if view.intersects(r["rect"]):
			_ink.draw_rect(_to_screen(r["rect"]), INK, false, line)
	for s in castle_map.stairs_on(storey):
		_draw_stair(s, line)
	var here := _local_player()
	if here != null:
		var current := castle_map.room_at(here.global_position)
		if not current.is_empty() and castle_map.view_storey_at(here.global_position) == storey:
			_ink.draw_rect(_to_screen(current["rect"]).grow(-line), CURRENT_ROOM, false, line * 1.5)
	if not hover_room.is_empty():
		_ink.draw_rect(_to_screen(hover_room["rect"]), Color(1, 1, 1, 0.9), false, line * 1.5)
	if show_place_labels and storey == 0:
		for g in castle_map.grounds:
			_label(_to_screen(g["rect"]), tr(g["key"]), label_font_size + 2, Color(0.12, 0.1, 0.06), true)
	if show_room_labels:
		_draw_room_labels(rooms, view)
	_draw_players()
	if show_compass:
		var font := get_theme_default_font()
		var north := tr("MAP_NORTH")
		var w := font.get_string_size(north, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var at := Vector2(size.x * 0.5 - w * 0.5, 4.0 + font.get_ascent(14))
		_ink.draw_string_outline(font, at, north, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.7))
		_ink.draw_string(font, at, north, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.8))


## Player-facing name of a storey: the dungeons, the ground floor, floor N.
static func storey_name(storey: int) -> String:
	if storey == 0:
		return TranslationServer.translate("MAP_FLOOR_GROUND")
	if storey < 0:
		return TranslationServer.translate("MAP_FLOOR_DUNGEONS") % -storey
	return TranslationServer.translate("MAP_FLOOR_N") % storey


func _to_screen(r: Rect2) -> Rect2:
	return Rect2(world_to_screen(r.position), r.size * pixels_per_metre)


func _room_color(r: Dictionary) -> Color:
	var house: int = r["house"]
	if house > 0:
		return PAPER.lerp(CharacterProfile.HOUSE_COLORS[house], 0.4)
	return KIND_COLORS.get(r["kind"], PAPER)


func _draw_stair(s: Dictionary, line: float) -> void:
	if s.has("spiral"):
		var c := world_to_screen(s["centre"])
		var radius: float = s["radius"] * pixels_per_metre
		_ink.draw_arc(c, radius * 0.75, 0.0, TAU * 0.8, 24, INK, line)
		_ink.draw_circle(c, maxf(radius * 0.15, 1.5), INK)
		return
	var dir: Vector2 = s["dir"]
	var side: Vector2 = Vector2(-dir.y, dir.x) * s["width"] * 0.5
	var foot: Vector2 = s["foot"]
	var top: Vector2 = foot + dir * s["run"]
	var corners := PackedVector2Array([world_to_screen(foot + side), world_to_screen(top + side), world_to_screen(top - side), world_to_screen(foot - side)])
	_ink.draw_colored_polygon(corners, Color(0.68, 0.63, 0.53))
	var treads := clampi(int(s["run"] * pixels_per_metre / 4.0), 2, 14)
	for i in range(1, treads):
		var p: Vector2 = foot + dir * s["run"] * float(i) / treads
		_ink.draw_line(world_to_screen(p + side), world_to_screen(p - side), INK, 1.0)
	corners.append(corners[0])
	_ink.draw_polyline(corners, INK, line)
	# An arrow pointing uphill on the lower storey, downhill on the upper one.
	var going_up: bool = storey == s["lo"]
	var tip := world_to_screen(top if going_up else foot)
	var tail := world_to_screen(foot.lerp(top, 0.5))
	var head := (tip - tail).normalized() * minf(6.0, s["width"] * pixels_per_metre * 0.4)
	if head.length() > 1.0:
		_ink.draw_line(tail, tip, INK, line)
		_ink.draw_line(tip, tip - head + head.orthogonal() * 0.6, INK, line)
		_ink.draw_line(tip, tip - head - head.orthogonal() * 0.6, INK, line)


func _draw_room_labels(rooms: Array[Dictionary], view: Rect2) -> void:
	var ordered: Array[Dictionary] = []
	for r in rooms:
		if view.intersects(r["rect"]):
			ordered.append(r)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := LABEL_PRIORITY.find(a["kind"])
		var pb := LABEL_PRIORITY.find(b["kind"])
		pa = pa if pa >= 0 else LABEL_PRIORITY.size()
		pb = pb if pb >= 0 else LABEL_PRIORITY.size()
		return pa < pb if pa != pb else a["rect"].get_area() > b["rect"].get_area())
	var taken: Array[Rect2] = []
	for r in ordered:
		var box := _to_screen(r["rect"]).intersection(Rect2(Vector2.ZERO, size))
		var placed := _label(box, tr(r["key"]), label_font_size, INK, false, taken)
		if placed.has_area():
			taken.append(placed)


## Draws text centred in `box` if it fits (and misses `taken`); returns the
## rect it used, or an empty one.
func _label(box: Rect2, text: String, font_size: int, color: Color, outline: bool, taken: Array[Rect2] = []) -> Rect2:
	var font := get_theme_default_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if text.is_empty() or text_size.x > box.size.x - 4.0 or text_size.y > box.size.y - 2.0:
		return Rect2()
	var at := box.get_center() - text_size * 0.5
	var used := Rect2(at, text_size)
	for t in taken:
		if t.intersects(used):
			return Rect2()
	var baseline := at + Vector2(0, font.get_ascent(font_size))
	if outline:
		_ink.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.92, 0.88, 0.76, 0.85))
	_ink.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	return used


func _draw_players() -> void:
	for p in get_tree().get_nodes_in_group("remote_players"):
		var body := p as Node3D
		if body == null:
			continue
		var at := world_to_screen(Vector2(body.global_position.x, body.global_position.z))
		var house := int(body.get("house")) if body.get("house") != null else 0
		var same := castle_map.view_storey_at(body.global_position) == storey
		var fill: Color = CharacterProfile.HOUSE_COLORS[clampi(house, 0, CharacterProfile.HOUSE_COLORS.size() - 1)]
		if not same:
			fill.a = 0.35
		_ink.draw_circle(at, 4.0, fill)
		_ink.draw_arc(at, 4.0, 0.0, TAU, 12, Color(INK, fill.a), 1.0)
	var me := _local_player()
	if me == null:
		return
	var at := world_to_screen(Vector2(me.global_position.x, me.global_position.z))
	var forward := _facing(me)
	var tip := at + forward * 9.0
	var left := at - forward * 5.0 + forward.orthogonal() * 6.0
	var right := at - forward * 5.0 - forward.orthogonal() * 6.0
	var arrow := PackedVector2Array([tip, left, at - forward * 2.0, right])
	_ink.draw_colored_polygon(arrow, Color(0.85, 0.15, 0.12))
	arrow.append(tip)
	_ink.draw_polyline(arrow, Color(1, 0.95, 0.85), 1.5)


func _local_player() -> Node3D:
	return get_tree().get_first_node_in_group("local_player") as Node3D


## Screen direction the local player looks (camera forward, else the body's).
func _facing(me: Node3D) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var fwd: Vector3 = -cam.global_basis.z if cam != null else -me.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	return flat.normalized() if flat.length() > 0.01 else Vector2.UP
