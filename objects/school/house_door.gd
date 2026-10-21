class_name HouseDoor
extends Node3D
## Door into a house area (common room, dormitory, house landing). Members of
## [member house] open it by interacting; everyone else is turned away. The
## house comes from the character's server profile (Player.house), so the
## client only compares; like puzzle doors, its state is local.
##
## The same oak leaves as CastleDoor (the second turned 180°, each its own
## AnimatableBody3D so the collision swings with it), each carrying the house
## house crest on both faces: one round emblem with an iron rim, split down the
## meeting line (the crest image is mapped across both halves), so it reads as
## a single crest while the door is shut and
## parts when it opens. The leaves swing toward the door's +Z side, which the
## generator turns into the house area.

signal opened()
signal closed()
signal refused(interactor: Node)

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "house_door"
## A warded gate turning someone away.
const REFUSE := preload("res://assets/audio/world/magic_door_refuse.wav")

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for objects outside the castle.
@export var object_id: String = ""

@export_range(0, 4) var house: int = 1
@export var open_angle_degrees: float = 90.0
@export var open_duration: float = 1.0
## How long the door stays open after a member passes.
@export var open_seconds: float = 6.0

var is_open: bool = false
var _tween: Tween
var _close_timer: SceneTreeTimer

@onready var _hinges: Array[Node3D] = [$HingeL, $HingeR]
@onready var _interactables: Array[Interactable] = [$HingeL/Interactable, $HingeR/Interactable]
@onready var _audio: AudioStreamPlayer3D = $Audio
@onready var _light: OmniLight3D = $CrestLight


const CREST_RADIUS := 0.34
const CREST_RIM := 0.05
const CREST_HEIGHT := 2.3
const CREST_THICKNESS := 0.025
## Leaf face (half the leaf's thickness) the crest sits on.
const LEAF_FACE := 0.07
const MEETING_X := 1.784
## Share of the crest image's half-width the field shows: the seal's outer
## ring, leaving the notches outside under the iron rim.
const CREST_IMAGE_RADIUS := 0.45

static var _rim_material: StandardMaterial3D

var _crest_fields: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_crests()
	for i in _interactables:
		i.prompt_text = "INTERACT_HOUSE_DOOR"
		i.interacted.connect(_on_interacted)
	_apply_house_visual()


func _apply_house_visual() -> void:
	var color := CharacterProfile.house_color(house)
	var crest := CharacterProfile.crest(house)
	var mat := StandardMaterial3D.new()
	if crest != null:
		# An enamel plate lit from within, like the plain field before it. Unshaded:
		# the crest light sits right in front of it and would wash the colours out.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = crest
		mat.albedo_color = Color(0.85, 0.85, 0.85)
	else:
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.5
		mat.metallic = 0.3
		mat.roughness = 0.4
	for field in _crest_fields:
		field.material_override = mat
	_light.light_color = color


## Half of the emblem on each leaf, front and back: a coloured field inside an iron rim.
func _build_crests() -> void:
	for i in 2:
		var side := 1.0 if i == 0 else -1.0   # the left leaf's meeting edge is at +x
		var hinge := _hinges[i]
		for face in [1.0, -1.0]:
			var z: float = face * (LEAF_FACE + CREST_THICKNESS / 2.0)
			var suffix := "Front" if face > 0.0 else "Back"
			var rim := MeshInstance3D.new()
			rim.name = "CrestRim" + suffix
			rim.mesh = _half_disc(CREST_RADIUS, side)
			rim.material_override = _get_rim_material()
			rim.position = Vector3(side * MEETING_X, CREST_HEIGHT, z)
			hinge.add_child(rim)
			var field := MeshInstance3D.new()
			field.name = "CrestField" + suffix
			field.mesh = _half_disc(CREST_RADIUS - CREST_RIM, side, face < 0.0)
			field.position = Vector3(side * MEETING_X, CREST_HEIGHT, z + face * 0.004)
			hinge.add_child(field)
			_crest_fields.append(field)


## A half disc of `radius` lying in the XY plane, toward -x (side 1) or +x (side -1)
## from the meeting line, CREST_THICKNESS thick. UVs place the crest image
## centred on the meeting line; `mirror` flips it for a field seen from -z.
static func _half_disc(radius: float, side: float, mirror: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	var half := CREST_THICKNESS / 2.0
	for k in steps:
		var a0 := PI / 2.0 + PI * k / steps
		var a1 := PI / 2.0 + PI * (k + 1) / steps
		var p0 := Vector3(side * cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(side * cos(a1) * radius, sin(a1) * radius, 0.0)
		if side < 0.0:
			var swap := p0   # mirroring flips the winding; keep front faces outward
			p0 = p1
			p1 = swap
		for zf in [half, -half]:
			var a := p0 if zf > 0.0 else p1
			var c := p1 if zf > 0.0 else p0
			st.set_normal(Vector3(0, 0, signf(zf)))
			for v: Vector3 in [Vector3.ZERO, c, a]:
				st.set_uv(_crest_uv(v, radius, mirror))
				st.add_vertex(v + Vector3(0, 0, zf))
		var n := ((p0 + p1) / 2.0).normalized()
		st.set_normal(n)
		for v: Vector3 in [p0 + Vector3(0, 0, half), p0 + Vector3(0, 0, -half), p1 + Vector3(0, 0, half),
				p1 + Vector3(0, 0, half), p0 + Vector3(0, 0, -half), p1 + Vector3(0, 0, -half)]:
			st.set_uv(_crest_uv(v, radius, mirror))
			st.add_vertex(v)
	return st.commit()


static func _crest_uv(p: Vector3, radius: float, mirror: bool) -> Vector2:
	var x := -p.x if mirror else p.x
	return Vector2(0.5 + x / radius * CREST_IMAGE_RADIUS, 0.5 - p.y / radius * CREST_IMAGE_RADIUS)


static func _get_rim_material() -> StandardMaterial3D:
	if _rim_material == null:
		_rim_material = StandardMaterial3D.new()
		_rim_material.albedo_color = Color(0.08, 0.08, 0.09)
		_rim_material.metallic = 0.8
		_rim_material.roughness = 0.45
		_rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rim_material


func admits(interactor: Node) -> bool:
	if interactor == null:
		return false
	return int(interactor.get("house")) == house or (interactor.is_in_group("local_player") and NetworkManager.has_guest_pass(house))


func _on_interacted(interactor: Node) -> void:
	if admits(interactor):
		# Members answer the riddle of the week first (online; guests with a pass do not).
		if interactor.is_in_group("local_player") and int(interactor.get("house")) == house and RiddlePanel.must_answer(house):
			GameEvents.panel_requested.emit("riddle", {"door": self})
			return
		open()
	else:
		refused.emit(interactor)
		Sfx.play_at(self, REFUSE, -4.0, 18.0, Vector3(0, 1.4, 0))
		if interactor.is_in_group("local_player"):
			GameEvents.notification_requested.emit(tr("NOTIFY_HOUSE_DOOR_LOCKED") % CharacterProfile.house_name(house), 4.0)


func open() -> void:
	_set_open(true)
	if _close_timer != null and _close_timer.timeout.is_connected(_on_close_timeout):
		_close_timer.timeout.disconnect(_on_close_timeout)
	_close_timer = get_tree().create_timer(open_seconds)
	_close_timer.timeout.connect(_on_close_timeout)


func close() -> void:
	_set_open(false)


func _on_close_timeout() -> void:
	if is_inside_tree():
		close()


func _set_open(value: bool) -> void:
	if is_open == value or not is_inside_tree():
		return
	is_open = value
	var angle := deg_to_rad(open_angle_degrees) if is_open else 0.0
	var targets := [-angle, angle]
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in 2:
		_tween.tween_property(_hinges[i], "rotation:y", targets[i], open_duration)
	_audio.play()
	if is_open:
		opened.emit()
	else:
		closed.emit()
