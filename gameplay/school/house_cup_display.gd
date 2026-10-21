class_name HouseCupDisplay
extends Node3D
## The house cup in the great hall: once a house holds it (OP_HOUSE_CUP), a golden cup
## stands on a plinth at the hall's north end under a banner in the holder's colour,
## with its name above. castle.gd adds it; it places itself from the great hall zone.

const HALL := &"great_hall"

var winner := 0
## Whether a cup state has been seen yet: the first one (joining) plays no fanfare.
var _seen := false
var _cup: Node3D
var _banner: Node3D
var _label: Label3D


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		var zone := node as AreaZone
		if zone.area_id == HALL:
			global_position = zone.global_position + Vector3(0, -zone.size.y / 2.0, -zone.size.z / 2.0 + 2.5)
	_build()
	NetworkManager.house_cup_changed.connect(show_cup)
	show_cup(NetworkManager.house_cup)


func _build() -> void:
	# A carved granite plinth (the pushable block's stone, scaled) and the golden cup.
	var plinth := (load("res://assets/models/environment/props5/pushable_block.glb") as PackedScene).instantiate() as Node3D
	plinth.scale = Vector3(1.0, 1.1, 1.0) / 1.44
	add_child(plinth)
	_cup = (load("res://assets/models/school/house_cup.glb") as PackedScene).instantiate() as Node3D
	_cup.position.y = 1.1
	add_child(_cup)
	_banner = Node3D.new()
	_banner.name = "Banner"
	_banner.position = Vector3(0, 0, -0.6)
	add_child(_banner)
	_label = Label3D.new()
	_label.position = Vector3(0, 2.3, 0)
	_label.font_size = 64
	_label.pixel_size = 0.004
	_label.outline_size = 14
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(_label)
	visible = false


func show_cup(cup: Dictionary) -> void:
	var before := winner
	winner = int(cup.get("winner", 0))
	# A house just won the cup: the fanfare (a one-shot event track) for everyone.
	if _seen and winner > 0 and winner != before:
		var music := get_tree().root.find_child("MusicDirector", true, false) as MusicDirector
		if music != null:
			music.event_track = &"house_cup"
	_seen = true
	visible = winner > 0
	if winner <= 0:
		return
	for child in _banner.get_children():
		child.queue_free()
	_banner.add_child(CharacterProfile.banner(winner, Vector3(0, 6.2, 0), 1.35))
	_label.text = tr("HOUSE_CUP_HOLDER") % CharacterProfile.house_name(winner)
	_label.modulate = CharacterProfile.house_color(winner).lightened(0.3)
	if cup.get("fresh", false):
		ceremony(winner)


## The ceremony when the cup is awarded live: confetti over the cup, the hall hung with the
## winners' colours for CEREMONY_SECONDS, and the cup's fanfare (the music director's event track).
const CEREMONY_SECONDS := 600.0
var ceremony_decor: Node3D


func ceremony(house: int) -> void:
	add_child(PotionEffects.confetti_burst(Vector3(0, 2.5, 0)))
	if ceremony_decor != null:
		ceremony_decor.queue_free()
	ceremony_decor = Node3D.new()
	ceremony_decor.name = "CeremonyBanners"
	for i in 8:
		ceremony_decor.add_child(CharacterProfile.banner(house, Vector3((i - 3.5) * 2.4, 6.8, 0.3), 1.2))
	add_child(ceremony_decor)
	var decor := ceremony_decor
	get_tree().create_timer(CEREMONY_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(decor):
			decor.queue_free())
