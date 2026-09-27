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
## Movement states whose clips must loop. Imported GLB clips default to play-once and the
## per-file loop setting lives in gitignored .import files, so it is enforced here at runtime.
@export var looping_states: Array[String] = ["idle", "walk", "run", "fall"]

var current_state_name: String = "idle"


func _ready() -> void:
	if animation_tree != null:
		_ensure_loops()
		animation_tree.active = true


## Marks the clips behind [member looping_states] as looping. Resolves each state to the
## AnimationNodeAnimation named after it in the root blend tree (Idle, Walk, ...).
func _ensure_loops() -> void:
	var blend_tree := animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null or animation_tree.anim_player.is_empty():
		return
	var player := animation_tree.get_node_or_null(animation_tree.anim_player) as AnimationPlayer
	if player == null:
		return
	for state_name in looping_states:
		var node_name: String = state_name.capitalize()
		if not blend_tree.has_node(node_name):
			continue
		var anim_node := blend_tree.get_node(node_name) as AnimationNodeAnimation
		if anim_node == null or not player.has_animation(anim_node.animation):
			continue
		var anim := player.get_animation(anim_node.animation)
		if anim.loop_mode == Animation.LOOP_NONE:
			anim.loop_mode = Animation.LOOP_LINEAR


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
