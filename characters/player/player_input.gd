class_name PlayerInput
extends Node
## Translates InputMap actions into a movement/action *intent* for the local player.
##
## Nothing here touches physics; PlayerMovement and the other components read
## the intent fields. Because only actions are read (never physical keys),
## gamepad bindings can be added in the InputMap without touching gameplay.
## When the UI captures the keyboard (chat) the intent is cleared and ignored.

## Raw 2D input in "screen" space: x = right, y = forward.
var move_axis: Vector2 = Vector2.ZERO
var sprint_held: bool = false
var jump_held: bool = false
var jump_just_pressed: bool = false
var cast_just_pressed: bool = false
var interact_just_pressed: bool = false

var enabled: bool = true


func _process(_delta: float) -> void:
	if not enabled or GameSession.ui_input_captured or get_tree().paused:
		clear()
		return
	move_axis = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	move_axis.y = -move_axis.y
	sprint_held = Input.is_action_pressed("sprint")
	jump_held = Input.is_action_pressed("jump")
	# "just pressed" flags accumulate until consumed so physics never misses them.
	if Input.is_action_just_pressed("jump"):
		jump_just_pressed = true
	if Input.is_action_just_pressed("cast"):
		cast_just_pressed = true
	if Input.is_action_just_pressed("interact"):
		interact_just_pressed = true


func clear() -> void:
	move_axis = Vector2.ZERO
	sprint_held = false
	jump_held = false
	jump_just_pressed = false
	cast_just_pressed = false
	interact_just_pressed = false


func consume_jump() -> bool:
	var v := jump_just_pressed
	jump_just_pressed = false
	return v


func consume_cast() -> bool:
	var v := cast_just_pressed
	cast_just_pressed = false
	return v


func consume_interact() -> bool:
	var v := interact_just_pressed
	interact_just_pressed = false
	return v
