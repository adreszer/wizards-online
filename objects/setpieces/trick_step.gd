class_name TrickStep
extends Area3D
## A tread that gives way under a foot: whoever steps on it sinks to the knee and is held
## for `hold_seconds` unless they jump. Harmless, and remembered by everyone it caught once.
## Everyone near hears it give way and, a moment later, grind back up.

const DROP_SOUND := preload("res://assets/audio/world/trick_step_drop.wav")
const RESET_SOUND := preload("res://assets/audio/world/trick_step_reset.wav")

@export var hold_seconds: float = 1.8
@export var size: Vector3 = Vector3(0.5, 0.4, 3.0)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # player
	monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		Sfx.play_at(self, DROP_SOUND, -2.0, 25.0)
		get_tree().create_timer(hold_seconds).timeout.connect(func() -> void:
			if is_inside_tree():
				Sfx.play_at(self, RESET_SOUND, -4.0, 20.0))
	if body is Player and (body as Player).is_local:
		(body as Player).movement.hold(hold_seconds)
		GameEvents.notification_requested.emit(tr("NOTIFY_TRICK_STEP"), 2.5)
