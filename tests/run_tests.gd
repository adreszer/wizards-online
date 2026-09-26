extends Node
## Headless gameplay tests. Run:
##   godot --headless --path . tests/run_tests.tscn
## Builds small physics fixtures, spawns a local player and drives it through
## PlayerMovement's scripted-control API. Exit code 1 on any failure.

const PLAYER_SCENE := preload("res://characters/player/player.tscn")
const SWITCH_SCENE := preload("res://objects/puzzles/magic_switch.tscn")
const LEVER_SCENE := preload("res://objects/interactables/lever.tscn")
const COLLECTIBLE_SCENE := preload("res://gameplay/collectibles/collectible.tscn")
const PLATFORM_SCENE := preload("res://objects/platforms/moving_platform.tscn")
const CHECKPOINT_SCENE := preload("res://gameplay/checkpoints/checkpoint.tscn")
const LEVEL_SCENE := preload("res://levels/mvp/mvp_level.tscn")
const ARCANE_PULSE := preload("res://resources/spells/arcane_pulse.tres")
const TestHelpers := preload("res://tests/test_helpers.gd")

var t := TestHelpers.new()
var player: Player


func _ready() -> void:
	await _run()


func _run() -> void:
	await _test_movement()
	await _test_camera()
	await _test_health_and_checkpoints()
	await _test_collectibles()
	await _test_spell()
	await _test_interaction()
	await _test_moving_platform()
	await _test_level_wiring()
	print(t.summary())
	get_tree().quit(1 if t.failed > 0 else 0)


func _wait(seconds: float) -> void:
	var frames := int(ceil(seconds * Engine.physics_ticks_per_second))
	for i in range(frames):
		await get_tree().physics_frame


func _spawn_player(at: Vector3) -> Player:
	if player != null:
		player.queue_free()
		await get_tree().process_frame
	player = PLAYER_SCENE.instantiate()
	player.is_local = true
	player.display_name = "Tester"
	add_child(player)
	player.global_position = at
	player.respawn_handler.set_checkpoint(player.global_transform)
	await _wait(0.3)
	return player


func _clear(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame


# --- Movement ------------------------------------------------------------------

func _test_movement() -> void:
	t.section("Movement")
	var fixtures: Array = []
	fixtures.append(TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(60, 1, 60)))
	await _spawn_player(Vector3(0, 0.1, 0))
	t.check(player.movement.is_grounded, "player is grounded after spawn")
	t.check(player.movement.state == PlayerMovement.State.IDLE, "idle state when still")

	# Walk
	var start := player.global_position
	player.movement.set_external_move(Vector3(0, 0, -1), false)
	await _wait(1.0)
	var walked := start.distance_to(player.global_position)
	t.check(walked > 2.5 and walked < 5.0, "walking 1s moves ~walk_speed (%.2f m)" % walked)
	t.check(player.movement.state == PlayerMovement.State.WALK, "walk state while walking")
	t.check(absf(wrapf(player.rotation.y, -PI, PI)) < 0.2, "body faces movement direction")

	# Run
	start = player.global_position
	player.movement.set_external_move(Vector3(0, 0, -1), true)
	await _wait(1.0)
	var ran := start.distance_to(player.global_position)
	t.check(ran > walked * 1.3, "running is faster than walking (%.2f m)" % ran)
	t.check(player.movement.state == PlayerMovement.State.RUN, "run state while sprinting")

	# Decelerate
	player.movement.set_external_move(Vector3.ZERO)
	await _wait(0.5)
	t.check(player.movement.get_horizontal_speed() < 0.1, "decelerates to a stop")
	t.check(player.movement.state == PlayerMovement.State.IDLE, "returns to idle")

	# Jump
	var ground_y := player.global_position.y
	var jumped_signal := [false]
	var landed_signal := [false]
	player.movement.jumped.connect(func() -> void: jumped_signal[0] = true)
	player.movement.landed.connect(func(_s: float) -> void: landed_signal[0] = true)
	player.movement.request_jump()
	await _wait(0.2)
	t.check(jumped_signal[0], "jumped signal fires")
	t.check(player.global_position.y > ground_y + 0.5, "jump gains height")
	t.check(player.movement.state == PlayerMovement.State.JUMP, "jump state while ascending")
	var peak := player.global_position.y
	for i in range(30):
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	t.check(peak > ground_y + 1.0 and peak < ground_y + 2.0, "jump peak within forgiving range (%.2f m)" % (peak - ground_y))
	await _wait(0.8)
	t.check(player.movement.is_grounded and landed_signal[0], "lands and emits landed")

	# Slope: 30° ramp
	var ramp := TestHelpers.make_floor(self, Vector3(20, 0, 0), Vector3(12, 0.5, 6))
	ramp.rotation.z = deg_to_rad(30.0)
	ramp.global_position = Vector3(20, 3.0, 0)
	fixtures.append(ramp)
	player.global_position = Vector3(13.5, 0.1, 0)
	player.velocity = Vector3.ZERO
	await _wait(0.3)
	player.movement.set_external_move(Vector3(1, 0, 0), false)
	await _wait(1.5)
	t.check(player.global_position.y > 1.0 and player.movement.is_grounded, "walks up a 30° slope (pos=%s wall=%s)" % [player.global_position, player.is_on_wall()])
	player.movement.set_external_move(Vector3.ZERO)
	await _wait(0.5)
	t.check(player.movement.get_horizontal_speed() < 0.2, "stands still on the slope (no sliding)")

	# Stairs: 0.4 m steps
	player.global_position = Vector3(-10, 0.1, 0)
	player.velocity = Vector3.ZERO
	for i in range(3):
		fixtures.append(TestHelpers.make_floor(self, Vector3(-13 - i * 0.8, 0.2 * (i + 1), 0), Vector3(0.8, 0.4 * (i + 1), 4)))
	await _wait(0.3)
	player.movement.set_external_move(Vector3(-1, 0, 0), false)
	await _wait(1.5)
	t.check(player.global_position.y > 1.0, "climbs 0.4 m stairs without jumping (pos=%s wall=%s)" % [player.global_position, player.is_on_wall()])
	player.movement.set_external_move(Vector3.ZERO)
	await _clear(fixtures)


# --- Camera --------------------------------------------------------------------

func _test_camera() -> void:
	t.section("Camera")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	await _spawn_player(Vector3(0, 0.1, 0))
	var rig := player.camera_rig
	var yaw0 := rig.get_yaw()
	rig.apply_look_delta(Vector2(100, 0))
	t.check(absf(rig.get_yaw() - yaw0) > 0.1, "horizontal mouse motion rotates yaw")
	rig.apply_look_delta(Vector2(0, -100000))
	t.check(is_equal_approx(rig.pitch, deg_to_rad(rig.max_pitch_degrees)), "pitch clamps at max")
	rig.apply_look_delta(Vector2(0, 100000))
	t.check(is_equal_approx(rig.pitch, deg_to_rad(rig.min_pitch_degrees)), "pitch clamps at min")
	rig.apply_look_delta(Vector2(0, -100000 + 1000))
	# Camera collision: wall right behind the player.
	rig.yaw = 0.0
	rig.pitch = 0.0
	rig._apply_rotation()
	var wall := TestHelpers.make_floor(self, Vector3(0, 2, 1.2), Vector3(10, 6, 0.5))
	await _wait(0.5)
	var cam := rig.get_camera()
	var dist := cam.global_position.distance_to(player.global_position + Vector3.UP * rig.target_height)
	t.check(dist < rig.distance - 0.5, "spring arm shortens against a wall (%.2f < %.2f)" % [dist, rig.distance])
	t.check(cam.global_position.z < 1.2, "camera stays on the player's side of the wall")
	t.check(cam.current, "local camera is the current camera")
	await _clear([floor_body, wall])


# --- Health / checkpoints -------------------------------------------------------

func _test_health_and_checkpoints() -> void:
	t.section("Health & checkpoints")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	await _spawn_player(Vector3(0, 0.1, 0))
	var health := player.health
	health.apply_damage(30)
	t.check(health.current == 70, "damage reduces health")
	health.heal(10)
	t.check(health.current == 80, "heal restores health")
	var checkpoint := CHECKPOINT_SCENE.instantiate()
	add_child(checkpoint)
	checkpoint.global_position = Vector3(6, 0, 0)
	player.global_position = Vector3(6, 0.1, 0)
	await _wait(0.3)
	t.check(player.respawn_handler.last_checkpoint == checkpoint, "walking into a checkpoint stores it")
	player.global_position = Vector3(-8, 0.1, 0)
	await _wait(0.2)
	var died := [false]
	health.died.connect(func(_s: Node) -> void: died[0] = true)
	health.apply_damage(999)
	t.check(died[0] and health.is_dead, "lethal damage emits died")
	await _wait(player.respawn_handler.respawn_delay + 0.3)
	t.check(player.global_position.distance_to(Vector3(6, 0, 0)) < 0.5, "respawns at the checkpoint")
	t.check(health.current == health.max_health and not health.is_dead, "health restored on respawn")
	# Fall out of the world
	floor_body.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(6, -25, 0)
	await _wait(player.respawn_handler.respawn_delay + 0.4)
	t.check(player.global_position.y > -5.0, "falling below kill height respawns")
	await _clear([checkpoint])


# --- Collectibles -----------------------------------------------------------------

func _test_collectibles() -> void:
	t.section("Collectibles")
	GameSession.reset_collectibles()
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var c1 := COLLECTIBLE_SCENE.instantiate()
	var c2 := COLLECTIBLE_SCENE.instantiate()
	add_child(c1)
	add_child(c2)
	c1.global_position = Vector3(3, 0, 0)
	c2.global_position = Vector3(-3, 0, 0)
	await get_tree().process_frame
	t.check(GameSession.get_total(&"arcane_fragment") == 2, "collectibles register their total")
	await _spawn_player(Vector3(3, 0.1, 0))
	await _wait(0.3)
	t.check(GameSession.get_collected(&"arcane_fragment") == 1, "touching a collectible increments the counter")
	t.check(not c1.try_collect(), "a collectible cannot be collected twice")
	t.check(GameSession.get_collected(&"arcane_fragment") == 1, "counter unchanged after double collect")
	await _clear([floor_body, c1, c2])


# --- Spell -------------------------------------------------------------------------

func _test_spell() -> void:
	t.section("Spell")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	await _spawn_player(Vector3(0, 0.1, 0))
	var caster := player.spell_caster
	t.check(not caster.try_cast(), "cannot cast before learning a spell")
	caster.learn_spell(ARCANE_PULSE)
	t.check(caster.equipped_spell == ARCANE_PULSE, "learn_spell equips the spell")

	var aim := TestHelpers.FixedAim.new()
	add_child(aim)
	caster.aim_source = aim
	var switch := SWITCH_SCENE.instantiate()
	add_child(switch)
	switch.global_position = Vector3(0, 0, -8)
	await get_tree().process_frame
	aim.origin = Vector3(0, 1.3, 2)
	aim.target = Vector3(0, 1.3, -8)
	t.check(caster.try_cast(), "cast succeeds with a target in range")
	t.check(not caster.try_cast(), "second cast blocked by cooldown")
	await _wait(0.8)
	t.check(switch.is_on, "switch activates when the projectile hits its receiver")

	# Slightly off-centre aim should still hit thanks to aim assist
	var switch2 := SWITCH_SCENE.instantiate()
	add_child(switch2)
	switch2.global_position = Vector3(0, 0, -10)
	switch.queue_free()
	await get_tree().process_frame
	aim.target = Vector3(0.9, 1.3, -10)
	caster.try_cast()
	await _wait(0.8)
	t.check(switch2.is_on, "aim assist snaps a near miss onto a receiver")

	# Invalid target: plain wall has no receiver, nothing happens and projectile is gone
	var wall := TestHelpers.make_floor(self, Vector3(0, 2, -6), Vector3(10, 4, 0.5))
	var switch3 := SWITCH_SCENE.instantiate()
	add_child(switch3)
	switch3.global_position = Vector3(0, 0, -12)
	await get_tree().process_frame
	aim.target = Vector3(0, 1.3, -12)
	caster.try_cast()
	await _wait(0.8)
	t.check(not switch3.is_on, "a receiver behind a wall is not affected")
	t.check(get_tree().get_nodes_in_group("spell_receivers").size() >= 1, "receivers remain registered")
	wall.queue_free()
	await get_tree().process_frame

	# Range: target beyond spell range is not reached
	var far := SWITCH_SCENE.instantiate()
	add_child(far)
	far.global_position = Vector3(0, 0, -(ARCANE_PULSE.range + 8.0))
	await get_tree().process_frame
	aim.target = Vector3(0, 1.3, -(ARCANE_PULSE.range + 8.0))
	caster.try_cast()
	await _wait(1.5)
	t.check(not far.is_on, "targets beyond range are not affected")
	t.check(get_tree().get_nodes_in_group("spell_receivers").size() > 0 and _count_projectiles() == 0, "projectile despawns after max range")
	await _clear([floor_body, switch2, switch3, far, aim])


func _count_projectiles() -> int:
	var n := 0
	for child in get_children():
		if child is SpellProjectile:
			n += 1
	return n


# --- Interaction ---------------------------------------------------------------------

func _test_interaction() -> void:
	t.section("Interaction")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	await _spawn_player(Vector3(0, 0.1, 0))
	var aim := TestHelpers.FixedAim.new()
	add_child(aim)
	var ic := player.interaction_controller
	ic.aim_source = aim
	var lever_near := LEVER_SCENE.instantiate()
	var lever_far := LEVER_SCENE.instantiate()
	add_child(lever_near)
	add_child(lever_far)
	lever_near.global_position = Vector3(0, 0, -1.8)
	lever_far.global_position = Vector3(0, 0, 1.8)
	aim.origin = Vector3(0, 1.3, 0)
	aim.target = Vector3(0, 1.0, -1.8)
	await _wait(0.3)
	t.check(ic.focused != null and ic.focused.get_parent() == lever_near, "looked-at lever is focused")
	var focus_events := [0]
	ic.focus_changed.connect(func(_i: Interactable) -> void: focus_events[0] += 1)
	aim.target = Vector3(0, 1.0, 1.8)
	await _wait(0.3)
	t.check(ic.focused != null and ic.focused.get_parent() == lever_far, "turning around focuses the other lever")
	t.check(focus_events[0] == 1, "focus_changed fires once per change")
	t.check(ic.try_interact(), "interact triggers the focused lever")
	t.check(lever_far.is_on, "lever toggled on")
	t.check(not ic.try_interact(), "one-shot lever cannot be pulled again")
	aim.target = Vector3(6, 1.0, 0)
	await _wait(0.3)
	t.check(ic.focused == null, "nothing focused when looking away")
	await _clear([floor_body, lever_near, lever_far, aim])


# --- Moving platform --------------------------------------------------------------------

func _test_moving_platform() -> void:
	t.section("Moving platform")
	var platform := PLATFORM_SCENE.instantiate()
	platform.points = [Vector3(6, 0, 0)] as Array[Vector3]
	platform.speed = 3.0
	platform.pause_at_points = 0.0
	add_child(platform)
	platform.global_position = Vector3(0, 0, 0)
	await get_tree().process_frame
	await _spawn_player(Vector3(0, 0.6, 0))
	await _wait(0.4)
	t.check(player.movement.is_grounded, "player stands on the platform")
	var before := player.global_position.x
	await _wait(1.0)
	var carried := player.global_position.x - before
	t.check(carried > 2.0, "platform carries the player (%.2f m in 1 s)" % carried)
	t.check(absf(player.global_position.x - platform.global_position.x) < 0.5, "player stays centred on the platform")
	await _clear([platform])


# --- Level wiring ------------------------------------------------------------------------

func _test_level_wiring() -> void:
	t.section("Level wiring")
	GameSession.reset_collectibles()
	var level := LEVEL_SCENE.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(GameSession.get_total(&"arcane_fragment") == 11, "level registers 11 fragments (got %d)" % GameSession.get_total(&"arcane_fragment"))
	var entrance_door: MagicDoor = level.get_node("EntranceDoor")
	var lever: Lever = level.get_node("EntranceLever")
	lever.get_node("Interactable").interact(self)
	t.check(entrance_door.is_open, "entrance lever opens the entrance door")
	var sa: MagicSwitch = level.get_node("TrainingSwitchA")
	var sb: MagicSwitch = level.get_node("TrainingSwitchB")
	var tdoor: MagicDoor = level.get_node("TrainingDoor")
	sa.set_on(true)
	t.check(not tdoor.is_open, "training door needs both switches")
	sb.set_on(true)
	t.check(tdoor.is_open, "both training switches open the training door")
	var ps: MagicSwitch = level.get_node("PuzzleSwitch")
	var gate: MagicDoor = level.get_node("PuzzleGate")
	ps.set_on(true)
	t.check(gate.is_open, "puzzle switch opens the inner gate")
	var plate: PressurePlate = level.get_node("PressurePlate")
	var pdoor: MagicDoor = level.get_node("PuzzleDoor")
	var block: PushableBlock = level.get_node("PushableBlock")
	block.global_position = plate.global_position + Vector3(0, 1.0, 0)
	await _wait(0.6)
	t.check(plate.is_active, "block on the pressure plate activates it")
	t.check(pdoor.is_open, "pressure plate opens the puzzle door")
	var sp: StatuePuzzle = level.get_node("StatuePuzzle")
	var final_lever: Lever = level.get_node("FinalLever")
	var final_door: MagicDoor = level.get_node("FinalDoor")
	final_lever.get_node("Interactable").interact(self)
	await _wait(0.1)
	t.check(not final_door.is_open and not final_lever.is_on, "final lever refuses while statues are wrong")
	for i in range(3):
		var statue: RotatingStatue = level.get_node("Statue%d" % (i + 1))
		while statue.state != 0:
			statue.advance()
	t.check(sp.is_solved, "statues in required states solve the puzzle")
	final_lever.get_node("Interactable").interact(self)
	t.check(final_door.is_open, "final lever opens the final door once solved")
	var secret: SecretWall = level.get_node("SecretWall")
	var effect := SpellEffect.create(ARCANE_PULSE, self, "", Vector3.ZERO, Vector3.FORWARD)
	secret.get_node("Ornament/SpellReceiver").receive(effect)
	t.check(secret.is_revealed, "spell on the ornament reveals the secret room")
	var completed := [false]
	GameEvents.level_completed.connect(func() -> void: completed[0] = true)
	await _spawn_player(level.get_node("LevelEnd").global_position + Vector3(0, -1.2, 0))
	await _wait(0.3)
	t.check(completed[0], "reaching the reward room completes the level")
	level.queue_free()
	await get_tree().process_frame
