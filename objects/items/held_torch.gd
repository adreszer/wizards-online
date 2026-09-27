class_name HeldTorch
extends Node3D
## Handheld torch: a wooden shaft with a cloth-wrapped head, a particle flame,
## drifting embers and a flickering OmniLight that lights the area around the
## carrier. Instantiated by HeldItemMount under the character's off-hand
## attachment. The hand bone sits at the wrist with its Y axis along the
## fingers, so the torch positions itself each frame: it moves the grip to the
## palm and orients itself from the *character's* facing (not the hand's), held
## upright with a forward/outward lean so the flame clears the shoulder even
## with the arm hanging at the side.

## Radius the torch lights up, in metres.
@export var light_radius: float = 9.0
@export var base_energy: float = 2.6
@export var flicker_amount: float = 0.18
@export var flicker_speed: float = 8.0
## Keep the torch upright (relative to the character) instead of following the
## hand bone's rotation.
@export var keep_upright: bool = true
## Distance from the wrist joint to the middle of the palm, along the fingers.
@export var palm_offset: float = 0.07
## Grip offset in the character's local frame (+X right, -Z forward).
@export var grip_offset: Vector3 = Vector3(-0.06, 0.0, -0.1)
## Lean of the shaft in degrees: forward (towards -Z) and outward (away from
## the body, i.e. to the character's left).
@export var lean_forward_deg: float = 28.0
@export var lean_outward_deg: float = 14.0

@onready var _light: OmniLight3D = $Flame
var _phase: float = randf() * TAU
var _character: Node3D


func _ready() -> void:
	_light.omni_range = light_radius
	_light.light_energy = base_energy
	# Run after the animation/skeleton update so the hand position is current.
	process_priority = 100
	_character = _find_character()
	_align()


func _process(delta: float) -> void:
	_align()
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.3 + 1.7) * 0.3 + sin(_phase * 5.1 + 0.4) * 0.2
	_light.light_energy = base_energy * (1.0 + n * flicker_amount)


## The body whose facing the torch follows: the CharacterBody3D above the
## hand socket, else the socket's top-level Node3D ancestor.
func _find_character() -> Node3D:
	var n: Node = get_parent()
	var last: Node3D = null
	while n != null:
		if n is CharacterBody3D:
			return n
		if n is Node3D:
			last = n
		n = n.get_parent()
	return last


func _align() -> void:
	if not keep_upright or not is_inside_tree():
		return
	var hand := get_parent() as Node3D
	if hand == null:
		return
	var palm := hand.global_position + hand.global_basis.y.normalized() * palm_offset
	var facing := Basis.IDENTITY
	if _character != null:
		facing = _character.global_basis.orthonormalized()
	var lean := Basis(Vector3.RIGHT, -deg_to_rad(lean_forward_deg)) * Basis(Vector3.FORWARD, -deg_to_rad(lean_outward_deg))
	global_transform = Transform3D(facing * lean, palm + facing * grip_offset)
