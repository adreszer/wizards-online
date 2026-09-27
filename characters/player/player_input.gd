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
## Hotbar slot pressed this frame (0-based), -1 = none.
var spell_slot_pressed: int = -1
## +1 / -1 when the next / previous spell action was pressed, 0 = none.
var spell_cycle: int = 0

const SLOT_ACTIONS: Array[StringName] = [
	&"spell_slot_1", &"spell_slot_2", &"spell_slot_3", &"spell_slot_4", &"spell_slot_5",
	&"spell_slot_6", &"spell_slot_7", &"spell_slot_8", &"spell_slot_9", &"spell_slot_10",
]

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
	for i in SLOT_ACTIONS.size():
		if Input.is_action_just_pressed(SLOT_ACTIONS[i]):
			spell_slot_pressed = i
	if Input.is_action_just_pressed("spell_next"):
		spell_cycle = 1
	elif Input.is_action_just_pressed("spell_prev"):
		spell_cycle = -1


func clear() -> void:
	move_axis = Vector2.ZERO
	sprint_held = false
	jump_held = false
	jump_just_pressed = false
	cast_just_pressed = false
	interact_just_pressed = false
	spell_slot_pressed = -1
	spell_cycle = 0


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


func consume_spell_slot() -> int:
	var v := spell_slot_pressed
	spell_slot_pressed = -1
	return v


func consume_spell_cycle() -> int:
	var v := spell_cycle
	spell_cycle = 0
	return v
