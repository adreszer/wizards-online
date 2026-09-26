class_name StatuePuzzle
extends Node
## Solved when every listed RotatingStatue is in its required state.

signal solved()
signal unsolved()

@export var statues: Array[RotatingStatue] = []
@export var required_states: Array[int] = []
@export var lock_when_solved: bool = true

var is_solved: bool = false


func _ready() -> void:
	for statue in statues:
		statue.state_changed.connect(_on_statue_changed)
	call_deferred("_evaluate")


func _on_statue_changed(_state: int) -> void:
	_evaluate()


func _evaluate() -> void:
	var ok := statues.size() == required_states.size() and not statues.is_empty()
	for i in range(mini(statues.size(), required_states.size())):
		if statues[i].state != required_states[i]:
			ok = false
			break
	if ok == is_solved:
		return
	is_solved = ok
	if ok:
		solved.emit()
		if lock_when_solved:
			for statue in statues:
				var receiver := statue.get_node_or_null("SpellReceiver") as SpellReceiver
				if receiver != null:
					receiver.enabled = false
	else:
		unsolved.emit()
