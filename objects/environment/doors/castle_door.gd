class_name CastleDoor
extends Node3D
## A pair of oak leaves hung in a doorway module (objects/environment/modular/
## doorway.tscn), one leaf mirrored from the other. Interacting opens or closes
## both; the leaves swing 90° toward the door's +Z side (the generator turns
## that side into the room). A `locked` door refuses to open until an `unlock`
## spell (Unbolt) hits it, which unlocks it and leaves it closed.
##
## In the shared world the state is server-authoritative like a lever's
## (object_rules.lua, kind "castle_door"): "locked", false (closed) or true
## (open). Offline the door acts on local triggers.

signal opened()
signal closed()
signal unlocked()

## Kind name in the server's world-object map (generated/world_objects.lua).
const WORLD_KIND := "castle_door"
const UNLOCKED := preload("res://assets/audio/world/lock_unlocked.wav")

## Stable id ("<area>/<name>") the server uses to refer to this object; set
## by the castle generator. Empty for doors outside the castle.
@export var object_id: String = ""
## Area on the other side of the door; players act on it from either.
@export var approach_area: String = ""
## Starts locked (and returns to locked when the server resets the world).
@export var locked: bool = false
## Starts open (a main route); players can still close it. Ignored when locked.
@export var start_open: bool = false
@export var open_angle_degrees: float = 90.0
@export var swing_duration: float = 0.9

var is_open: bool = false
var is_locked: bool = false
var _tween: Tween

## Leaf meshes imported without normals (some exports omit them), rebuilt once
## with generated normals and tangents so lighting and the normal map work.
static var _lit_meshes: Dictionary = {}

## Each hinge is the leaf's own AnimatableBody3D: a physics body only follows
## changes to its own transform, so rotating a parent would leave the
## collision shut while the leaf swings.
@onready var _hinges: Array[Node3D] = [$HingeL, $HingeR]
@onready var _interactables: Array[Interactable] = [$HingeL/Interactable, $HingeR/Interactable]
@onready var _receivers: Array[SpellReceiver] = [$HingeL/SpellReceiver, $HingeR/SpellReceiver]
@onready var _occluder: OccluderInstance3D = $Occluder
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		_ensure_normals(mi as MeshInstance3D)
	is_locked = locked
	for i in _interactables:
		i.interacted.connect(_on_interacted)
	for r in _receivers:
		r.spell_received.connect(_on_spell_received)
	if start_open and not locked:
		set_open(true, true)
	_update_prompt()


static func _ensure_normals(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0 or mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_NORMAL:
		return
	if not _lit_meshes.has(mesh):
		var out := ArrayMesh.new()
		for i in mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(mesh, i)
			st.generate_normals()
			st.generate_tangents()
			st.commit(out)
			out.surface_set_material(i, mesh.surface_get_material(i))
		_lit_meshes[mesh] = out
	mi.mesh = _lit_meshes[mesh]


func _on_interacted(interactor: Node) -> void:
	if is_locked:
		if interactor != null and interactor.is_in_group("local_player"):
			GameEvents.notification_requested.emit(tr("NOTIFY_DOOR_LOCKED"), 3.0)
		if WorldObjectSync.is_synced(self):
			WorldObjectSync.report(self, "interact")
		return
	if WorldObjectSync.request(self, "interact"):
		return
	set_open(not is_open)


func _on_spell_received(effect: SpellEffect) -> void:
	if effect.effect_type != &"unlock":
		return
	if WorldObjectSync.request(self, "spell", effect):
		return
	unlock()


func unlock() -> void:
	if not is_locked:
		return
	is_locked = false
	Sfx.play_at(self, UNLOCKED, -2.0, 20.0, Vector3(0, 1.2, 0))
	_update_prompt()
	unlocked.emit()


## Swings both leaves. `instant` (a late joiner's snapshot) snaps them without sound.
func set_open(value: bool, instant: bool = false) -> void:
	if is_open == value:
		return
	is_open = value
	var angle := deg_to_rad(open_angle_degrees) if is_open else 0.0
	var targets := [-angle, angle]   # left leaf swings clockwise seen from above, right leaf mirrors it
	if _tween != null:
		_tween.kill()
	if instant:
		for i in 2:
			_hinges[i].rotation.y = targets[i]
	else:
		_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		for i in 2:
			_tween.tween_property(_hinges[i], "rotation:y", targets[i], swing_duration)
		_audio.play()
	_occluder.visible = not is_open
	_update_prompt()
	if is_open:
		opened.emit()
	else:
		closed.emit()


## Server state: "locked", false (closed) or true (open); null means the
## default: locked for a door that starts locked, open for one that starts open.
func apply_world_state(state: Variant, instant: bool) -> void:
	# The state mixes types (String or bool), and comparing across them is an error.
	var lock: bool = (state is String and state == "locked") or (state == null and locked)
	if lock != is_locked:
		is_locked = lock
		if not lock and not instant:
			_audio.play()
			unlocked.emit()
	var open_now: bool = (state is bool and state) if state != null else (start_open and not locked)
	set_open(open_now, instant)
	_update_prompt()


func _update_prompt() -> void:
	var key := "INTERACT_DOOR_LOCKED" if is_locked else ("INTERACT_CLOSE_DOOR" if is_open else "INTERACT_OPEN_DOOR")
	for i in _interactables:
		i.prompt_text = key
