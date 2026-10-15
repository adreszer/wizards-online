class_name Minimap
extends CanvasLayer
## Bottom-right minimap: a MapView that follows the local player, north up,
## on the storey they stand on (the ground floor outdoors), zoomed in indoors
## and out on the grounds. Below it the name of the place and the storey.
## Display only: it never takes the mouse or the keyboard.

const INDOOR_ZOOM := 2.4
const OUTDOOR_ZOOM := 0.7

@onready var _root: Control = %Root
@onready var _view: MapView = %View
@onready var _place: Label = %PlaceLabel

var castle_map: CastleMap


func _ready() -> void:
	_root.visible = false


func set_map(map: CastleMap) -> void:
	castle_map = map
	_view.castle_map = map
	_root.visible = map != null and not map.rooms.is_empty()


func _process(delta: float) -> void:
	if castle_map == null or not _root.visible:
		return
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me == null:
		return
	var pos := me.global_position
	var indoors := not castle_map.room_at(pos).is_empty()
	_view.centre = Vector2(pos.x, pos.z)
	_view.storey = castle_map.view_storey_at(pos)
	_view.pixels_per_metre = lerpf(_view.pixels_per_metre, INDOOR_ZOOM if indoors else OUTDOOR_ZOOM, clampf(delta * 3.0, 0.0, 1.0))
	_view.refresh()
	var place := castle_map.place_name_at(pos)
	var floor_name := MapView.storey_name(_view.storey) if indoors else tr("MAP_OUTDOORS")
	_place.text = "%s · %s" % [place, floor_name] if not place.is_empty() else floor_name
