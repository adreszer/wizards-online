class_name AnimationController
extends Node
## Drives an AnimationTree from coarse gameplay states.
##
## Gameplay code only ever calls [method set_movement_state] and
## [method play_cast]; the mapping from state names to animation inputs is
## data on this node, so swapping the placeholder animations for real ones
## never touches movement or spell code.

@export var animation_tree: AnimationTree
## Movement state name (from PlayerMovement.STATE_NAMES) -> transition input name.
@export var movement_state_map: Dictionary = {
	"idle": "idle", "walk": "walk", "run": "run", "jump": "jump", "fall": "fall", "land": "land",
}
@export var movement_transition_param: String = "parameters/Movement/transition_request"
@export var cast_oneshot_param: String = "parameters/Cast/request"

var current_state_name: String = "idle"


func _ready() -> void:
	if animation_tree != null:
		animation_tree.active = true


func set_movement_state(state: int, _old_state: int = -1) -> void:
	set_movement_state_name(PlayerMovement.STATE_NAMES[state])


func set_movement_state_name(state_name: String) -> void:
	if state_name == current_state_name:
		return
	current_state_name = state_name
	if animation_tree == null:
		return
	var input_name: String = str(movement_state_map.get(state_name, "idle"))
	animation_tree.set(movement_transition_param, input_name)


func play_cast() -> void:
	if animation_tree == null:
		return
	animation_tree.set(cast_oneshot_param, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
