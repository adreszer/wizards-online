class_name ReverbDirector
extends Node
## Gives the castle's spaces their sound: every positional sound effect plays on the
## World bus (any AudioStreamPlayer3D left on Master is moved there as it enters the
## tree), and the World bus's reverb follows the kind of the area the local player
## stands in: a long tail in the great hall and the library, stone echo in corridors
## and towers, a close one in rooms, a damp one in hidden rooms, none outdoors or
## among the soft furnishings of common rooms, dormitories and shops. Changes glide
## over GLIDE seconds. Music, ambience beds and the interface keep their own buses.
## Added by castle.gd next to the MusicDirector.

const BUS := &"World"
## Reverb presets: room size, damping, wet level (dry stays at 1).
const PRESETS := {
	&"hall": {"room_size": 0.85, "damping": 0.35, "wet": 0.26},
	&"stone": {"room_size": 0.6, "damping": 0.45, "wet": 0.2},
	&"room": {"room_size": 0.32, "damping": 0.6, "wet": 0.1},
	&"cellar": {"room_size": 0.55, "damping": 0.25, "wet": 0.24},
	&"soft": {"room_size": 0.2, "damping": 0.85, "wet": 0.04},
	&"open": {"room_size": 0.1, "damping": 0.9, "wet": 0.0},
}
## AreaZone kind -> preset; kinds not listed are "room".
const KIND_PRESETS := {
	"hall": &"hall", "library": &"hall", "shaft": &"hall",
	"corridor": &"stone", "tower": &"stone", "stair_turret": &"stone", "classroom": &"stone",
	"secret": &"cellar",
	"common_room": &"soft", "dormitory": &"soft", "shop": &"soft", "inn": &"soft", "post_office": &"soft",
	"grounds": &"open", "outdoor": &"open", "bridge": &"open", "station": &"open",
}
const GLIDE := 1.5

## The local player's area, set when the local player spawns.
var tracker: AreaTracker
## The preset playing now (for tests).
var preset: StringName = &"open"

var _reverb: AudioEffectReverb
var _target: Dictionary = PRESETS[&"open"]


func _ready() -> void:
	_reverb = ensure_bus()
	get_tree().node_added.connect(_route)
	for node: Node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		_route(node)
	GameEvents.local_player_spawned.connect(func(player: Node) -> void: tracker = player.get("area_tracker"))
	GameEvents.local_player_removed.connect(func(_p: Node) -> void: tracker = null)


## The World bus (sending to Master) with its reverb, created on first use.
static func ensure_bus() -> AudioEffectReverb:
	var index := AudioServer.get_bus_index(BUS)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"Master")
	for i in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, i) is AudioEffectReverb:
			return AudioServer.get_bus_effect(index, i)
	var reverb := AudioEffectReverb.new()
	reverb.dry = 1.0
	reverb.wet = 0.0
	reverb.predelay_msec = 20.0
	reverb.hipass = 0.15
	AudioServer.add_bus_effect(index, reverb)
	return reverb


static func preset_for(kind: String) -> StringName:
	return KIND_PRESETS.get(kind, &"room")


func _route(node: Node) -> void:
	var player := node as AudioStreamPlayer3D
	if player != null and player.bus == &"Master":
		player.bus = BUS


func _process(delta: float) -> void:
	var zone := tracker.current_zone if tracker != null else null
	var want := preset_for(zone.kind) if zone != null else &"open"
	if want != preset:
		preset = want
		_target = PRESETS[want]
	var t := clampf(delta / GLIDE, 0.0, 1.0)
	_reverb.room_size = lerpf(_reverb.room_size, _target["room_size"], t)
	_reverb.damping = lerpf(_reverb.damping, _target["damping"], t)
	_reverb.wet = lerpf(_reverb.wet, _target["wet"], t)
