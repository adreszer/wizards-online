extends Node3D
## Wires the greybox level's objects together. Objects expose signals and
## simple methods; this script holds only the level-specific puzzle logic.

@export var entrance_lever: Lever
@export var entrance_door: MagicDoor
@export var training_switch_a: MagicSwitch
@export var training_switch_b: MagicSwitch
@export var training_door: MagicDoor
@export var puzzle_switch: MagicSwitch
@export var puzzle_gate: MagicDoor
@export var puzzle_plate: PressurePlate
@export var puzzle_door: MagicDoor
@export var statue_puzzle: StatuePuzzle
@export var final_lever: Lever
@export var final_door: MagicDoor
@export var secret_wall: SecretWall


func _ready() -> void:
	entrance_lever.pulled.connect(entrance_door.open)
	training_switch_a.toggled.connect(_on_training_switch)
	training_switch_b.toggled.connect(_on_training_switch)
	puzzle_switch.activated.connect(puzzle_gate.open)
	puzzle_plate.activated.connect(puzzle_door.open)
	puzzle_plate.deactivated.connect(puzzle_door.close)
	statue_puzzle.solved.connect(_on_statues_solved)
	final_lever.toggled.connect(_on_final_lever)
	secret_wall.revealed.connect(func() -> void: GameEvents.notification_requested.emit("A hidden passage opens!", 4.0))
	GameEvents.checkpoint_activated.connect(func(_c: Node) -> void: GameEvents.notification_requested.emit("Checkpoint reached", 2.0))


func _on_training_switch(_is_on: bool) -> void:
	if training_switch_a.is_on and training_switch_b.is_on:
		training_door.open()


func _on_statues_solved() -> void:
	GameEvents.notification_requested.emit("The statues' gaze aligns. Something unlocked.", 4.0)


func _on_final_lever(is_on: bool) -> void:
	if not statue_puzzle.is_solved:
		GameEvents.notification_requested.emit("The lever will not budge while the statues look away.", 4.0)
		final_lever.reset()
		return
	final_door.set_open(is_on)
