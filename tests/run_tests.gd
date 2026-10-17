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
const CASTLE_SCENE := preload("res://levels/castle/castle.tscn")
const ARCANE_PULSE := preload("res://resources/spells/arcane_pulse.tres")
const TORCH := preload("res://resources/items/torch.tres")
const BROOM := preload("res://resources/items/broom.tres")
const BROOM_RACK_SCENE := preload("res://objects/interactables/broom_rack.tscn")
const AREA_ZONE_SCENE := preload("res://gameplay/world/area_zone.tscn")
const CHAT_PANEL_SCENE := preload("res://ui/chat/chat_panel.tscn")
const INVENTORY_PANEL_SCENE := preload("res://ui/inventory/inventory_panel.tscn")
const BLOCK_SCENE := preload("res://objects/puzzles/pushable_block.tscn")
const WALL_TORCH_SCENE := preload("res://objects/environment/props/wall_torch.tscn")
const CASTLE_DOOR_SCENE := preload("res://objects/environment/doors/castle_door.tscn")
const GRAND_DOOR_SCENE := preload("res://objects/environment/doors/castle_door_ceremonial.tscn")
const UNBOLT := preload("res://resources/spells/unbolt.tres")
const HUD_SCENE := preload("res://ui/hud/hud.tscn")
const PROFESSOR_PANEL_SCENE := preload("res://ui/school/professor_panel.tscn")
const SORTING_PANEL_SCENE := preload("res://ui/school/sorting_panel.tscn")
const HOUSE_DOOR_SCENE := preload("res://objects/school/house_door.tscn")
const SORTING_STONE_SCENE := preload("res://objects/school/sorting_stone.tscn")
const HOUSE_TALLY_SCENE := preload("res://objects/school/house_tally.tscn")
const GUARDIAN_SCENE := preload("res://characters/enemies/crystal_guardian.tscn")
const SECRET_WALL_SCENE := preload("res://objects/puzzles/secret_wall.tscn")
const STATUE_SCENE := preload("res://objects/puzzles/rotating_statue.tscn")
const DOOR_SCENE := preload("res://objects/puzzles/magic_door.tscn")
const MINIMAP_SCENE := preload("res://ui/map/minimap.tscn")
const MAP_PANEL_SCENE := preload("res://ui/map/map_panel.tscn")
const TestHelpers := preload("res://tests/test_helpers.gd")

var t := TestHelpers.new()
var player: Player


func _ready() -> void:
	await _run()


func _run() -> void:
	# `-- --only=castle` runs one section (any _test_<name>), for quick iteration.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			var method := "_test_" + arg.get_slice("=", 1)
			if has_method(method):
				await call(method)
			print(t.summary())
			get_tree().quit(1 if t.failed > 0 else 0)
			return
	await _test_movement()
	await _test_camera()
	await _test_health_and_checkpoints()
	await _test_enemy()
	await _test_collectibles()
	await _test_spell()
	await _test_spellbook()
	await _test_spell_effects()
	await _test_school()
	await _test_houses()
	await _test_inventory()
	await _test_flying()
	await _test_interaction()
	await _test_moving_platform()
	await _test_level_wiring()
	await _test_castle()
	await _test_grounds()
	await _test_village()
	_test_currency()
	await _test_map()
	await _test_setpieces()
	await _test_day_night()
	await _test_timetable()
	await _test_chat()
	await _test_gestures()
	await _test_board_and_quiz()
	await _test_practicals()
	_test_self_study()
	await _test_character_look()
	await _test_meals()
	await _test_mastery()
	_test_runes()
	_test_journal()
	_test_grades()
	await _test_books()
	await _test_prefects()
	_test_localization()
	await _test_characters()
	_test_server_content()
	await _test_world_objects()
	_test_mysteries()
	print(t.summary())
	get_tree().quit(1 if t.failed > 0 else 0)


func _wait(seconds: float) -> void:
	var frames := int(ceil(seconds * Engine.physics_ticks_per_second))
	for i in range(frames):
		await get_tree().physics_frame


func _spawn_player(at: Vector3, character_id: String = "") -> Player:
	if player != null:
		player.queue_free()
		await get_tree().process_frame
	player = PLAYER_SCENE.instantiate()
	player.is_local = true
	player.character_id = character_id
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
	var peak_y := 0.0
	for i in range(45):
		await get_tree().physics_frame
		peak_y = maxf(peak_y, player.global_position.y)
		if peak_y > 1.5:
			break
	t.check(peak_y > 1.0, "walks up a 30° slope (peak y=%.2f)" % peak_y)
	player.movement.set_external_move(Vector3.ZERO)
	await _wait(0.5)
	t.check(player.movement.is_grounded and player.movement.get_horizontal_speed() < 0.2, "stands still on the slope (no sliding)")

	# Stairs: 0.4 m steps
	player.global_position = Vector3(-10, 0.1, 0)
	player.velocity = Vector3.ZERO
	for i in range(3):
		fixtures.append(TestHelpers.make_floor(self, Vector3(-13 - i * 0.8, 0.2 * (i + 1), 0), Vector3(0.8, 0.4 * (i + 1), 4)))
	await _wait(0.3)
	player.movement.set_external_move(Vector3(-1, 0, 0), false)
	var stair_peak := 0.0
	var visual_peak := 0.0
	var visual_dipped := false
	var max_mesh_step := 0.0
	var prev_mesh_x := player.visual.global_position.x
	var kept_walking := true
	for i in range(120):
		await get_tree().physics_frame
		if i > 5:
			max_mesh_step = maxf(max_mesh_step, absf(player.visual.global_position.x - prev_mesh_x))
			if player.movement.get_state_name() != "walk":
				kept_walking = false
		prev_mesh_x = player.visual.global_position.x
		stair_peak = maxf(stair_peak, player.global_position.y)
		visual_peak = maxf(visual_peak, player.visual.global_position.y)
		if player.visual.position.y < -0.1:
			visual_dipped = true
		if stair_peak > 1.1:
			break
	t.check(stair_peak > 1.0, "climbs 0.4 m stairs without jumping (peak y=%.2f)" % stair_peak)
	t.check(visual_dipped, "mesh eases up each step instead of popping with the body")
	t.check(visual_peak < stair_peak - 0.05, "mesh trails the body during the climb (%.2f < %.2f)" % [visual_peak, stair_peak])
	var walk_tick := player.movement.walk_speed / 60.0
	t.check(max_mesh_step < walk_tick * 2.0, "mesh never lurches while climbing (max %.3f m/tick, walk %.3f)" % [max_mesh_step, walk_tick])
	t.check(kept_walking, "walk animation state holds through the climb")
	player.movement.set_external_move(Vector3.ZERO)
	await _wait(0.5)
	t.check(player.visual.position.length() < 0.01, "mesh settles back onto the body after the stairs")
	# Back down the same stairs: stay grounded, no fall/land animation, mesh eases down.
	var left_floor := false
	var visual_rose := false
	var bottom_reached := false
	var start_x := player.global_position.x
	var ticks := 0
	max_mesh_step = 0.0
	prev_mesh_x = player.visual.global_position.x
	player.movement.set_external_move(Vector3(1, 0, 0), false)
	for i in range(120):
		await get_tree().physics_frame
		ticks += 1
		if i > 5:
			max_mesh_step = maxf(max_mesh_step, absf(player.visual.global_position.x - prev_mesh_x))
		prev_mesh_x = player.visual.global_position.x
		if not player.movement.is_grounded or player.movement.state in [PlayerMovement.State.FALL, PlayerMovement.State.LAND]:
			left_floor = true
		if player.visual.position.y > 0.1:
			visual_rose = true
		if player.global_position.y < 0.2 and player.global_position.x > -10.5:
			bottom_reached = true
			break
	t.check(bottom_reached, "walks back down the stairs (y=%.2f)" % player.global_position.y)
	t.check(not left_floor, "stays grounded going down 0.4 m steps (no fall animation)")
	t.check(visual_rose, "mesh eases down each step instead of dropping with the body")
	var avg_speed := (player.global_position.x - start_x) / (ticks / 60.0)
	t.check(avg_speed < player.movement.walk_speed * 1.1, "descending does not speed you up (avg %.2f m/s, walk %.2f)" % [avg_speed, player.movement.walk_speed])
	t.check(max_mesh_step < walk_tick * 2.0, "mesh never lurches while descending (max %.3f m/tick)" % max_mesh_step)
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
	# The headless display server has no cursor capture, so only assert the mode on a real one.
	var headless := DisplayServer.get_name() == "headless"
	t.check(rig.is_mouse_looking() and (headless or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "mouse look is on by default")
	var yaw_before := rig.get_yaw()
	rig._unhandled_input(_mouse_motion(Vector2(50, 0)))
	t.check(absf(rig.get_yaw() - yaw_before) > 0.05, "mouse movement turns the camera without holding a button")
	GameSession.ui_input_captured = true
	await _wait(0.05)
	t.check(not rig.is_mouse_looking() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "an open UI panel frees the cursor")
	yaw_before = rig.get_yaw()
	rig._unhandled_input(_mouse_motion(Vector2(50, 0)))
	t.check(is_equal_approx(rig.get_yaw(), yaw_before), "mouse movement over a UI panel leaves the camera alone")
	GameSession.ui_input_captured = false
	await _wait(0.05)
	t.check(rig.is_mouse_looking(), "closing the panel resumes mouse look")
	rig._unhandled_input(_action_press("toggle_cursor"))
	t.check(not rig.is_mouse_looking() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "F1 frees the cursor")
	rig._unhandled_input(_action_press("toggle_cursor"))
	t.check(rig.is_mouse_looking(), "F1 again resumes mouse look")
	var backquote := InputEventKey.new()
	backquote.physical_keycode = KEY_QUOTELEFT
	t.check(InputMap.event_is_action(backquote, "toggle_cursor"), "the ` key also frees the cursor (Mac F1 needs Fn)")
	rig._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	t.check(not rig.is_mouse_looking() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "losing window focus frees the cursor")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	rig._unhandled_input(click)
	t.check(rig.is_mouse_looking(), "clicking back into the window resumes mouse look")
	var dist_before: float = rig.distance
	rig.zoom_by(-rig.zoom_step)
	await _wait(0.6)
	t.check(rig.distance < dist_before - 0.3, "scroll wheel zooms the camera in (%.2f -> %.2f)" % [dist_before, rig.distance])
	rig.zoom_by(-1000.0)
	await _wait(0.6)
	t.check(is_equal_approx(rig.distance, rig.min_distance), "zoom clamps at min distance")
	rig.zoom_by(1000.0)
	await _wait(0.8)
	t.check(is_equal_approx(rig.distance, rig.max_distance), "zoom clamps at max distance")
	rig.set_distance(dist_before)
	await _clear([floor_body, wall])


func _action_press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.relative = relative
	return ev


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


# --- Enemies ----------------------------------------------------------------------

func _test_enemy() -> void:
	t.section("Enemy")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	await _spawn_player(Vector3(0, 0.1, 0))
	var enemy: Enemy = GUARDIAN_SCENE.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(0, 0.05, -30)
	await _wait(0.4)
	t.check(enemy.state_name() == "idle", "a guardian far from the player stays idle (%s)" % enemy.state_name())
	t.check(enemy.health.current == enemy.health.max_health, "guardian starts at full health")
	t.check(enemy.get_meta("health") == enemy.health and SpellReceiver.find_on(enemy) == enemy.spell_receiver, "guardian exposes health and a spell receiver")
	t.check(enemy.nameplate.text == tr("ENEMY_CRYSTAL_GUARDIAN_NAME") and not enemy.nameplate.text.begins_with("ENEMY_"), "guardian nameplate is translated")

	# Walk into detection range: alert -> chase -> attack lands on the player.
	player.global_position = Vector3(0, 0.1, -22)
	var noticed := [false]
	enemy.target_acquired.connect(func(_target: Node3D) -> void: noticed[0] = true)
	await _wait(0.4)
	t.check(noticed[0] and enemy.state_name() == "alert", "guardian notices a player within detection range (%s)" % enemy.state_name())
	var start_health := player.health.current
	var swung := [false]
	enemy.attacked.connect(func(_target: Node3D, _hit: bool) -> void: swung[0] = true)
	var waited := 0.0
	while player.health.current == start_health and waited < 8.0:
		await _wait(0.25)
		waited += 0.25
	t.check(swung[0], "guardian chases and swings at the player")
	t.check(player.health.current == start_health - enemy.attack_damage, "the blow deals attack_damage (%d -> %d)" % [start_health, player.health.current])
	t.check(enemy.global_position.distance_to(player.global_position) < enemy.attack_range * 1.5, "guardian closed the distance before striking")

	# Every third blow on a close target is the ground stomp (area damage).
	var stomp_hits := [-1]
	enemy.stomped.connect(func(count: int) -> void: stomp_hits[0] = count)
	waited = 0.0
	while stomp_hits[0] < 0 and waited < 12.0:
		await _wait(0.25)
		waited += 0.25
	t.check(stomp_hits[0] == 1, "the third strike is a ground stomp that catches the player (%d)" % stomp_hits[0])
	t.check(player.health.current == start_health - 2 * enemy.attack_damage - enemy.stomp_damage, "two swings and a stomp add up (%d)" % player.health.current)

	# Shield block: a spell from the front while chasing is parried for a quarter of its damage.
	player.global_position = Vector3(0, 0.1, -16)
	waited = 0.0
	while enemy.state_name() != "chase" and waited < 5.0:  # the current clip finishes first
		await _wait(0.1)
		waited += 0.1
	t.check(enemy.state_name() == "chase", "guardian chases a player who backs off (%s)" % enemy.state_name())
	enemy.block_chance = 1.0
	var parried := [false]
	enemy.blocked.connect(func(_e: SpellEffect) -> void: parried[0] = true)
	var hp_before_block := enemy.health.current
	enemy.spell_receiver.receive(SpellEffect.create(ARCANE_PULSE, player, "", enemy.global_position, Vector3.FORWARD))
	t.check(parried[0] and enemy.state_name() == "block", "guardian raises its shield against a spell from the front (%s)" % enemy.state_name())
	t.check(enemy.health.current == hp_before_block - int(round(enemy.spell_damage[&"force"] * enemy.block_damage_factor)), "a blocked spell deals reduced damage (%d -> %d)" % [hp_before_block, enemy.health.current])
	await _wait(enemy.block_duration + 0.3)
	t.check(enemy.state_name() == "chase", "guardian lowers the shield and resumes the chase (%s)" % enemy.state_name())
	enemy.block_chance = 0.0

	# Spells hurt it: direct effect, then a real projectile from the player.
	var before := enemy.health.current
	var effect := SpellEffect.create(ARCANE_PULSE, player, "", enemy.global_position, Vector3.FORWARD)
	enemy.spell_receiver.receive(effect)
	t.check(enemy.health.current == before - int(enemy.spell_damage[&"force"]), "a force spell damages the guardian (%d -> %d)" % [before, enemy.health.current])
	player.global_position = Vector3(0, 0.1, -12)
	enemy.global_position = Vector3(0, 0.05, -20)
	enemy.respawn_delay = 1.0
	await _wait(0.2)
	var caster := player.spell_caster
	caster.learn_spell(ARCANE_PULSE)
	var aim := TestHelpers.FixedAim.new()
	add_child(aim)
	caster.aim_source = aim
	aim.origin = Vector3(0, 1.3, -10)
	aim.target = enemy.spell_receiver.get_aim_point()
	before = enemy.health.current
	t.check(caster.try_cast(), "player can cast at the guardian")
	await _wait(0.8)
	t.check(enemy.health.current < before, "the projectile hits the guardian's body (%d -> %d)" % [before, enemy.health.current])

	# Death shatters it, then it comes back at its post.
	var died := [false]
	enemy.died.connect(func() -> void: died[0] = true)
	enemy.health.apply_damage(999, player)
	await _wait(0.9)
	t.check(died[0] and enemy.state_name() == "dead", "lethal damage kills the guardian")
	t.check(enemy.collision_layer == 0 and not enemy.visible, "a dead guardian is gone from the world")
	t.check(enemy.global_position.y > -0.5, "a dead guardian does not fall through the floor (y=%.2f)" % enemy.global_position.y)
	var hp_at_death := player.health.current
	await _wait(0.5)
	t.check(player.health.current == hp_at_death, "a dead guardian stops attacking")
	await _wait(enemy.respawn_delay + 1.0)
	t.check(enemy.state_name() != "dead" and enemy.visible and enemy.health.current == enemy.health.max_health, "guardian respawns with full health (%s)" % enemy.state_name())
	t.check(enemy.global_position.distance_to(enemy.home_transform.origin) < 0.5, "guardian respawns at its post")
	await _clear([floor_body, enemy, aim])


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


# --- Spellbook / quick select ---------------------------------------------------------

func _test_spellbook() -> void:
	t.section("Spellbook")
	var defs := SpellRegistry.all()
	t.check(defs.size() == SpellRegistry.SPELL_IDS.size() and defs.size() == 11, "registry loads every spell (%d)" % defs.size())
	var bad: Array[String] = []
	var types: Dictionary = {}
	for i in defs.size():
		var def := defs[i]
		if String(def.id) != SpellRegistry.SPELL_IDS[i] or def.projectile_scene == null \
				or tr(def.display_name) == def.display_name or tr(def.description) == def.description:
			bad.append(String(def.id))
		types[def.effect_type] = true
	t.check(bad.is_empty(), "every spell has a matching id, a projectile and translated texts (%s)" % str(bad))
	t.check(types.size() == defs.size(), "every spell has a distinct effect type")
	t.check(SpellRegistry.sanitize("glowmote") == "glowmote" and SpellRegistry.sanitize("../x") == "" and SpellRegistry.load_definition("nope") == null, "registry rejects unknown ids")

	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	await _spawn_player(Vector3(0, 0.1, 0))
	var caster := player.spell_caster
	var uplift := SpellRegistry.load_definition("uplift")
	var ember := SpellRegistry.load_definition("emberkindle")
	var glow := SpellRegistry.load_definition("glowmote")
	var changes: Array = []
	caster.spells_changed.connect(func() -> void: changes.append(true))
	caster.learn_spell(ARCANE_PULSE)
	caster.learn_spell(uplift)
	caster.learn_spell(ember)
	t.check(caster.known_spells.size() == 3 and caster.quick_slots[0] == ARCANE_PULSE and caster.quick_slots[1] == uplift and caster.quick_slots[2] == ember, "learned spells fill slots 1–3 in order")
	t.check(caster.equipped_spell == ember and caster.equipped_slot() == 2 and changes.size() == 3, "the newest spell is equipped and spells_changed fired per spell")
	caster.learn_spell(uplift)
	t.check(caster.known_spells.size() == 3 and caster.equipped_spell == uplift and changes.size() == 3, "re-learning a spell only equips it")
	t.check(caster.select_slot(0) and caster.equipped_spell == ARCANE_PULSE, "select_slot(0) equips slot 1")
	t.check(not caster.select_slot(5) and not caster.select_slot(-1) and not caster.select_slot(10) and caster.equipped_spell == ARCANE_PULSE, "empty and invalid slots are ignored")
	t.check(caster.cycle(-1) and caster.equipped_spell == ember, "cycling backwards wraps to the last spell")
	t.check(caster.cycle(1) and caster.equipped_spell == ARCANE_PULSE, "cycling forwards wraps to the first spell")
	t.check(not caster.equip(glow) and caster.equipped_spell == ARCANE_PULSE, "an unknown spell cannot be equipped")
	t.check(caster.assign_slot(9, uplift) and caster.quick_slots[9] == uplift and caster.quick_slots[1] == null, "assign_slot moves a spell to slot 10")
	var state := caster.to_state()
	t.check(state["known"] == ["arcane_pulse", "uplift", "emberkindle"] and state["slots"][9] == "uplift" and state["slots"][1] == "" and state["equipped"] == "arcane_pulse", "to_state serialises ids")
	caster.load_state({"known": ["glowmote", "bogus", "uplift"], "slots": ["", "glowmote"], "equipped": "uplift"})
	t.check(caster.known_spells.size() == 2 and caster.quick_slots[1] == glow and caster.quick_slots[0] == uplift and caster.equipped_spell == uplift, "load_state drops unknown ids, keeps slots and fills the rest")
	caster.forget_spell(&"uplift")
	t.check(caster.known_spells.size() == 1 and caster.equipped_spell == glow and caster.quick_slots[0] == null, "forget_spell clears the slot and equips the next spell")
	caster.load_state({})
	t.check(caster.known_spells.is_empty() and caster.equipped_spell == null and not caster.has_spell(), "empty state clears the spellbook")

	# Input actions → PlayerInput → Player → SpellCaster
	caster.load_state({"known": ["arcane_pulse", "uplift", "emberkindle"], "slots": [], "equipped": "arcane_pulse"})
	t.check(caster.equipped_spell == ARCANE_PULSE and caster.quick_slots[2] == ember, "state without slots fills the hotbar in learning order")
	await _press_action("spell_slot_3")
	t.check(caster.equipped_spell == ember, "pressing the slot 3 action equips slot 3")
	await _press_action("spell_prev")
	t.check(caster.equipped_spell == uplift, "spell_prev steps back one slot")
	await _press_action("spell_next")
	await _press_action("spell_next")
	t.check(caster.equipped_spell == ARCANE_PULSE, "spell_next wraps around to slot 1")
	await _press_action("spell_slot_10")
	t.check(caster.equipped_spell == ARCANE_PULSE, "an empty slot key changes nothing")
	await _clear([floor_body])


## Simulates a tap of an InputMap action and lets PlayerInput and the physics
## step see it (Input state is per frame, so the ordering matters).
func _press_action(action: StringName) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().process_frame


# --- Spell effects -------------------------------------------------------------------

func _test_spell_effects() -> void:
	t.section("Spell effects")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	await _spawn_player(Vector3(0, 0.1, 0))
	var caster := player.spell_caster
	var aim := TestHelpers.FixedAim.new()
	add_child(aim)
	caster.aim_source = aim
	aim.origin = Vector3(0, 1.3, 2)
	var uplift := SpellRegistry.load_definition("uplift")
	var galewind := SpellRegistry.load_definition("galewind")
	var ember := SpellRegistry.load_definition("emberkindle")
	var wellspring := SpellRegistry.load_definition("wellspring")
	var duskveil := SpellRegistry.load_definition("duskveil")
	var glow := SpellRegistry.load_definition("glowmote")

	# Uplift floats a block, then it settles; Galewind shoves it.
	var block: PushableBlock = BLOCK_SCENE.instantiate()
	add_child(block)
	block.global_position = Vector3(0, 0.75, -6)
	await _wait(0.6)
	var rest_y := block.global_position.y
	caster.learn_spell(uplift)
	aim.target = block.global_position
	t.check(caster.try_cast(), "uplift casts at the block")
	await _wait(0.8)
	t.check(block.is_floating and block.global_position.y > rest_y + 0.3, "uplift lifts the block (%.2f → %.2f)" % [rest_y, block.global_position.y])
	await _wait(block.float_seconds + 1.5)
	t.check(not block.is_floating and block.global_position.y < rest_y + 0.3, "the block lands again after float_seconds (y %.2f)" % block.global_position.y)
	caster.learn_spell(galewind)
	aim.target = block.global_position
	var z0 := block.global_position.z
	caster.try_cast()
	await _wait(1.0)
	t.check(block.global_position.z < z0 - 1.0, "galewind shoves the block along the cast (%.2f → %.2f)" % [z0, block.global_position.z])
	block.queue_free()
	await get_tree().process_frame

	# Wall torch: water / dark put it out, fire relights, force is ignored.
	var torch: WallTorch = WALL_TORCH_SCENE.instantiate()
	add_child(torch)
	torch.global_position = Vector3(4, 1.2, -6)
	await get_tree().process_frame
	t.check(torch.lit, "torch starts lit")
	var torch_point: Vector3 = torch.get_node("Target/SpellReceiver").get_aim_point()
	caster.learn_spell(wellspring)
	aim.target = torch_point
	caster.try_cast()
	await _wait(0.8)
	t.check(not torch.lit and not torch.get_node("Flame").visible, "wellspring puts the torch out")
	caster.learn_spell(ember)
	caster.try_cast()
	await _wait(0.8)
	t.check(torch.lit and torch.get_node("Flame").visible, "emberkindle relights it")
	caster.learn_spell(duskveil)
	caster.try_cast()
	await _wait(0.8)
	t.check(not torch.lit, "duskveil snuffs it again")
	torch.set_lit(true)
	caster.learn_spell(ARCANE_PULSE)
	caster.try_cast()
	await _wait(0.8)
	t.check(torch.lit, "a force spell leaves the torch alone")
	torch.queue_free()
	await get_tree().process_frame

	# Glowmote leaves a floating light just in front of the surface it hits.
	var wall := TestHelpers.make_floor(self, Vector3(0, 2, -10), Vector3(10, 4, 0.5))
	await _wait(0.1)  # let physics pick up the wall's transform before aiming at it
	caster.learn_spell(glow)
	aim.target = Vector3(2, 1.3, -10)
	caster.try_cast()
	await _wait(1.2)
	var motes: Array = get_children().filter(func(n: Node) -> bool: return n is LightMote)
	t.check(motes.size() == 1, "glowmote spawns one light mote")
	if motes.size() == 1:
		var mote: LightMote = motes[0]
		var light: OmniLight3D = mote.get_node("OmniLight3D")
		t.check(mote.global_position.z > -9.9 and mote.global_position.z < -9.0, "the mote hovers just in front of the wall (z %.2f)" % mote.global_position.z)
		t.check(light.light_energy > 0.5 and light.light_color.is_equal_approx(glow.color), "the mote glows in the spell's colour")
		mote.queue_free()
	wall.queue_free()

	# Per-spell cooldowns with a short global lock.
	await _wait(1.1)
	caster.learn_spell(ember)
	t.check(caster.try_cast(), "emberkindle casts")
	caster.equip(glow)
	t.check(not caster.can_cast() and caster.cooldown_remaining > 0.0, "the global cooldown blocks an instant follow-up with another spell")
	await _wait(SpellCaster.GLOBAL_COOLDOWN + 0.1)
	t.check(caster.can_cast() and caster.get_cooldown_remaining(ember) > 0.0, "after the global lock the other spell is ready while the first still cools")

	# HUD hotbar mirrors the caster.
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	hud._bind_player(player)
	await get_tree().process_frame
	t.check(hud.get_node("%HotbarRoot").visible and hud.hotbar_selected_index() == caster.equipped_slot(), "HUD hotbar is visible and highlights the equipped slot")
	caster.select_slot(0)
	await get_tree().process_frame
	t.check(hud.hotbar_selected_index() == 0 and hud.get_node("%Hotbar").get_child_count() == SpellCaster.QUICK_SLOT_COUNT, "hotbar follows selection and has ten slots")
	hud.queue_free()
	await _clear([floor_body, aim])


# --- School: profiles, areas, lesson tools ------------------------------------------

func _make_zone(id: StringName, kind: String, center: Vector3, size: Vector3) -> AreaZone:
	var zone := AreaZone.new()
	zone.area_id = id
	zone.display_key = "AREA_UNKNOWN"
	zone.kind = kind
	zone.size = size
	add_child(zone)
	zone.global_position = center
	return zone


func _test_school() -> void:
	t.section("School")
	# Profile sanitising mirrors the server record.
	var p := CharacterProfile.sanitize({"house": 9, "role": "wizard", "spells": {"known": ["glowmote", "bogus"], "slots": ["", "glowmote", "x"], "equipped": "nope"}})
	t.check(p["house"] == 4 and p["role"] == "student", "profile clamps the house and unknown roles become student")
	t.check(p["spells"]["known"] == ["glowmote"] and p["spells"]["slots"] == ["", "glowmote", ""] and p["spells"]["equipped"] == "", "profile drops unknown spell ids but keeps slot positions")
	t.check(CharacterProfile.is_staff("professor") and CharacterProfile.is_staff("admin") and not CharacterProfile.is_staff("student"), "staff = professor or admin")
	t.check(CharacterProfile.sanitize({})["role"] == "student", "empty profile is a student")

	# Area tracker: nested zones, innermost wins, leaving falls back.
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var outer := _make_zone(&"test_grounds", "outdoor", Vector3(0, 4.5, 0), Vector3(40, 9, 40))
	var inner := _make_zone(&"test_class", "classroom", Vector3(10, 4.5, 0), Vector3(12, 9, 12))
	await _spawn_player(Vector3(-15, 0.1, 0))
	await _wait(0.3)
	var tracker: AreaTracker = player.area_tracker
	t.check(tracker.current_zone == outer and tracker.current_area_id() == &"test_grounds", "tracker reports the zone the player spawned in")
	player.global_position = Vector3(10, 0.1, 0)
	await _wait(0.3)
	t.check(tracker.current_zone == inner and tracker.current_kind() == "classroom", "entering a nested zone makes it current")
	player.global_position = Vector3(-15, 0.1, 0)
	await _wait(0.3)
	t.check(tracker.current_zone == outer, "leaving the nested zone falls back to the enclosing one")
	player.global_position = Vector3(30, 0.1, 0)
	await _wait(0.3)
	t.check(tracker.current_zone == null and tracker.current_area_id() == &"", "outside every zone the tracker is empty")

	# Nameplate titles follow the role.
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.is_local = false
	remote.display_name = "Remote"
	remote.peer_id = "remote-sid-1"
	add_child(remote)
	remote.global_position = Vector3(12, 0.1, 2)  # inside the classroom
	await _wait(0.2)
	t.check(remote.nameplate.text == "Remote" and remote.role == "student", "students show a bare name")
	remote.set_profile("professor", 2)
	t.check(remote.role == "professor" and remote.house == 2 and remote.nameplate.text == tr("ROLE_PROFESSOR_TITLE") + " Remote\n" + tr("HOUSE_2_NAME"), "professors get a title and their house on the nameplate")
	remote.set_profile("garbage", 9)
	t.check(remote.role == "student" and remote.house == 4, "unknown roles fall back to student")
	var outsider: Player = PLAYER_SCENE.instantiate()
	outsider.is_local = false
	outsider.display_name = "Outsider"
	add_child(outsider)
	outsider.global_position = Vector3(-15, 0.1, 5)  # in the grounds, not the classroom
	await _wait(0.2)

	# Lesson tools: lists students in the room, only enables teaching in a classroom.
	var panel := PROFESSOR_PANEL_SCENE.instantiate()
	add_child(panel)
	panel._bind_player(player)
	t.check(not panel.can_open(), "offline players are students: lesson tools stay closed")
	var requests: Array = []
	panel.grant_requested.connect(func(sid: String, id: String) -> void: requests.append([sid, id]))
	player.global_position = Vector3(8, 0.1, -2)
	await _wait(0.3)
	panel.open()
	t.check(panel.is_open and panel.in_classroom(), "panel opens and sees the classroom")
	var present: Array = panel.students_present()
	t.check(present.size() == 1 and present[0] == remote, "only the player inside the classroom is listed as present")
	t.check(panel.get_node("%Students").item_count == 1 and panel.get_node("%Spells").item_count == SpellRegistry.SPELL_IDS.size(), "lists show one student and every spell")
	panel.get_node("%Spells").select(0)
	panel._update_buttons()
	t.check(not panel.get_node("%GrantButton").disabled and not panel.get_node("%GrantAllButton").disabled and not panel.get_node("%GrantSelfButton").disabled, "teach buttons enabled with a student and a spell")
	panel.get_node("%GrantButton").pressed.emit()
	t.check(requests.size() == 1 and requests[0][0] == "remote-sid-1" and requests[0][1] == "arcane_pulse", "teach asks for the selected student and spell (%s)" % str(requests))
	player.global_position = Vector3(-15, 0.1, 0)
	await _wait(0.3)
	panel.refresh()
	t.check(not panel.in_classroom() and panel.get_node("%GrantButton").disabled and panel.get_node("%GrantSelfButton").disabled, "outside a classroom teaching is disabled")
	panel.close()
	t.check(not panel.is_open and not GameSession.ui_input_captured, "panel close releases UI input")
	panel.queue_free()
	remote.queue_free()
	outsider.queue_free()
	await _clear([floor_body, outer, inner])


# --- Houses: sorting and gated doors ---------------------------------------------------

func _test_houses() -> void:
	t.section("Houses")
	# Questionnaire rule: every house is reachable, ties break toward the emptiest house.
	for house in range(1, CharacterProfile.MAX_HOUSE + 1):
		var answers: Array = []
		for q in HouseSorting.questions():
			for i in q["answers"].size():
				if q["answers"][i]["house"] == house:
					answers.append(i + 1)
					break
		t.check(answers.size() == HouseSorting.question_count() and HouseSorting.sort_offline(answers) == house, "answering for house %d sorts into house %d" % [house, house])
	t.check(HouseSorting.sort_offline([1, 1]) == 0 and HouseSorting.sort_offline([9, 1, 1, 1]) == 0, "malformed answers do not sort")
	var tie := PackedInt32Array([0, 1, 1, 0, 0])
	t.check(HouseSorting.pick(tie) == 1 and HouseSorting.pick(tie, PackedInt32Array([0, 5, 2, 0, 0])) == 2, "ties go to the emptier house")
	t.check(CharacterProfile.house_name(2) == tr("HOUSE_2_NAME") and CharacterProfile.house_name(0) == "" and CharacterProfile.house_color(9) == CharacterProfile.HOUSE_COLORS[4], "house names and colours resolve")

	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	await _spawn_player(Vector3(0, 0.1, 0))
	var houses_seen: Array = []
	GameEvents.house_changed.connect(func(h: int) -> void: houses_seen.append(h))

	# A house door refuses the unsorted and opens for members.
	var door: HouseDoor = HOUSE_DOOR_SCENE.instantiate()
	door.house = 2
	door.open_seconds = 0.6
	add_child(door)
	door.global_position = Vector3(0, 0, -3)
	await get_tree().process_frame
	var refusals: Array = []
	door.refused.connect(func(who: Node) -> void: refusals.append(who))
	var interactable: Interactable = door.get_node("HingeL/Interactable")
	interactable.interact(player)
	t.check(not door.is_open and refusals.size() == 1 and refusals[0] == player, "an unsorted player is refused at a house door")
	player.set_profile("student", 3)
	interactable.interact(player)
	t.check(not door.is_open and refusals.size() == 2, "a member of another house is refused too")
	player.set_profile("student", 2)
	t.check(houses_seen == [3, 2] and player.nameplate.text.ends_with(tr("HOUSE_2_NAME")), "house changes fire house_changed and show on the nameplate")
	interactable.interact(player)
	t.check(door.is_open and refusals.size() == 2, "a member opens the door")
	await _wait(door.open_duration + 0.1)
	t.check(not _capsule_blocked(door.global_position + Vector3(0, 1.0, 0)), "an open house door lets the member walk through")
	await _wait(door.open_seconds + door.open_duration + 0.3)
	t.check(not door.is_open, "the door closes again after open_seconds")
	t.check(_capsule_blocked(door.global_position + Vector3(0, 1.0, 0)), "a closed house door blocks the doorway")
	door.queue_free()

	# The Choosing Stone opens the ceremony once; the panel sorts offline.
	player.set_profile("student", 0)
	var stone: SortingStone = SORTING_STONE_SCENE.instantiate()
	add_child(stone)
	stone.global_position = Vector3(3, 0, -3)
	var panel := SORTING_PANEL_SCENE.instantiate()
	add_child(panel)
	panel._player = player
	await get_tree().process_frame
	var completed: Array = []
	panel.sorting_completed.connect(func(h: int) -> void: completed.append(h))
	stone.get_node("Interactable").interact(player)
	t.check(panel.is_open and GameSession.ui_input_captured and panel.current_question == 0, "touching the stone opens the questionnaire")
	t.check(panel.get_node("%Answers").get_child_count() == 4 and panel.get_node("%Question").text == tr("SORT_Q1"), "the first question shows four answers")
	# Answer everything toward house 3.
	for q in HouseSorting.questions():
		for i in q["answers"].size():
			if q["answers"][i]["house"] == 3:
				(panel.get_node("%Answers").get_child(i) as Button).pressed.emit()
				break
	t.check(completed == [3] and player.house == 3 and panel.get_node("%CloseButton").visible, "answering every question sorts the offline player into house 3")
	t.check(panel.get_node("%Question").text == tr("SORT_RESULT") % tr("HOUSE_3_NAME"), "the panel announces the house")
	panel.close()
	t.check(not panel.is_open and not GameSession.ui_input_captured, "closing the panel releases input")
	stone.get_node("Interactable").interact(player)
	t.check(not panel.is_open, "the stone does not sort a player twice")
	panel.queue_free()
	stone.queue_free()

	# The house columns rank the tally and fill against whole hundreds above the leader.
	var tally: HouseTally = HOUSE_TALLY_SCENE.instantiate()
	add_child(tally)
	tally.global_position = Vector3(-4, 0, -4)
	await get_tree().process_frame
	t.check(tally.totals.is_empty() and tally.ranks == PackedInt32Array([0, 0, 0, 0]) and tally.fill_target(1) == 0.0, "offline the columns stand empty and unranked")
	t.check(HouseTally.rank_of(PackedInt32Array([30, 120, 30, -5])) == PackedInt32Array([2, 1, 2, 4]), "ranks follow the points, ties share a rank")
	tally.set_totals(PackedInt32Array([30, 120, 30, -5]))
	t.check(tally.ranks == PackedInt32Array([2, 1, 2, 4]) and is_equal_approx(tally.fill_target(2), 0.6) and is_equal_approx(tally.fill_target(1), 0.15) and tally.fill_target(4) == 0.0, "the leader fills against 200, a negative house stays empty")
	t.check((tally.get_node("Column2/Rank") as Label3D).text == "I" and (tally.get_node("Column4/Rank") as Label3D).text == "IV", "rank numerals stand above the columns")
	t.check((tally.get_node("Column2/Points") as Label3D).text == "%s\n%s" % [tr("HOUSE_2_NAME"), tr("TALLY_POINTS") % 120], "the plinth names each house and its points")
	t.check(tally.burst_count == 0, "the first tally does not burst")
	tally.set_totals(PackedInt32Array([45, 120, 30, -5]))
	t.check(tally.burst_count == 1 and tally.ranks[0] == 2 and tally.ranks[2] == 3, "a change bursts on that column and re-ranks")
	await _wait(0.3)
	t.check(tally.get_node("Column1").get_child(4).scale.y > 0.01, "the column rises toward its fill")
	tally.queue_free()
	await _clear([floor_body])


# --- Inventory -----------------------------------------------------------------

func _test_inventory() -> void:
	t.section("Inventory")
	# Registry
	t.check(ItemRegistry.exists("torch") and ItemRegistry.load_definition("torch") == TORCH, "registry resolves torch by id")
	t.check(ItemRegistry.sanitize("nope") == "" and ItemRegistry.sanitize("../torch") == "" and ItemRegistry.sanitize("torch") == "torch", "registry rejects unknown / unsafe ids")
	t.check(TORCH.holdable and TORCH.held_scene != null and TORCH.burn_seconds == 0.0, "torch is holdable, has a held scene and never expires")
	var state := ItemRegistry.default_state()
	t.check(state["items"].size() == 1 and state["items"][0]["id"] == "torch", "starting kit is one torch")

	# Data component
	var inv := Inventory.new()
	add_child(inv)
	var held_events: Array = []
	inv.held_item_changed.connect(func(d: ItemDefinition) -> void: held_events.append(d))
	t.check(inv.is_empty() and not inv.hold(TORCH), "cannot hold an item you do not own")
	t.check(inv.add(TORCH, 1) == 1 and inv.has(&"torch") and inv.count_of(&"torch") == 1, "add + count")
	inv.add(TORCH, 2)
	t.check(inv.count_of(&"torch") == 3 and inv.slots.size() == 3, "non-stackable items take one slot each")
	t.check(inv.hold(TORCH) and inv.held_item == TORCH and held_events.size() == 1, "hold emits held_item_changed")
	inv.hold(TORCH)
	t.check(held_events.size() == 1, "holding the same item again is a no-op")
	t.check(inv.remove(&"torch", 2) == 2 and inv.count_of(&"torch") == 1 and inv.held_item == TORCH, "removing spare copies keeps the held one")
	t.check(inv.remove(&"torch", 5) == 1 and inv.is_empty() and inv.held_item == null and held_events.size() == 2, "removing the last held item frees the hands")
	inv.load_state({"items": [{"id": "torch", "count": 1}, {"id": "bogus", "count": 3}], "held": "torch"})
	t.check(inv.slots.size() == 1 and inv.held_item == TORCH, "load_state drops unknown items and restores the held item")
	var round_trip := inv.to_state()
	t.check(round_trip["held"] == "torch" and round_trip["items"] == [{"id": "torch", "count": 1}], "to_state round-trips")
	inv.load_state({"items": [], "held": "torch"})
	t.check(inv.is_empty() and inv.held_item == null and held_events.back() == null, "load_state without the held item frees the hands")
	inv.queue_free()

	# Visual: local player, placeholder body
	var fixtures: Array = []
	fixtures.append(TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(20, 1, 20)))
	await _spawn_player(Vector3(0, 0.1, 0))
	t.check(Inventory.find_on(player) == player.inventory, "inventory registers on the player via meta")
	t.check(player.off_hand != null and player.off_hand.name == "OffHand", "player found its OffHand socket")
	t.check(_find_light(player) == null, "no light before anything is held")
	player.inventory.load_state(ItemRegistry.default_state())
	t.check(player.inventory.hold_id(&"torch"), "player holds the torch")
	var light := _find_light(player)
	t.check(light != null and light.omni_range > 5.0, "held torch spawns an OmniLight under the off hand")
	t.check(player.held_item_mount.current_node != null and player.held_item_mount.current_node.get_parent() == player.off_hand, "held scene is parented to the OffHand socket")
	await _wait(0.3)
	t.check(is_instance_valid(light) and light.light_energy > 0.5, "torch keeps flickering above zero")
	player.inventory.release_held()
	await get_tree().process_frame
	t.check(_find_light(player) == null, "putting the torch away removes the light")

	# Panel: opens on the action, captures input, click holds
	var panel := INVENTORY_PANEL_SCENE.instantiate()
	add_child(panel)
	panel._bind_player(player)
	panel.open()
	t.check(panel.is_open and GameSession.ui_input_captured, "panel open captures UI input")
	var buttons: Array = panel.get_node("%Slots").get_children().filter(func(n: Node) -> bool: return n is Button)
	t.check(buttons.size() == 1, "one slot button for the torch")
	if buttons.size() == 1:
		(buttons[0] as Button).pressed.emit()
		t.check(player.inventory.held_item == TORCH, "clicking the slot takes the torch in hand")
		await get_tree().process_frame
		buttons = panel.get_node("%Slots").get_children().filter(func(n: Node) -> bool: return n is Button)
		(buttons[0] as Button).pressed.emit()
		t.check(player.inventory.held_item == null, "clicking again puts it away")
	panel.close()
	t.check(not panel.is_open and not GameSession.ui_input_captured, "panel close releases UI input")
	panel.queue_free()

	# Remote player path (server-validated id → mount)
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.is_local = false
	remote.display_name = "Remote"
	add_child(remote)
	await _wait(0.2)
	remote.set_remote_held_item("torch")
	t.check(_find_light(remote) != null, "remote player shows the replicated torch")
	remote.set_remote_held_item("")
	await get_tree().process_frame
	t.check(_find_light(remote) == null, "remote player hides it again")
	remote.queue_free()
	await _clear(fixtures)


# --- Brooms and flying ---------------------------------------------------------------

func _test_flying() -> void:
	t.section("Brooms and flying")
	t.check(ItemRegistry.load_definition("broom") == BROOM and BROOM.is_mount() and not BROOM.holdable, "broom is a registered mount, not a hand item")
	t.check(not TORCH.is_mount(), "the torch is not a mount")
	var fixtures: Array = []
	fixtures.append(TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(200, 1, 200)))
	# A rigged character, for the riding pose.
	await _spawn_player(Vector3(0, 0.1, 0), "apprentice_m")
	player.inventory.load_state(ItemRegistry.default_state())
	var movement := player.movement

	# No broom, no flight.
	t.check(not player.broom_rider.toggle() and not movement.is_flying, "cannot fly without a broom")

	# Broom rack (offline): gives one broom, never a second.
	var rack: BroomRack = BROOM_RACK_SCENE.instantiate()
	add_child(rack)
	rack.global_position = Vector3(3, 0, 0)
	fixtures.append(rack)
	await get_tree().process_frame
	t.check(rack.get_child_count() > 4, "rack builds its stand and brooms")
	(rack.get_meta("interactable") as Interactable).interact(player)
	t.check(player.inventory.count_of(&"broom") == 1, "rack gives a broom")
	(rack.get_meta("interactable") as Interactable).interact(player)
	t.check(player.inventory.count_of(&"broom") == 1, "rack gives at most one broom")

	# Mount: takes off and shows the broom under the rider.
	var ground_y := player.global_position.y
	t.check(player.broom_rider.toggle() and movement.is_flying, "B mounts the broom")
	t.check(player.broom_rider.mount_node != null and player.broom_rider.mount_node.get_parent() == player.visual, "broom model sits under the character visual")
	await _wait(0.5)
	t.check(movement.state == PlayerMovement.State.FLY and movement.get_state_name() == "fly", "fly state while mounted")
	t.check(player.global_position.y > ground_y + 0.5, "mounting on the ground lifts off (%.2f m)" % (player.global_position.y - ground_y))

	# Hover: no gravity with nothing pressed.
	await _wait(1.0)
	var hover_y := player.global_position.y
	await _wait(1.0)
	t.check(absf(player.global_position.y - hover_y) < 0.1, "hovers without input (drift %.3f m)" % (player.global_position.y - hover_y))

	# Climb and sink.
	movement.set_external_vertical(1.0)
	await _wait(1.0)
	var climbed := player.global_position.y - hover_y
	t.check(climbed > 4.0, "Space climbs (%.1f m in 1 s)" % climbed)
	var top := player.global_position.y
	movement.set_external_vertical(-1.0)
	await _wait(1.0)
	t.check(player.global_position.y < top - 3.0, "C sinks (%.1f m in 1 s)" % (top - player.global_position.y))
	movement.set_external_vertical(0.0)

	# Cruise and boost are far faster than running.
	movement.set_external_move(Vector3(0, 0, -1), false)
	await _wait(1.5)
	var start := player.global_position
	await _wait(1.0)
	var cruise := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	t.check(cruise > movement.run_speed * 1.5, "cruising flight beats running (%.1f m/s)" % cruise)
	movement.set_external_move(Vector3(0, 0, -1), true)
	await _wait(1.5)
	start = player.global_position
	await _wait(1.0)
	var boosted := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	t.check(boosted > cruise * 1.6, "Shift boosts (%.1f m/s)" % boosted)
	t.check(player.broom_rider.pose != Transform3D.IDENTITY, "the rider leans into fast flight")
	var ride := player.broom_rider.ride_pose
	t.check(ride != null and ride.get_parent() is Skeleton3D and ride.active and ride.influence > 0.99, "the riding pose is blended in on the skeleton")
	var skeleton := ride.get_skeleton()
	# Bone poses carry the modification right after the modifier ran.
	await ride.modification_processed
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_LeftHand")).origin
	var broom_local := player.broom_rider.mount_node.global_transform.affine_inverse() * hand
	# The wrist joint, so a hand's width above the shaft.
	t.check(broom_local.z < -0.3 and Vector2(broom_local.x, broom_local.y).length() < 0.25, "the rider grips the shaft ahead of the seat (%s)" % broom_local)
	var hips := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Hips")).origin
	t.check(absf((player.broom_rider.mount_node.global_transform.affine_inverse() * hips).y - ride.seat_clearance) < 0.02, "the rider sits on the shaft")
	t.check(ride.speed > 0.6, "boosting drives the tucked pose (%.2f)" % ride.speed)
	var wand := player.visual.find_child("WandMesh", true, false) as Node3D
	t.check(wand == null or not wand.visible, "the wand is put away while both hands hold the broom")
	player.broom_rider.on_cast()
	await _wait(0.3)
	t.check(ride.wand_grip < 0.5 and (wand == null or wand.visible), "casting frees the wand hand")
	movement.set_external_move(Vector3.ZERO)
	await _wait(3.0)
	t.check(player.velocity.length() < 1.0, "slows to a hover when released")

	# Mouse steering: the broom turns to the camera's yaw and W climbs toward a raised crosshair.
	movement.frame_yaw_provider = func() -> float: return PI / 2.0
	movement.frame_pitch_provider = func() -> float: return deg_to_rad(30.0)
	await _wait(1.0)
	t.check(absf(angle_difference(player.rotation.y, PI / 2.0)) < 0.1, "the hovering broom turns to face the mouse")
	var before_w := player.global_position
	player.player_input.set_process(false)
	player.player_input.move_axis = Vector2(0, 1)
	await _wait(1.5)
	player.player_input.move_axis = Vector2.ZERO
	player.player_input.set_process(true)
	var flown := player.global_position - before_w
	t.check(flown.x < -5.0 and flown.y > 3.0, "W flies toward the crosshair: west and up (%s)" % str(flown))
	movement.frame_yaw_provider = player.camera_rig.get_yaw
	movement.frame_pitch_provider = player.camera_rig.get_pitch
	await _wait(3.0)

	# Altitude cap.
	var cap := movement.max_flight_height
	movement.max_flight_height = player.global_position.y + 2.0
	movement.set_external_vertical(1.0)
	await _wait(2.0)
	t.check(player.global_position.y < movement.max_flight_height + 1.0, "cannot climb past the flight ceiling")
	movement.set_external_vertical(0.0)
	movement.max_flight_height = cap

	# Dismount in the air: gravity takes over, the landing is soft.
	player.broom_rider.toggle()
	t.check(not movement.is_flying and player.broom_rider.mount_node == null, "B again dismounts and hides the broom")
	await _wait(0.5)
	t.check(not ride.active and ride.influence < 0.01, "landing blends the riding pose back out")
	await _wait(3.0)
	t.check(movement.is_grounded and player.health.current == player.health.max_health, "falls back to the ground unharmed")

	# Landing by holding Descend on the floor.
	player.broom_rider.toggle()
	await _wait(0.3)
	movement.set_external_vertical(-1.0)
	await _wait(2.0)
	t.check(not movement.is_flying and player.broom_rider.mount == null, "holding C on the ground lands and dismounts")
	movement.set_external_vertical(0.0)

	# Flying is for the open air: indoor zones (a classroom here) refuse mounting and land you on entry.
	var zone: AreaZone = AREA_ZONE_SCENE.instantiate()
	zone.area_id = &"test_classroom"
	zone.kind = "classroom"
	zone.size = Vector3(10, 10, 10)
	add_child(zone)
	zone.global_position = Vector3(0, 5, -40)
	fixtures.append(zone)
	player.broom_rider.toggle()
	await _wait(0.3)
	movement.set_external_move(Vector3(0, 0, -1), false)
	var entered := false
	for i in 40:
		await _wait(0.1)
		if player.area_tracker.current_kind() == "classroom":
			entered = true
			break
	await get_tree().physics_frame
	t.check(entered and not movement.is_flying, "flying into a classroom lands the rider")
	movement.set_external_move(Vector3.ZERO)
	await _wait(0.5)
	t.check(not player.broom_rider.toggle() and not movement.is_flying, "cannot mount inside a classroom")
	for kind in ["room", "corridor", "hall", "tower", "common_room"]:
		zone.kind = kind
		t.check(not player.broom_rider.can_fly_here(), "no flying indoors (%s)" % kind)
	for kind in ["grounds", "outdoor"]:
		zone.kind = kind
		t.check(player.broom_rider.can_fly_here(), "flying allowed in the open air (%s)" % kind)
	zone.kind = "classroom"
	# A roof overhead (a cottage in the grounds) also keeps the broom grounded.
	player.global_position = Vector3(30, 0.1, 20)
	var roof := TestHelpers.make_floor(self, Vector3(30, 4.0, 20), Vector3(6, 0.4, 6))
	fixtures.append(roof)
	await _wait(0.3)
	t.check(not player.broom_rider.toggle() and not movement.is_flying, "cannot mount under a roof")

	# Respawning (death, falling out of the world) lands the rider.
	player.global_position = Vector3(0, 0.1, 20)
	await _wait(0.5)
	player.broom_rider.toggle()
	t.check(movement.is_flying, "mounts again outside the classroom")
	player.respawn_handler.respawn()
	t.check(not movement.is_flying and player.broom_rider.mount == null, "respawning dismounts")

	# Losing the broom (server inventory) ends the flight.
	player.global_position = Vector3(0, 0.1, 20)
	await _wait(0.5)
	player.broom_rider.toggle()
	t.check(movement.is_flying, "mounts again after respawning")
	player.inventory.load_state(ItemRegistry.default_state())
	t.check(not movement.is_flying, "losing the broom ends the flight")

	# Snapshots carry the mount; remote players show it.
	player.inventory.add(BROOM)
	player.broom_rider.toggle()
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.is_local = false
	add_child(remote)
	await _wait(0.2)
	remote.synchronizer.receive_state({"p": [0, 5, 0], "y": 0.0, "v": [0, 0, 0], "s": "fly", "m": "broom"})
	t.check(remote.broom_rider.mount == BROOM and remote.broom_rider.mount_node != null, "remote player shows the replicated broom")
	remote.synchronizer.receive_state({"p": [0, 5, 0], "y": 0.0, "v": [0, 0, 0], "s": "idle"})
	t.check(remote.broom_rider.mount == null, "remote player puts it away")
	remote.synchronizer.receive_state({"p": [0, 5, 0], "y": 0.0, "v": [0, 0, 0], "s": "fly", "m": "torch"})
	t.check(remote.broom_rider.mount == null, "a non-mount id in a snapshot is ignored")
	remote.queue_free()
	player.broom_rider.dismount()

	# Satchel: clicking the broom mounts it.
	var panel := INVENTORY_PANEL_SCENE.instantiate()
	add_child(panel)
	panel._bind_player(player)
	panel.open()
	for button: Button in panel.get_node("%Slots").get_children().filter(func(n: Node) -> bool: return n is Button):
		if button.text.begins_with(tr(BROOM.display_name)):
			button.pressed.emit()
	t.check(movement.is_flying and not panel.is_open, "clicking the broom in the satchel mounts it and closes the panel")
	player.broom_rider.dismount()
	panel._unbind_player(player)
	panel.queue_free()

	# Cheat commands (offline: straight into the inventory).
	player.inventory.load_state(ItemRegistry.default_state())
	t.check(ChatCommands.is_command("/broom") and not ChatCommands.is_command("hello"), "slash lines are commands")
	ChatCommands.run("/miotla", player)
	t.check(player.inventory.count_of(&"broom") == 1, "/miotla gives a broom offline")
	ChatCommands.run("/broom", player)
	t.check(player.inventory.count_of(&"broom") == 1, "a second /broom does not duplicate it")
	var unknown := ChatCommands.run("/give dragon", player)
	t.check(unknown.contains("dragon") and player.inventory.slots.size() == 2, "/give with an unknown item is refused")
	t.check(not ChatCommands.run("/help", player).is_empty(), "/help lists the commands")
	var chat := CHAT_PANEL_SCENE.instantiate()
	add_child(chat)
	player.inventory.load_state(ItemRegistry.default_state())
	chat.open()
	chat._on_submitted("/broom")
	t.check(player.inventory.has(&"broom") and not chat.is_open, "the chat box runs commands offline")
	chat.queue_free()
	await _clear(fixtures)


func _find_light(p: Node) -> OmniLight3D:
	return p.find_child("Flame", true, false) as OmniLight3D


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
	t.check(absf(player.global_position.x - platform.global_position.x) < 0.8, "player stays centred on the platform")
	await _clear([platform])


# --- Castle ------------------------------------------------------------------------------

func _test_castle() -> void:
	t.section("Castle")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	await get_tree().physics_frame
	var zones: Array[AreaZone] = castle.get_zones()
	t.check(zones.size() >= 50, "castle has %d named areas" % zones.size())
	var untranslated: Array[String] = []
	for z in zones:
		if tr(z.display_key) == z.display_key:
			untranslated.append(z.display_key)
	t.check(untranslated.is_empty(), "every area has a translated name (missing: %s)" % ", ".join(untranslated))
	t.check(castle.get_node_or_null("StartPoint") != null, "castle has a StartPoint")
	var shell: CastleExterior = castle.get_node_or_null("Exterior")
	var shell_ok := shell != null
	for part in ["Roofs", "Stone"]:
		var mi: MeshInstance3D = shell.get_node_or_null(part) if shell != null else null
		shell_ok = shell_ok and mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0
	# The far view's visibility range counts from each chunk's AABB centre, so a chunk must be
	# small enough never to show while the camera is inside one of its rooms (one castle-wide
	# mesh filled the doorways near the castle's edges with walls one could walk through).
	var far_chunks := 0
	var widest := 0.0
	for part in ["Hlod", "HlodWindows"]:
		var group: Node = shell.get_node_or_null(part) if shell != null else null
		shell_ok = shell_ok and group != null and group.get_child_count() > 0
		for mi: MeshInstance3D in (group.get_children() if group != null else []):
			far_chunks += 1
			widest = maxf(widest, mi.get_aabb().size.length() / 2.0)
			shell_ok = shell_ok and mi.mesh.get_surface_count() > 0
	t.check(shell_ok, "the castle has its exterior shell (roofs, stone, far view)")
	t.check(shell != null and widest < shell.detail_range - 20.0,
		"the far view is chunked so it never shows from inside the castle (%d chunks, widest %.0f m from its centre)" % [far_chunks, widest])
	await get_tree().process_frame
	var ranged := 0
	for w in castle.get_node("Walls").find_children("*", "GeometryInstance3D", true, false) + castle.get_node("StaticBatch").get_children():
		if w is GeometryInstance3D and (w as GeometryInstance3D).visibility_range_end > 0.0:
			ranged += 1
	t.check(ranged > 100, "interior detail fades out at the far-view range (%d meshes)" % ranged)
	var batch: StaticBatch = castle.get_node("StaticBatch")
	t.check(batch.instance_count > 3000 and castle.get_node("Walls").find_children("*", "StaticBody3D", true, false).size() < batch.instance_count / 8,
		"static modules are batched (%d modules in %d nodes)" % [batch.instance_count, batch.get_child_count()])
	t.check(get_tree().get_nodes_in_group("secret_walls").size() >= 3, "castle has secret passages")
	# Stable object ids: unique "<area>/<name>", the area exists, and every placement is in the scene.
	var area_ids: Dictionary = {}
	for z in zones:
		area_ids[str(z.area_id)] = true
	var object_ids: Dictionary = {}
	var bad_ids: Array[String] = []
	for node in get_tree().get_nodes_in_group("world_objects"):
		var oid: String = str(node.get("object_id"))
		if oid.is_empty() or object_ids.has(oid) or not area_ids.has(oid.get_slice("/", 0)):
			bad_ids.append("%s (%s)" % [oid, node.name])
		object_ids[oid] = true
	t.check(bad_ids.is_empty() and object_ids.size() >= 90, "%d world objects with unique ids in known areas (bad: %s)" % [object_ids.size(), ", ".join(bad_ids)])
	var placements: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/placements.json"))
	var missing_placed: Array[String] = []
	if placements is Dictionary:
		for area: String in placements:
			for entry: Dictionary in placements[area]:
				if entry["kind"] in ["checkpoint", "crystal_guardian", "house_tally", "notice_board"]:
					continue
				if not object_ids.has(area + "/" + str(entry["id"])):
					missing_placed.append(area + "/" + str(entry["id"]))
	t.check(placements is Dictionary and missing_placed.is_empty(), "every world object in content/placements.json is in the castle (missing: %s)" % ", ".join(missing_placed))
	# Offline practice mysteries: the secret walls follow the public offline set.
	var engine: OfflineMysteryEngine = castle.world_object_sync.offline_engine
	var generated_offline: Variant = JSON.parse_string(FileAccess.get_file_as_string(OfflineMysteryEngine.GENERATED_PATH))
	var gen_count: int = (generated_offline as Dictionary).get("mysteries", []).size() if generated_offline is Dictionary else 0
	t.check(engine != null and engine.mystery_count() == 3 + gen_count and gen_count >= 15 and engine.drives("undercroft/secret_wall"),
		"offline, the castle runs the practice mysteries and the generated secrets (%d)" % gen_count)
	var offline_problems: Array[String] = []
	var offline_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OfflineMysteryEngine.CONTENT_PATH))
	for m: Dictionary in offline_data.get("mysteries", []) + (generated_offline.get("mysteries", []) if generated_offline is Dictionary else []):
		for step: Dictionary in m.get("steps", []):
			if step.has("object") and not object_ids.has(str(step["object"])):
				offline_problems.append("unknown object %s" % step["object"])
			if step.has("area") and not area_ids.has(str(step["area"])):
				offline_problems.append("unknown area %s" % step["area"])
			if step.has("text") and tr(str(step["text"])) == str(step["text"]):
				offline_problems.append("untranslated %s" % step["text"])
			if str(step.get("event", "")) == "together":
				offline_problems.append("%s: together needs other players" % m.get("id"))
		for oid: String in m.get("on_solved", {}).get("set_state", {}):
			if not object_ids.has(oid):
				offline_problems.append("sets unknown object %s" % oid)
	t.check(offline_problems.is_empty(), "the offline set refers to real objects and translated text (%s)" % "; ".join(offline_problems))
	var undercroft: SecretWall = null
	var cellar_plaque: Plaque = null
	for node in get_tree().get_nodes_in_group("world_objects"):
		if node.get("object_id") == "undercroft/secret_wall":
			undercroft = node
		elif node.get("object_id") == "cellars/plaque_cellars":
			cellar_plaque = node
	var hit := SpellEffect.create(ARCANE_PULSE, null, "", undercroft.global_position, Vector3.FORWARD)
	undercroft._on_spell_received(hit)
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(not undercroft.is_revealed, "offline, a bare hit no longer opens the undercroft")
	cellar_plaque._on_interacted(null)
	await get_tree().process_frame
	await get_tree().process_frame
	undercroft._on_spell_received(hit)
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(undercroft.is_revealed, "reading the cellar plaque first, then striking the wall, opens it offline")
	# A generated secret: read its clue plaque, then strike its wall.
	var gen_solved := false
	for m: Dictionary in (generated_offline as Dictionary).get("mysteries", []):
		var first: Dictionary = m["steps"][0]
		if first.get("event") != "interact":
			continue
		var plaque_node: Node = null
		var wall_node: SecretWall = null
		for node in get_tree().get_nodes_in_group("world_objects"):
			if node.get("object_id") == first["object"]:
				plaque_node = node
			elif node.get("object_id") == m["steps"][1]["object"]:
				wall_node = node
		if plaque_node == null or wall_node == null:
			continue
		plaque_node._on_interacted(null)
		await get_tree().process_frame
		wall_node._on_spell_received(SpellEffect.create(ARCANE_PULSE, null, "", wall_node.global_position, Vector3.FORWARD))
		await get_tree().process_frame
		await get_tree().process_frame
		gen_solved = wall_node.is_revealed
		break
	t.check(gen_solved, "a generated secret opens offline after its clue plaque is read")
	t.check(GameSession.get_total(&"arcane_fragment") >= 10, "castle registers its fragments (got %d)" % GameSession.get_total(&"arcane_fragment"))
	var tome_spells: Dictionary = {}
	for tome in castle.get_node("Tomes").get_children():
		if tome is SpellTome and tome.spell != null:
			tome_spells[tome.spell.id] = true
	t.check(tome_spells.size() == SpellRegistry.SPELL_IDS.size(), "a practice tome for every spell is placed in the castle (%d)" % tome_spells.size())
	var gate_houses: Dictionary = {}
	for door in castle.get_node("Doors").get_children():
		if door is HouseDoor:
			gate_houses[door.house] = true
	t.check(gate_houses.size() == 4, "every house has a gated door (%s)" % str(gate_houses.keys()))
	t.check(get_tree().get_nodes_in_group("world_objects").any(func(n: Node) -> bool: return n is SortingStone), "the Choosing Stone stands in the castle")
	var tallies := castle.get_node("Props").get_children().filter(func(n: Node) -> bool: return n is HouseTally)
	var tally_at: Vector3 = (tallies[0] as Node3D).position if tallies.size() == 1 else Vector3.INF
	t.check(tally_at.x > 12 and tally_at.x < 44 and tally_at.z > 8 and tally_at.z < 22, "the house columns stand at the head of the great hall (%s)" % str(tally_at))
	var guardians := 0
	for enemy in castle.get_node("Enemies").get_children():
		if enemy is Enemy and (enemy as Enemy).global_position.y < -5.0:
			guardians += 1
	t.check(guardians >= 3, "guardians stand in the dungeons (%d)" % guardians)
	var landing_houses: Dictionary = {}
	for z in zones:
		if z.area_id == &"tower_ne_1" or z.area_id == &"tower_nw_1":
			landing_houses[z.area_id] = z.house
	t.check(landing_houses.get(&"tower_ne_1", 0) == 1 and landing_houses.get(&"tower_nw_1", 0) == 2, "tower landings belong to their houses")
	# Every area has a floor under its centre (rooms with stair holes keep their centre solid).
	var fell: Array[String] = []
	var terrain: Terrain = castle.get_node_or_null("Grounds/Terrain")
	t.check(terrain != null and terrain.size_x > 0, "the castle stands in generated grounds")
	for z in zones:
		var base_y := z.global_position.y - z.size.y / 2.0
		if z.kind == "grounds" and terrain != null:
			# Outdoor areas over terrain: stand on open ground in the area (its centre, or an
			# inset corner when a landmark stands in the middle).
			var spot: Vector3 = await _open_ground(terrain, z)
			if spot == Vector3.INF:
				continue
			var cx := spot.x
			var cz := spot.z
			base_y = spot.y
			await _spawn_player(Vector3(cx, base_y + 0.4, cz))
			await _wait(0.4)
			if not player.movement.is_grounded or absf(player.global_position.y - base_y) > 0.6:
				fell.append("%s (y %.2f vs ground %.2f)" % [z.area_id, player.global_position.y, base_y])
			continue
		await _spawn_player(Vector3(z.global_position.x, base_y + 0.2, z.global_position.z))
		await _wait(0.4)
		if not player.movement.is_grounded or absf(player.global_position.y - base_y) > 0.3:
			fell.append("%s (y %.2f vs %.2f)" % [z.area_id, player.global_position.y, base_y])
	t.check(fell.is_empty(), "every area has a floor at its centre (%s)" % ", ".join(fell))
	# Area events: walking north from the start crosses the grounds into the entrance hall.
	var entered: Array = []
	var on_enter := func(id: StringName, _z: Node) -> void: entered.append(id)
	GameEvents.area_entered.connect(on_enter)
	await _spawn_player(castle.get_node("StartPoint").global_position + Vector3(2, 0.1, 0))
	player.movement.set_external_move(Vector3(0, 0, -1), true)
	await _wait(9.0)
	player.movement.set_external_move(Vector3.ZERO)
	t.check(entered.has(&"grounds") and entered.has(&"entrance_hall"), "walking north enters the grounds then the entrance hall (%s)" % str(entered))
	t.check(player.global_position.z < 44.0, "the entrance doorway can be walked through (z %.1f)" % player.global_position.z)
	GameEvents.area_entered.disconnect(on_enter)
	# Grand staircase: the first flight climbs from the ground to the first landing.
	await _spawn_player(Vector3(-33.975, 1.2, 46.5))
	player.movement.set_external_move(Vector3(0, 0, -1), false)
	await _wait(8.0)
	player.movement.set_external_move(Vector3.ZERO)
	t.check(player.global_position.y > 8.5 and player.global_position.z < 32.5, "stairs: walking up the first flight reaches the landing (y %.2f, z %.2f)" % [player.global_position.y, player.global_position.z])
	# Stair turret: walk the southwest turret's spiral from its ground-floor doorway up one turn.
	var spiral: SpiralStaircase = null
	for node in castle.get_node("Stairs").get_children():
		if node is SpiralStaircase and absf(node.global_position.x - -56.0) < 0.1:
			spiral = node
	t.check(spiral != null, "the southwest tower has a spiral stair turret")
	if spiral != null:
		var centre := spiral.global_position
		var door_angle := spiral.landing_angle()
		t.check(spiral.landing_steps > 0 and spiral.riser() <= 0.36 + 1e-4,
			"the turret's spiral has a level landing at its doorways (%d sectors, riser %.2f)" % [spiral.landing_steps, spiral.riser()])
		await _spawn_player(centre + Vector3(cos(door_angle), 0, sin(door_angle)) * 2.3 + Vector3(0, 0.3, 0))
		for i in range(int(14.0 * Engine.physics_ticks_per_second)):
			var rel := player.global_position - centre
			var radial := Vector3(rel.x, 0, rel.z)
			var tangent := Vector3(-rel.z, 0, rel.x).normalized()
			# Hold the walking line at 2.3 m from the column while climbing.
			player.movement.set_external_move((tangent + radial.normalized() * (2.3 - radial.length()) * 0.8).normalized(), false)
			await get_tree().physics_frame
			if player.global_position.y > centre.y + 9.2:
				break
		player.movement.set_external_move(Vector3.ZERO)
		t.check(player.global_position.y > centre.y + 8.5, "stairs: the turret's spiral climbs a full storey (y %.2f)" % player.global_position.y)
	# Every straight flight: from the middle of its approach landing straight up to its arrival landing.
	var flights_ok: Array[String] = []
	for node in castle.get_node("Stairs").get_children():
		if not node is Staircase:
			continue
		var flight := node as Staircase
		var along := flight.global_transform.basis.x.normalized()
		await _spawn_player(flight.global_position - along * 2.0 + Vector3(0, 0.3, 0))
		player.movement.set_external_move(along, false)
		var reached := false
		for i in range(int(12.0 * Engine.physics_ticks_per_second)):
			await get_tree().physics_frame
			if player.global_position.y > flight.global_position.y + flight.rise - 0.2 and \
					(player.global_position - flight.global_position).dot(along) > flight.run + 0.5:
				reached = true
				break
		player.movement.set_external_move(Vector3.ZERO)
		if not reached:
			flights_ok.append("%s (y %.1f)" % [flight.name, player.global_position.y])
	t.check(flights_ok.is_empty(), "every straight flight is walkable from its approach to its arrival landing (stuck: %s)" % ", ".join(flights_ok))
	castle.queue_free()
	await get_tree().process_frame


func _test_grounds() -> void:
	t.section("Grounds")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var terrain: Terrain = castle.get_node("Grounds/Terrain")
	var worst := 0.0
	for p: Array in terrain.meta.get("probes", []):
		worst = maxf(worst, absf(terrain.height_at(p[0], p[2]) - float(p[1])))
	t.check(terrain.meta.get("probes", []).size() > 3 and worst < 0.02, "terrain heights match the generator (worst %.3f m)" % worst)
	t.check(not terrain.has_ground(0.0, 36.0) and terrain.has_ground(0.0, 120.0), "the terrain has a hole where the castle's floors are")
	# The first-year path: from the landing stage up the cliff to the lake terrace, through the
	# lake gate into the boat tunnel.
	var route: Array = terrain.meta["paths"]["first_year_path"]
	var start := Vector3(route[0][0], route[0][1], route[0][2])
	terrain.focus_on(start, true)
	await _spawn_player(start + Vector3(0, 0.5, 0))
	var entered: Array = []
	var on_enter := func(id: StringName, _z: Node) -> void: entered.append(id)
	GameEvents.area_entered.connect(on_enter)
	var stuck := ""
	var targets: Array[Vector3] = []
	for p: Array in route:
		targets.append(Vector3(p[0], p[1], p[2]))
	targets.append(Vector3(-84.0, -9.0, -58.0))
	targets.append(Vector3(-66.0, -9.0, -58.0))
	for target in targets:
		var ok := false
		for i in range(int(6.0 * Engine.physics_ticks_per_second)):
			var to := target - player.global_position
			to.y = 0
			if to.length() < 1.6:
				ok = true
				break
			player.movement.set_external_move(to.normalized(), true)
			if i % 30 == 0:
				terrain.focus_on(player.global_position, true)
			await get_tree().physics_frame
		if not ok:
			stuck = "stuck at (%.1f, %.1f, %.1f) heading for (%.1f, %.1f)" % [player.global_position.x, player.global_position.y, player.global_position.z, target.x, target.z]
			break
	player.movement.set_external_move(Vector3.ZERO)
	GameEvents.area_entered.disconnect(on_enter)
	t.check(stuck.is_empty(), "the first-year path climbs from the landing stage to the lake gate (%s)" % stuck)
	t.check(entered.has(&"lake_terrace") and entered.has(&"lake_tunnel"), "walking it reaches the lake terrace and the boat tunnel (%s)" % str(entered))
	# The causeway crosses the viaduct without dropping into the valley.
	var causeway: Array = terrain.meta["paths"]["causeway"]
	var low := INF
	var from := Vector3(0, 0, 270)
	for p: Array in causeway:
		if absf(float(p[2]) - 270.0) < 3.0:
			from.y = p[1]
	terrain.focus_on(from, true)
	await _spawn_player(from + Vector3(0, 0.6, 0))
	player.movement.set_external_move(Vector3(0, 0, 1), true)
	for i in range(int(22.0 * Engine.physics_ticks_per_second)):
		if i % 30 == 0:
			terrain.focus_on(player.global_position, true)
		await get_tree().physics_frame
		low = minf(low, player.global_position.y - terrain.height_at(player.global_position.x, player.global_position.z))
		if player.global_position.z > 410.0:
			break
	player.movement.set_external_move(Vector3.ZERO)
	t.check(player.global_position.z > 405.0, "the causeway can be walked across the viaduct (z %.1f)" % player.global_position.z)
	# Deep water carries a player back to the last dry ground.
	var shore := Vector3(-215.0, 0, 20.0)
	shore.y = terrain.height_at(shore.x, shore.z)
	terrain.focus_on(shore, true)
	await _spawn_player(shore + Vector3(0, 0.4, 0))
	await _wait(0.5)
	player.global_position = Vector3(-420.0, terrain.water_level - 4.0, 20.0)
	await _wait(0.3)
	t.check(player.global_position.distance_to(shore) < 6.0, "deep water carries the player back to the shore (at %s)" % str(player.global_position))
	castle.queue_free()
	await get_tree().process_frame


func _test_village() -> void:
	t.section("Village")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var village := castle.get_node_or_null("Grounds/Village") as Village
	t.check(village != null and village.buildings.size() >= 40, "the village stands beyond the outer gate (%d buildings)" % (village.buildings.size() if village != null else 0))
	if village == null:
		castle.queue_free()
		return
	var zones := {}
	for z: AreaZone in castle.get_zones():
		zones[str(z.area_id)] = z
	var enterable := village.buildings.filter(func(b: Dictionary) -> bool: return b["enterable"])
	var missing: Array[String] = []
	for b: Dictionary in enterable:
		var z := zones.get(b["id"]) as AreaZone
		if z == null or z.kind != str(b["kind"]):
			missing.append(str(b["id"]))
	t.check(enterable.size() >= 12 and missing.is_empty(), "every shop, inn, the post office and the station hall is its own area (%d, missing %s)" % [enterable.size(), str(missing)])
	var inside_meshes := village.find_children("Inside_*", "MeshInstance3D", false, false)
	var outside_meshes := village.find_children("Outside_*", "MeshInstance3D", false, false)
	var shapes := village.get_node("Collision").get_child_count()
	t.check(shapes > 300 and outside_meshes.size() > 5 and inside_meshes.size() > 3, "buildings, interiors and the railway are built (%d shapes, %d outside / %d inside meshes)" % [shapes, outside_meshes.size(), inside_meshes.size()])
	t.check(inside_meshes.all(func(m: MeshInstance3D) -> bool: return m.layers == 1) and outside_meshes.all(func(m: MeshInstance3D) -> bool: return m.layers & (1 << 10) != 0),
		"interiors stay off the outdoor light's layer, the outside is on it")
	var glow := village.get("_glow") as StandardMaterial3D
	village.set_daylight(0.0)
	var night := glow.albedo_color
	village.set_daylight(1.0)
	t.check(night.r > 0.9 and glow.albedo_color.r < 0.5, "window glows follow the daylight")
	# Walk in from the high street: up the step, through the door, into the shop's area.
	var terrain: Terrain = castle.get_node("Grounds/Terrain")
	var shop := village.building("sweet_shop")
	var street := Village.door_point(shop, 5.0)
	street.y = terrain.height_at(street.x, street.z)
	terrain.focus_on(street, true)
	await _spawn_player(street + Vector3(0, 0.4, 0))
	var entered: Array = []
	var on_enter := func(id: StringName, _z: Node) -> void: entered.append(id)
	GameEvents.area_entered.connect(on_enter)
	var stuck := await _walk_route([Village.door_point(shop, 1.0), Village.door_point(shop, -4.0)], terrain)
	GameEvents.area_entered.disconnect(on_enter)
	t.check(stuck.is_empty() and entered.has(&"sweet_shop"), "a player walks in off the high street into the sweet shop (%s, entered %s)" % [stuck, str(entered)])
	t.check(absf(player.global_position.y - float(shop["floor"])) < 0.3, "and stands on the shop floor (y %.2f)" % player.global_position.y)
	var castle_map := CastleMap.new()
	add_child(castle_map)
	castle_map.build(castle)
	t.check(castle_map.room_at(player.global_position).get("id", "") == "sweet_shop" and castle_map.view_storey_at(player.global_position) == 0,
		"the map finds the shop under the player and shows the ground floor")
	castle_map.queue_free()
	# Arrival: from the platform through the station hall onto the forecourt.
	var marker := castle.get_tree().get_first_node_in_group("station_arrival") as Node3D
	t.check(marker != null and village.is_ancestor_of(marker), "the station has an arrival marker on its platform")
	var hall := village.building("station_hall")
	var back := Vector3(float(hall["back_door"]), float(hall["floor"]), float(hall["rect"][3]))
	terrain.focus_on(marker.global_position, true)
	await _spawn_player(marker.global_position + Vector3(0, 0.3, 0))
	await _wait(0.3)
	t.check(absf(player.global_position.y - float(hall["floor"])) < 0.3, "a player put on the arrival marker stands on the platform (y %.2f)" % player.global_position.y)
	entered.clear()
	GameEvents.area_entered.connect(on_enter)
	stuck = await _walk_route([back + Vector3(0, 0, 2.0), back + Vector3(0, 0, -2.0), Village.door_point(hall, -2.0), Village.door_point(hall, 4.0)], terrain)
	GameEvents.area_entered.disconnect(on_enter)
	t.check(stuck.is_empty() and entered.has(&"station_hall"), "from the platform through the station hall to the forecourt (%s, entered %s)" % [stuck, str(entered)])
	# /goto takes a playtester there.
	await _spawn_player(Vector3(0, 0.2, 84))
	var line := ChatCommands.run("/goto station", player)
	await _wait(0.3)
	t.check(player.global_position.distance_to(marker.global_position) < 1.0, "/goto station puts the player on the platform (%s)" % line)
	ChatCommands.run("/idz wioska", player)
	await _wait(0.3)
	var square := zones["village_square"] as AreaZone
	t.check(absf(player.global_position.x - square.global_position.x) < square.size.x / 2.0 and absf(player.global_position.z - square.global_position.z) < square.size.z / 2.0,
		"/idz wioska puts the player in the village square")
	t.check(ChatCommands.run("/goto nowhere_at_all", player).contains("nowhere_at_all"), "/goto names an unknown place back")
	castle.queue_free()
	await get_tree().process_frame


func _test_currency() -> void:
	t.section("Currency")
	var forms := {1: "one", 2: "few", 4: "few", 5: "many", 11: "many", 12: "many", 14: "many", 21: "many", 22: "few", 25: "many", 112: "many", 122: "few", 0: "many"}
	var wrong: Array = []
	for n: int in forms:
		if Currency.polish_form(n) != forms[n]:
			wrong.append(n)
	t.check(wrong.is_empty(), "Polish plural forms of the currency (wrong for %s)" % str(wrong))
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	var pl := [Currency.format(1), Currency.format(3), Currency.format(5)]
	TranslationServer.set_locale("en")
	var en := [Currency.format(1), Currency.format(5)]
	t.check(pl[0] != pl[1] and pl[1] != pl[2] and en[0] != en[1] and pl[2].begins_with("5 ") and en[1].begins_with("5 "),
		"amounts read naturally in both languages (%s / %s)" % [str(pl), str(en)])
	var subject: SubjectDefinition = SubjectRegistry.all()[0]
	var line := Currency.change_line(10, "lesson", str(subject.id))
	t.check(line.begins_with("+10") and line.contains(tr(subject.display_name)), "a lesson's pay names the subject (%s)" % line)
	t.check(Currency.change_line(0, "lesson", "") == "" and Currency.change_line(-4, "shop", "").contains("4"), "no line for nothing, a purchase shows what it cost")
	TranslationServer.set_locale(locale)
	# Offline the purse is a practice one: /coins changes it at once and never goes below zero.
	NetworkManager.offline_coins = 0
	var seen: Array = []
	var on_wallet := func(coins: int, delta: int, _s: String, _d: String) -> void: seen.append([coins, delta])
	NetworkManager.wallet_changed.connect(on_wallet)
	ChatCommands.run("/coins 25", null)
	ChatCommands.run("/korony -100", null)
	var said := ChatCommands.run("/coins", null)
	var usage := ChatCommands.run("/coins lots", null)
	NetworkManager.wallet_changed.disconnect(on_wallet)
	t.check(seen == [[25, 25], [0, -25]] and NetworkManager.get_coins() == 0, "offline /coins adds and takes, never below zero (%s)" % str(seen))
	t.check(said.contains(Currency.format(0)) and usage == tr("CHEAT_COINS_USAGE"), "/coins alone says the balance, a bad amount shows the usage")
	# The server's economy rules ship with sensible values.
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/school_rules.json"))
	var ok := true
	for key in ["coins_per_lesson", "lesson_coin_minutes", "coins_per_mystery", "max_daily_coins", "max_coin_grant"]:
		ok = ok and rules.has(key) and float(rules[key]) > 0.0 and float(rules[key]) == floorf(float(rules[key]))
	t.check(ok and float(rules["max_daily_coins"]) >= float(rules["coins_per_lesson"]), "school_rules.json sets the economy (pay, cap, grant limit)")


## Walks the player through the points in order (each within 8 s); "" or where it got stuck.
func _walk_route(points: Array, terrain: Terrain = null) -> String:
	for target: Vector3 in points:
		var ok := false
		for i in range(int(8.0 * Engine.physics_ticks_per_second)):
			var to := target - player.global_position
			to.y = 0
			if to.length() < 0.8:
				ok = true
				break
			player.movement.set_external_move(to.normalized(), true)
			if terrain != null and i % 30 == 0:
				terrain.focus_on(player.global_position, true)
			await get_tree().physics_frame
		if not ok:
			player.movement.set_external_move(Vector3.ZERO)
			return "stuck at (%.1f, %.1f, %.1f) heading for (%.1f, %.1f)" % [player.global_position.x, player.global_position.y, player.global_position.z, target.x, target.z]
	player.movement.set_external_move(Vector3.ZERO)
	return ""


func _test_map() -> void:
	t.section("Map")
	# The map is read from whatever level it is given: a two-room fixture maps to two rooms.
	var fixture := Node3D.new()
	add_child(fixture)
	var fixture_zones := Node3D.new()
	fixture_zones.name = "Zones"
	fixture.add_child(fixture_zones)
	for spec: Array in [[&"hall_a", "hall", Vector3(0, 4.5, 0), Vector3(16, 9, 16)], [&"nook", "secret", Vector3(12, 13.5, 0), Vector3(8, 9, 8)]]:
		var z := _make_zone(spec[0], spec[1], spec[2], spec[3])
		z.reparent(fixture_zones)
	var small := CastleMap.new()
	add_child(small)
	small.build(fixture)
	t.check(small.rooms.size() == 2 and small.min_storey == 0 and small.max_storey == 1 and small.terrain == null,
		"the map is built from the level's zones (%d rooms, storeys %d..%d)" % [small.rooms.size(), small.min_storey, small.max_storey])
	t.check(small.rooms_on(0).size() == 1 and small.rooms_on(1).is_empty(), "an unfound secret room is not on the map")
	small.reveal("nook")
	t.check(small.rooms_on(1).size() == 1 and small.room_at(Vector3(12, 9.2, 0)).get("id", "") == "nook", "a found secret room appears on its storey")
	small.queue_free()
	fixture.queue_free()

	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var castle_map := CastleMap.new()
	add_child(castle_map)
	castle_map.build(castle)
	var non_grounds := 0
	var secret_id := ""
	for z: AreaZone in castle.get_zones():
		if z.kind != "grounds":
			non_grounds += 1
		if z.kind == "secret" and secret_id.is_empty():
			secret_id = str(z.area_id)
	t.check(castle_map.rooms.size() == non_grounds and castle_map.grounds.size() > 3, "every castle zone is a map room (%d), named grounds places are labels (%d)" % [castle_map.rooms.size(), castle_map.grounds.size()])
	t.check(castle_map.min_storey <= -1 and castle_map.max_storey >= 3, "the map spans the dungeons to the towers (%d..%d)" % [castle_map.min_storey, castle_map.max_storey])
	t.check(castle_map.stairs.size() > 5 and not castle_map.stairs_on(0).is_empty(), "stairs are on the map (%d)" % castle_map.stairs.size())
	var hall := castle_map.room_at(Vector3(0, 0.1, 36))
	t.check(hall.get("id", "") == "entrance_hall" and castle_map.view_storey_at(Vector3(0, 0.1, 36)) == 0, "the room under a position is found (%s)" % hall.get("id", "none"))
	t.check(castle_map.view_storey_at(Vector3(0, 9.1, 36)) == 1, "standing on the first floor shows the first floor")
	var shown_secrets := castle_map.rooms.filter(func(r: Dictionary) -> bool: return r["secret"] and castle_map.is_known(r))
	t.check(not secret_id.is_empty() and shown_secrets.is_empty(), "secret areas start hidden")
	NetworkManager.profile_received.emit({"discoveries": ["map:" + secret_id, "founders_tale"]})
	t.check(castle_map.is_revealed(secret_id), "a \"map:<area>\" discovery from the server reveals that secret area")
	# The relief: the height image carries the terrain's quantised samples.
	var terrain := castle_map.terrain
	var heights := terrain.height_image() if terrain != null else null
	var decoded_ok := heights != null and heights.get_width() == terrain.size_x
	if decoded_ok:
		for probe: Vector2i in [Vector2i(10, 20), Vector2i(500, 600), Vector2i(1000, 3)]:
			var c := heights.get_pixelv(probe)
			var h := terrain.h_min + (roundi(c.r8) + roundi(c.g8) * 256) * terrain.h_scale
			decoded_ok = decoded_ok and absf(h - terrain.sample(probe.x, probe.y)) < 0.01
	t.check(decoded_ok, "the map's relief image decodes to the terrain's heights")

	# Minimap and full map.
	await _spawn_player(Vector3(0, 0.2, 36))
	var minimap: Minimap = MINIMAP_SCENE.instantiate()
	add_child(minimap)
	minimap.set_map(castle_map)
	await get_tree().process_frame
	await get_tree().process_frame
	var minimap_view: MapView = minimap.get_node("%View")
	t.check(minimap.get_node("%Root").visible and minimap_view.storey == 0 and minimap_view.centre.distance_to(Vector2(0, 36)) < 2.0,
		"the minimap follows the player (centre %s, storey %d)" % [str(minimap_view.centre), minimap_view.storey])
	t.check((minimap.get_node("%PlaceLabel") as Label).text.begins_with(tr("AREA_ENTRANCE_HALL")), "the minimap names the place (%s)" % (minimap.get_node("%PlaceLabel") as Label).text)
	var panel: MapPanel = MAP_PANEL_SCENE.instantiate()
	add_child(panel)
	panel.set_map(castle_map)
	var open_ev := InputEventAction.new()
	open_ev.action = &"map"
	open_ev.pressed = true
	panel._unhandled_input(open_ev)
	t.check(panel.is_open and GameSession.ui_input_captured, "M opens the map and it takes the keyboard")
	var view: MapView = panel.get_node("%View")
	for i in range(12):
		panel.change_storey(1)
	t.check(view.storey == castle_map.max_storey, "the floor buttons stop at the top storey (%d)" % view.storey)
	panel.centre_on_player()
	var before := view.screen_to_world(Vector2(100, 80))
	panel.zoom_at(2.0, Vector2(100, 80))
	t.check(view.screen_to_world(Vector2(100, 80)).distance_to(before) < 0.01, "zooming keeps the point under the cursor")
	await get_tree().process_frame
	panel._input(open_ev)
	t.check(not panel.is_open and not GameSession.ui_input_captured, "M closes the map again")
	panel.queue_free()
	minimap.queue_free()
	castle_map.queue_free()
	player.queue_free()
	player = null
	castle.queue_free()
	await get_tree().process_frame


func _test_setpieces() -> void:
	t.section("Set pieces")
	# The shared clock prefers the least-delayed sample.
	var clock := ServerClock.new()
	clock.add_sample((ServerClock.local_seconds() + 100.0) * 1000.0, 400)
	clock.add_sample((ServerClock.local_seconds() + 100.0) * 1000.0, 20)
	t.check(absf(clock.now() - (ServerClock.local_seconds() + 100.01)) < 0.05, "the server clock keeps the shortest round trip")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var stairs: Array[ShiftingStair] = []
	var gates: Array[RailGate] = []
	var gears := 0
	var tricks: Array[TrickStep] = []
	for node in castle.get_node("Movers").get_children():
		if node is ShiftingStair:
			stairs.append(node)
		elif node is RailGate:
			gates.append(node)
		elif node is Gear:
			gears += 1
		elif node is TrickStep:
			tricks.append(node)
	t.check(stairs.size() >= 4 and gates.size() == stairs.size() * 2, "the Hall of Turning Stairs has shifting stairs with rail gates (%d, %d)" % [stairs.size(), gates.size()])
	t.check(gears >= 4 and tricks.size() >= 2, "the clockwork loft has gears and the shaft has trick steps (%d, %d)" % [gears, tricks.size()])
	if stairs.size() > 0:
		var st := stairs[0]
		var t0 := st.cycle() * 100.0 - st.phase   # the start of a cycle
		t.check(st.stop_at(t0 + 1.0) == 0 and st.stop_at(t0 + st.hold + st.move + 1.0) == 1 and st.stop_at(t0 + st.hold + 1.0) == -1,
			"a shifting stair rests at its stops and swings between them on the schedule")
		var twin: ShiftingStair = load("res://objects/setpieces/shifting_stair.tscn").instantiate()
		twin.stops = st.stops
		twin.hold = st.hold
		twin.move = st.move
		twin.phase = st.phase
		t.check(is_equal_approx(twin.yaw_at(12345.6), st.yaw_at(12345.6)), "two copies agree on the pose at the same moment")
		twin.free()
		# Ride it: pin the clock at stop 0, walk from the ring up to the tongue.
		for s in stairs:
			s.time_override = t0 + 2.0
		for i in range(4):
			await get_tree().physics_frame
		var gate_ok := true
		for g in gates:
			if g.stair == g.get_path_to(st) and g.is_open != (g.open_stop == 0):
				gate_ok = false
		t.check(gate_ok, "rail gates open only where the stair rests")
		var dir := st.global_transform.basis.x.normalized()
		var foot := st.global_position - dir * 2.0 + Vector3(0, 0.3, 0)
		await _spawn_player(foot)
		player.movement.set_external_move(Vector3(dir.x, 0, dir.z).normalized(), false)
		for i in range(int(10.0 * Engine.physics_ticks_per_second)):
			await get_tree().physics_frame
			if player.global_position.y > st.global_position.y + 8.8:
				break
		player.movement.set_external_move(Vector3.ZERO)
		await _wait(0.4)
		t.check(player.global_position.y > st.global_position.y + 8.8 and player.movement.is_grounded,
			"a shifting stair at rest carries a player up to the landing above (y %.1f)" % player.global_position.y)
	if tricks.size() > 0:
		await _spawn_player(tricks[0].global_position + Vector3(0, 0.6, 0))
		await _wait(0.3)
		t.check(player.movement.is_held(), "a trick step grips the foot")
		player.movement.request_jump()
		await _wait(0.1)
		t.check(not player.movement.is_held(), "a jump frees it")
	castle.queue_free()
	await get_tree().process_frame


func _test_day_night() -> void:
	t.section("Day and night")
	var clock := SchoolClock.new()
	clock.day_seconds = 3600.0
	t.check(is_equal_approx(clock.hours_at(0.0), 0.0) and is_equal_approx(clock.hours_at(1800.0), 12.0), "a school day is one day length of world time")
	clock.offset = clock.offset_for(123456.7, 14.5)
	t.check(absf(clock.hours_at(123456.7) - 14.5) < 0.001, "offset_for moves the clock to the asked hour")
	t.check(absf(clock.hours_at(123456.7 + 150.0) - 15.5) < 0.001, "and it keeps running from there")
	t.check(SchoolClock.phase_of(0.0) == SchoolClock.Phase.NIGHT and SchoolClock.phase_of(6.0) == SchoolClock.Phase.DAWN
		and SchoolClock.phase_of(12.0) == SchoolClock.Phase.DAY and SchoolClock.phase_of(20.0) == SchoolClock.Phase.DUSK,
		"phases: night, dawn, day, dusk")
	t.check(SchoolClock.format(7.09) == "07:05" and SchoolClock.format(23.99) == "23:59", "the clock reads hh:mm")
	t.check(is_equal_approx(SchoolClock.parse("14:30"), 14.5) and is_equal_approx(SchoolClock.parse("7"), 7.0)
		and SchoolClock.parse("25") < 0.0 and SchoolClock.parse("noon") < 0.0, "/time parses hh, hh:mm and refuses the rest")
	t.check(clock.apply({"day": 1200.0, "offset": 30.0}) and clock.day_seconds == 1200.0 and not clock.apply({"day": 1200.0, "offset": 30.0}),
		"the server's clock settings apply once")
	t.check(DayNightCycle.sun_direction(12.0).y > 0.8 and DayNightCycle.sun_direction(0.0).y < -0.8
		and absf(DayNightCycle.sun_direction(6.0).y) < 0.01 and DayNightCycle.sun_direction(6.0).x > 0.99, "the sun rises in the east and stands high at noon")

	# Offline /time moves the shared school clock.
	var saved_offset := NetworkManager.school_clock.offset
	var line := ChatCommands.run("/czas 13:15", null)
	t.check(absf(NetworkManager.school_hours() - 13.25) < 0.01, "/time 13:15 sets the clock offline (%s)" % line)
	ChatCommands.run("/time night", null)
	t.check(SchoolClock.is_night(NetworkManager.school_hours()), "/time night")
	t.check(ChatCommands.run("/time 99", null) == tr("CHEAT_TIME_USAGE"), "/time refuses a bad hour")
	NetworkManager.school_clock.offset = saved_offset

	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var cycle := castle.get_node_or_null("DayNightCycle") as DayNightCycle
	t.check(cycle != null and cycle.sky_light != null and cycle.fill_light != null and cycle.sky_material != null,
		"the castle lights itself from the school clock")
	if cycle != null and cycle.sky_light != null:
		cycle.time_override = 3.0   # start from a known phase (the real clock could be anywhere)
		cycle.refresh()
		var phases: Array[int] = []
		var on_phase := func(p: int) -> void: phases.append(p)
		GameEvents.time_phase_changed.connect(on_phase)
		cycle.time_override = 12.0
		cycle.refresh()
		var noon_ambient := cycle.environment.ambient_light_energy
		var sun := cycle.sky_light
		t.check(sun.visible and sun.light_energy > 1.0 and sun.light_color.b > 0.8, "noon: a bright white sun over the grounds (%.2f)" % sun.light_energy)
		t.check((-sun.global_basis.z).y < -0.8, "noon: the sun shines down from high up")
		t.check(cycle.daylight > 0.99 and cycle.sky_material.sky_cover_modulate.a < 0.01, "noon: full daylight, no stars")
		cycle.time_override = 0.0
		cycle.refresh()
		t.check(sun.visible and sun.light_energy < 0.5 and sun.light_color.b > sun.light_color.r, "midnight: the dim blue moon (%.2f)" % sun.light_energy)
		t.check(cycle.environment.ambient_light_energy < noon_ambient and cycle.sky_material.sky_cover_modulate.a > 0.99, "midnight: darker, with stars")
		t.check(phases.has(SchoolClock.Phase.DAY) and phases.has(SchoolClock.Phase.NIGHT), "phase changes reach GameEvents")
		GameEvents.time_phase_changed.disconnect(on_phase)
		cycle.time_override = 6.0
		cycle.refresh()
		t.check(sun.light_energy < 0.05, "the light fades out where sun and moon swap at the horizon")
		var e1 := cycle.sky_light.light_energy
		cycle.time_override = 6.75
		cycle.refresh()
		t.check(cycle.sky_light.light_energy > e1 and cycle.sky_light.light_color.r > cycle.sky_light.light_color.b, "the low morning sun is warm and rising")

	# Music follows the time of day.
	t.check(MusicDirector.track_for(SchoolClock.Phase.DAWN) == &"day" and MusicDirector.track_for(SchoolClock.Phase.DAY) == &"day"
		and MusicDirector.track_for(SchoolClock.Phase.DUSK) == &"night" and MusicDirector.track_for(SchoolClock.Phase.NIGHT) == &"night",
		"day music from dawn, night music from dusk")
	t.check(AudioServer.get_bus_index(&"Music") > 0, "there is a Music bus")
	var music := castle.get_node_or_null("MusicDirector") as MusicDirector
	t.check(music != null and music.cycle == cycle, "the castle plays music from its day/night cycle")
	if music != null and cycle != null:
		for track: StringName in MusicDirector.TRACKS:
			var stream := MusicDirector.TRACKS[track] as AudioStream
			t.check(stream != null and stream.get_length() > MusicDirector.LOOP_FADE * 4.0, "%s music is long enough to %s (%.0f s)" % [track, "play out" if MusicDirector.ONE_SHOT.has(track) else "loop", stream.get_length()])
		cycle.time_override = 12.0
		cycle.refresh()
		music.update()
		t.check(music.current == &"day", "noon plays the day music")
		cycle.time_override = 23.0
		cycle.refresh()
		music.update()
		var playing := music.find_children("*", "AudioStreamPlayer", false, false).filter(func(p: Node) -> bool: return (p as AudioStreamPlayer).playing)
		t.check(music.current == &"night" and playing.size() == 2, "night switches to the night music, crossfading from the day track")

		# Out on the grounds by day: the grounds music, after a short delay.
		t.check(MusicDirector.track_for(SchoolClock.Phase.DAY, true) == &"grounds" and MusicDirector.track_for(SchoolClock.Phase.NIGHT, true) == &"night",
			"grounds music outdoors by day, night music outdoors at night")
		var saved_tracker := music.tracker
		var fake := AreaTracker.new()
		var field := AreaZone.new()
		field.kind = "grounds"
		var yard := AreaZone.new()
		yard.kind = "outdoor"
		music.tracker = fake
		cycle.time_override = 12.0
		cycle.refresh()
		music.update(0.25)
		fake.current_zone = field
		music.update(1.0)
		t.check(music.current == &"day", "a step outside is not enough to change the music")
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"grounds" and music.outdoors, "staying out on the grounds plays the grounds music")
		fake.current_zone = yard
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"day", "a walled courtyard counts as the castle")
		fake.current_zone = field
		music.update(MusicDirector.OUTDOOR_DELAY)
		cycle.time_override = 23.0
		cycle.refresh()
		music.update(0.25)
		t.check(music.current == &"night", "night outdoors plays the night music")
		# A running lesson in the room: the lesson music, at any hour, after the same delay.
		t.check(MusicDirector.track_for(SchoolClock.Phase.NIGHT, false, true) == &"lesson", "a lesson plays the lesson music at any hour")
		var room := AreaZone.new()
		room.area_id = &"class_test"
		room.kind = "classroom"
		music.lessons_override = {"class_test": {"subject": "elixirs"}}
		fake.current_zone = room
		music.update(MusicDirector.OUTDOOR_DELAY)
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"lesson" and music.in_lesson, "inside a running lesson the lesson music plays")
		music.lessons_override = {}
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"night" and not music.in_lesson, "when the lesson ends the room goes back to the clock's music")
		music.lessons_override = {"class_other": {"subject": "elixirs"}}
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"night", "a lesson in another room changes nothing")
		# Events (feasts, duels, mysteries) cue their track over everything else.
		music.event_track = &"feast"
		music.update(0.25)
		t.check(music.current == &"feast", "an event track plays at once")
		music.event_track = &""
		music.update(0.25)
		t.check(music.current == &"night", "clearing the event goes back to the clock's music")
		# On a broom: the flying music at any hour, after the same delay.
		t.check(MusicDirector.track_for(SchoolClock.Phase.DAY, true, false, true) == &"flying"
			and MusicDirector.track_for(SchoolClock.Phase.NIGHT, false, false, true) == &"flying", "a broom plays the flying music at any hour")
		var saved_movement := music.movement
		var rider := PlayerMovement.new()
		music.movement = rider
		rider.is_flying = true
		music.update(1.0)
		t.check(music.current == &"night", "a short hop on the broom does not change the music")
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"flying" and music.flying, "staying on the broom plays the flying music")
		rider.is_flying = false
		music.update(MusicDirector.OUTDOOR_DELAY)
		t.check(music.current == &"night" and not music.flying, "landing goes back to the clock's music")
		music.movement = saved_movement
		rider.free()
		# One-shot tracks (ceremony, fanfare) play once and hand back to the clock.
		t.check(MusicDirector.ONE_SHOT.has(&"sorting") and MusicDirector.ONE_SHOT.has(&"house_cup"), "the sorting and house cup music play once")
		music.event_track = &"house_cup"
		music.update(0.25)
		var cup_player: AudioStreamPlayer = null
		for child in music.find_children("*", "AudioStreamPlayer", false, false):
			if (child as AudioStreamPlayer).stream == MusicDirector.TRACKS[&"house_cup"]:
				cup_player = child
		t.check(music.current == &"house_cup" and cup_player != null, "the house cup fanfare plays")
		if cup_player != null:
			cup_player.seek(cup_player.stream.get_length() - 0.1)
			await _wait(0.05)
		music.update(0.25)
		t.check(music.event_track.is_empty(), "the fanfare clears itself when it ends, it does not loop")
		music.update(0.25)
		t.check(music.current == &"night", "after the fanfare the clock's music returns")
		music.lessons_override = null
		room.free()
		music.tracker = saved_tracker
		fake.free()
		field.free()
		yard.free()

	# The lamplighter: daylit rooms' candles go out by day and are lit at dusk.
	t.check(Lamplighter.burns_at(23.0, 0.5) and Lamplighter.burns_at(3.0, 0.5) and not Lamplighter.burns_at(12.0, 0.0)
		and Lamplighter.burns_at(7.2, 0.5) and not Lamplighter.burns_at(7.6, 0.5) and Lamplighter.burns_at(19.6, 0.5)
		and not Lamplighter.burns_at(19.2, 0.5), "daylit lights burn from dusk (plus their delay) until after dawn")
	t.check(Lamplighter.stagger_for("great_hall/torch_1") == Lamplighter.stagger_for("great_hall/torch_1")
		and Lamplighter.stagger_for("a") <= Lamplighter.STAGGER_HOURS, "each light's delay is fixed and small")
	var daylit_torches := castle.find_children("*", "WallTorch", true, false).filter(func(n: Node) -> bool: return (n as WallTorch).daylit)
	var dark_torches := castle.find_children("*", "WallTorch", true, false).filter(func(n: Node) -> bool: return not (n as WallTorch).daylit)
	var daylit_chandeliers := castle.find_children("*", "Chandelier", true, false).filter(func(n: Node) -> bool: return (n as Chandelier).daylit)
	t.check(daylit_torches.size() > 0 and dark_torches.size() > 0 and daylit_chandeliers.size() > 0,
		"rooms with windows have daylit lights, windowless ones keep theirs (%d / %d torches)" % [daylit_torches.size(), dark_torches.size()])
	if cycle != null and daylit_torches.size() > 0 and dark_torches.size() > 0 and daylit_chandeliers.size() > 0:
		var torch := daylit_torches[0] as WallTorch
		var chandelier := daylit_chandeliers[0] as Chandelier
		var dungeon_torch := dark_torches[0] as WallTorch
		cycle.time_override = 13.0
		cycle.refresh()
		t.check(not torch.burning() and not torch.get_node("Flame").visible and not chandelier.get_node("Candles").visible,
			"at 13:00 the daylit torch and chandelier are out")
		t.check(dungeon_torch.burning() and dungeon_torch.get_node("Flame").visible, "a windowless room's torch burns by day")
		cycle.time_override = 23.0
		cycle.refresh()
		t.check(torch.burning() and torch.get_node("Flame").visible and chandelier.get_node("Candles").visible, "at 23:00 they are lit again")
		torch.set_lit(false)
		t.check(not torch.burning(), "a lit lamp put out by a spell stays out")
		torch.set_lit(true)
		cycle.time_override = NAN
	castle.queue_free()

	# The main theme plays behind the menu, whatever the time, and stops for the world.
	var game := (load("res://core/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var menu_music := game.get_node_or_null("MenuMusic") as MusicDirector
	t.check(menu_music != null and menu_music.current == &"main_theme", "the menu plays the main theme")
	if menu_music != null:
		menu_music.stop(0.1)
		t.check(menu_music.current.is_empty() and not menu_music.is_processing(), "leaving the menu stops the main theme")
		menu_music.start()
		t.check(menu_music.current == &"main_theme", "back at the menu it starts again")
		menu_music.stop(0.05)
		await _wait(0.2)
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_chat() -> void:
	t.section("Chat")
	t.check(ChatCommands.parse_chat("hello").is_empty() and ChatCommands.parse_chat("/time 12").is_empty(), "plain lines and cheats are not chat modes")
	var w := ChatCommands.parse_chat("/sz psst over here")
	t.check(w.mode == "whisper" and w.text == "psst over here", "/sz whispers")
	t.check(ChatCommands.parse_chat("/s HELLO").mode == "shout" and ChatCommands.parse_chat("/krzyk hej").text == "hej", "/s and /krzyk shout")
	var dm := ChatCommands.parse_chat("/pw Ola see you at lunch")
	t.check(dm.mode == "dm" and dm.to == "Ola" and dm.text == "see you at lunch", "/pw name text writes a direct message")
	var quoted := ChatCommands.parse_chat("/msg \"Anna Maria\" hi there")
	t.check(quoted.to == "Anna Maria" and quoted.text == "hi there", "a name with spaces goes in quotes")
	var reply := ChatCommands.parse_chat("/r thanks", "Kuba")
	t.check(reply.mode == "dm" and reply.to == "Kuba" and reply.text == "thanks", "/r answers the last sender")
	t.check(ChatCommands.parse_chat("/msg").to == "" and ChatCommands.parse_chat("/r hi").to == "", "a DM without a recipient is recognised (usage shown)")
	var ChatPanelScript: GDScript = load("res://ui/chat/chat_panel.gd")
	var say_line: String = ChatPanelScript.line_bbcode({"mode": "say", "name": "Ola", "text": "hi [b]", "self": false})
	t.check(say_line.contains("[Ola]") and not say_line.contains("[b]"), "a say line names the speaker and escapes BBCode (%s)" % say_line)
	t.check(ChatPanelScript.line_bbcode({"mode": "whisper", "name": "Ola", "text": "psst"}).contains(tr("CHAT_WHISPERS"))
		and ChatPanelScript.line_bbcode({"mode": "shout", "name": "Ola", "text": "HEY"}).contains(tr("CHAT_SHOUTS")), "whispers and shouts are marked")
	var mail_line: String = ChatPanelScript.line_bbcode({"mode": "dm", "name": "Kuba", "text": "hi", "self": false, "mail": true})
	t.check(mail_line.contains(tr("CHAT_DM_FROM") % "Kuba") and mail_line.contains(tr("CHAT_DM_FROM_MAIL")), "a DM from the mailbox says so")
	t.check(ChatPanelScript.line_bbcode({"mode": "dm", "name": "Me", "to_name": "Kuba", "text": "hi", "self": true}).contains(tr("CHAT_DM_TO") % "Kuba"), "our own DM names its recipient")
	t.check(ChatManager.result_text("too_soon", {"mode": "shout", "wait": 7}) == tr("CHAT_SHOUT_TOO_SOON") % 7
		and ChatManager.result_text("no_such_player", {"to_name": "X"}) == tr("CHAT_DM_NO_PLAYER") % "X", "refusals read as sentences")
	var p := await _spawn_player(Vector3(0, 1, 0))
	p.say("Good morning!", "say")
	t.check(p.speech_bubble.visible and p.speech_bubble.text == "Good morning!" and p.speech_bubble.visibility_range_end == SpeechBubble.STYLE.say.range, "saying something shows a bubble over the head")
	p.say("PSST", "whisper")
	t.check(p.speech_bubble.visibility_range_end < 10.0 and p.speech_bubble.font_size < SpeechBubble.STYLE.say.size, "a whisper bubble is small and only readable up close")
	await _wait(10.0)
	t.check(not p.speech_bubble.visible, "the bubble fades after a few seconds")


func _test_gestures() -> void:
	t.section("Gestures and seats")
	var bench := "res://objects/environment/props/student_bench.tscn"
	var at := Transform3D(Basis.IDENTITY, Vector3(10, 0, 10))
	var seats := Seats.for_instance(bench, at)
	t.check(seats.size() == 2 and is_equal_approx((seats[0].t as Transform3D).origin.y, 0.54) and seats[0].both, "a bench has two seats, usable both ways")
	var from_front := Seats.facing_from(seats[0], Vector3(10, 0, 8))   # standing on its -Z side
	var from_back := Seats.facing_from(seats[0], Vector3(10, 0, 12))
	t.check((-from_front.basis.z).z > 0.9 and (-from_back.basis.z).z < -0.9, "a bench sitter faces away from the side they came from")
	var chair := Seats.for_instance("res://objects/environment/placeholders/chair.tscn", at)[0]
	t.check(not chair.both and (-(chair.t as Transform3D).basis.z).z > 0.9, "a chair faces its front (+Z)")

	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var all_seats := Seats.all(get_tree())
	t.check(all_seats.size() > 200, "the castle's benches, chairs and sofas have seats (%d)" % all_seats.size())
	var p := await _spawn_player(Vector3(0, 1, 0), "apprentice_f")
	# Stand next to a seat (the first one, wherever it is) and sit.
	var first: Transform3D = all_seats[0].t
	p.global_position = first.origin - first.basis.z * -0.9 + Vector3(0, -first.origin.y + 0.05, 0) + Vector3(0, first.origin.y - 0.54, 0)
	await _wait(0.3)
	t.check(p.seat_nearby(), "a seat is within reach")
	t.check(p.try_sit() and p.gestures.is_sitting() and p.collision_mask == 0 and not p.movement.is_physics_processing(),
		"interacting near a seat sits down (no collision, movement off)")
	var seat_h := p.gestures.seat_height
	t.check(seat_h > 0.3 and seat_h < 0.8, "the seat height is measured from the floor (%.2f m)" % seat_h)
	await _wait(0.5)
	t.check(p.gestures.pose != null and p.gestures.pose.influence > 0.9 and p.gestures.pose.seated, "the sitting pose blends in")
	p.gestures.play(&"raise_hand")
	t.check(p.gestures.is_sitting() and p.gestures.current == &"raise_hand", "a seated student raises a hand without standing up")
	p.gestures.play(&"raise_hand")
	t.check(p.gestures.is_sitting() and p.gestures.current == &"", "and lowers it, still seated")
	p.gestures.stand()
	t.check(not p.gestures.is_sitting() and p.collision_mask == Player.LAYER_WORLD and p.movement.is_physics_processing(), "standing up restores collision and movement")
	castle.queue_free()
	await get_tree().process_frame

	p = await _spawn_player(Vector3(0, 1, 0))
	t.check(p.gestures.play(&"wave") and p.gestures.current == &"wave", "a wave plays")
	await _wait(Gestures.ONE_SHOT[&"wave"] + 0.3)
	t.check(p.gestures.current == &"", "and ends by itself")
	p.gestures.play(&"raise_hand")
	await _wait(3.0)
	t.check(p.gestures.current == &"raise_hand", "a raised hand stays up")
	var ProfessorPanelScript: GDScript = load("res://ui/school/professor_panel.gd")
	t.check(ProfessorPanelScript._hand_raised(p), "the lesson panel sees the raised hand")
	p.gestures.play(&"raise_hand")
	t.check(p.gestures.current == &"", "pressing it again lowers the hand")
	ChatCommands.run("/uklon", p)
	await _wait(0.1)
	t.check(p.gestures.current == &"bow", "/ukłon bows (%s)" % p.gestures.current)
	t.check(ChatCommands.run("/sit", p) == tr("GESTURE_NO_SEAT"), "/sit with no seat nearby says so")
	p.gestures.set_remote(&"notes", 0.0)
	t.check(p.gestures.current == &"notes", "a remote snapshot's gesture shows")
	p.gestures.set_remote(&"teleport", 0.0)
	t.check(p.gestures.current == &"", "unknown gestures from the network are ignored")


func _test_board_and_quiz() -> void:
	t.section("Board and quiz")
	var ProfessorPanelScript: GDScript = load("res://ui/school/professor_panel.gd")
	var parsed: Dictionary = ProfessorPanelScript.parse_choices("Galewind\n*Uplift\nEmberkindle")
	t.check(parsed.choices.size() == 3 and parsed.correct == 1 and parsed.choices[1] == "Uplift", "choices one per line, * marks the right one")
	parsed = ProfessorPanelScript.parse_choices(" a | *b ")
	t.check(parsed.choices == PackedStringArray(["a", "b"]) and parsed.correct == 1, "or separated by | (a plan line)")
	t.check(ProfessorPanelScript.parse_choices("").choices.is_empty(), "no choices: an open question")
	t.check(QuizPanel.status_text({"id": 1, "choices": ["a", "b"], "open": true}) == tr("QUIZ_HINT_CHOICES")
		and QuizPanel.status_text({"id": 1, "choices": [], "open": true}) == tr("QUIZ_HINT_OPEN"), "the question says how to answer")
	t.check(QuizPanel.status_text({"id": 1, "open": true, "answer": 1}) == tr("QUIZ_ANSWERED")
		and QuizPanel.status_text({"id": 1, "open": false, "answer": 1, "right": true}) == tr("QUIZ_RIGHT")
		and QuizPanel.status_text({"id": 1, "open": false}) == tr("QUIZ_CLOSED_NO_ANSWER"), "and how it went")
	var tt := Timetable.new()
	tt.apply({"tz": 0, "slots": [{"id": "x", "k": "lesson", "s": "sigilcraft", "a": "class_sigilcraft", "t0": 2000.0, "t1": 3000.0}]})
	var idle := ClassroomBoards.board_text_for("class_sigilcraft", {}, tt, 1000.0)
	t.check(idle.contains(tr("SUBJECT_SIGILCRAFT_NAME")) and idle.contains(tr("BOARD_NEXT_LESSON").get_slice("%", 0).strip_edges()), "an idle board names the subject and the next lesson (%s)" % idle.replace("\n", " | "))
	t.check(ClassroomBoards.board_text_for("class_sigilcraft", {"class_sigilcraft": {"board": "Sigils, week one"}}, tt, 1000.0) == "Sigils, week one", "during a lesson it shows what the professor wrote")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var boards := castle.get_node_or_null("ClassroomBoards") as ClassroomBoards
	var classrooms := get_tree().get_nodes_in_group(AreaZone.GROUP).filter(func(z: Node) -> bool: return (z as AreaZone).kind == "classroom")
	t.check(boards != null and boards.labels.size() >= classrooms.size() - 2 and boards.labels.has("class_sigilcraft"),
		"every classroom's board can be written on (%d boards, %d classrooms)" % [boards.labels.size() if boards else 0, classrooms.size()])
	if boards != null and boards.labels.has("class_sigilcraft"):
		var label: Label3D = boards.labels["class_sigilcraft"]
		var zone: AreaZone = classrooms.filter(func(z: Node) -> bool: return str((z as AreaZone).area_id) == "class_sigilcraft")[0]
		var to_room := (zone.global_position - label.global_position)
		to_room.y = 0.0
		t.check(label.global_basis.z.dot(to_room.normalized()) > 0.7, "the chalk text faces into the room")
	castle.queue_free()


func _test_practicals() -> void:
	t.section("Practicals")
	var ProfessorPanelScript: GDScript = load("res://ui/school/professor_panel.gd")
	t.check(ProfessorPanelScript.practical_progress_text({"spell": ""}) == tr("PRACTICAL_NONE"), "no practical running")
	var text: String = ProfessorPanelScript.practical_progress_text({"spell": "uplift", "hits": 3, "students": [{"name": "Ola", "progress": 2}, {"name": "Kuba", "done": true}]})
	t.check(text.contains(tr("SPELL_UPLIFT_NAME")) and text.contains("Ola 2/3") and text.contains("Kuba ✓"), "the professor sees everyone's progress (%s)" % text.replace("\n", " | "))
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var targets := castle.find_children("*", "PracticeTarget", true, false)
	var zones := {}
	for z in get_tree().get_nodes_in_group(AreaZone.GROUP):
		zones[str((z as AreaZone).area_id)] = z
	var misplaced: Array[String] = []
	for target: PracticeTarget in targets:
		var area := (target.object_id as String).get_slice("/", 0)
		var zone: AreaZone = zones.get(area)
		var local := zone.global_transform.affine_inverse() * target.global_position if zone != null else Vector3.INF
		var to_centre := zone.global_position - target.global_position if zone != null else Vector3.ZERO
		to_centre.y = 0.0
		if zone == null or absf(local.x) > zone.size.x / 2.0 or absf(local.z) > zone.size.z / 2.0 or target.global_basis.z.dot(to_centre.normalized()) < 0.2:
			misplaced.append(target.object_id)
	t.check(targets.size() >= 12 and misplaced.is_empty(), "every classroom has a practice target inside it, facing the class (%d, %s)" % [targets.size(), str(misplaced)])
	var p := await _spawn_player(Vector3(0, 1, 0))
	var spawner := PlayerSpawner.new()
	add_child(spawner)
	spawner.local_player = p
	NetworkManager.practical_changed.emit({"spell": "uplift", "hits": 2, "progress": 0})
	t.check(p.spell_caster.knows(&"uplift") and p.spell_caster.equipped_spell.id == &"uplift", "a practical puts its spell on the hotbar for practice")
	NetworkManager.practical_changed.emit({})
	t.check(not p.spell_caster.knows(&"uplift"), "and takes it away when the practical ends without a grant")
	spawner.queue_free()
	castle.queue_free()


func _test_self_study() -> void:
	t.section("Self-study")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/self_study.json"))
	var problems: Array[String] = []
	var text_ok := func(v: Variant) -> bool: return v is Dictionary and str(v.get("pl", "")) != "" and str(v.get("en", "")) != ""
	if not data is Dictionary or not text_ok.call(data.get("host")):
		problems.append("host")
	var plans: Dictionary = data.get("plans", {}) if data is Dictionary else {}
	for subject: String in plans:
		var def := SubjectRegistry.load_definition(subject)
		if def == null:
			problems.append("unknown subject " + subject)
			continue
		for s: Dictionary in plans[subject].get("steps", []):
			if s.has("say") or s.has("board"):
				if not text_ok.call(s.get("say", s.get("board"))):
					problems.append(subject + ": text")
			elif s.has("quiz"):
				var choices: Array = s.get("choices", [])
				if not text_ok.call(s.quiz) or choices.size() < 2 or not choices.all(func(c: Variant) -> bool: return text_ok.call(c)) \
						or int(s.get("correct", -1)) < 0 or int(s.get("correct", -1)) >= choices.size():
					problems.append(subject + ": quiz")
			elif s.has("practical"):
				if not def.spells().has(str(s.practical)):
					problems.append(subject + ": practical " + str(s.practical))
			else:
				problems.append(subject + ": unknown step")
	t.check(plans.size() == SubjectRegistry.SUBJECT_IDS.size() and problems.is_empty(),
		"self_study.json: a valid plan for every subject, every text in pl and en (%d plans, %s)" % [plans.size(), str(problems)])
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/school_rules.json"))
	t.check(rules is Dictionary and not (rules as Dictionary).has("self_study_spells") or (rules.self_study_spells as Array).all(func(id: Variant) -> bool: return SpellRegistry.load_definition(str(id)) != null),
		"self_study_spells names only real spells (owner decision: none by default)")
	var lessons := {"class_sigilcraft": {"board": "Zaklęcia", "board_i18n": {"pl": "Zaklęcia", "en": "Charms"}, "auto": true}}
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	t.check(ClassroomBoards.board_text_for("class_sigilcraft", lessons, Timetable.new(), 0.0) == "Charms", "a self-study board shows in the player's language")
	TranslationServer.set_locale(previous)


func _test_character_look() -> void:
	t.section("Character look")
	var clean := CharacterLook.sanitize({"body": "nobody", "skin": 99, "robe": -3})
	t.check(clean.body == CharacterRegistry.DEFAULT and clean.skin == CharacterLook.SKIN_TONES.size() - 1 and clean.robe == 0 and not clean.set, "looks are clamped to what exists")
	var p := await _spawn_player(Vector3(0, 1, 0), "apprentice_m")
	p.set_look({"body": "apprentice_f", "skin": 2, "robe": 3, "set": true})
	await get_tree().process_frame
	t.check(p.character_id == "apprentice_f" and p.visual.scene_file_path.ends_with("apprentice_f.tscn"), "a look's body swaps the visual")
	t.check(p.gestures.pose != null and p.gestures.pose.get_skeleton() != null, "gestures follow the new body")
	var mats: Array = []
	for node in p.visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(s) is ShaderMaterial:
				mats.append(mi.get_surface_override_material(s))
	t.check(not mats.is_empty() and (mats[0] as ShaderMaterial).get_shader_parameter("skin_tint") == CharacterLook.SKIN_TONES[2]
		and (mats[0] as ShaderMaterial).get_shader_parameter("house_amount") == 0.0, "skin and robe go to the look shader; unsorted keeps the violet trim")
	if not mats.is_empty():
		p.set_profile("student", 3)
		t.check((mats[0] as ShaderMaterial).get_shader_parameter("house_amount") == 1.0
			and (mats[0] as ShaderMaterial).get_shader_parameter("house_color") == CharacterProfile.house_color(3), "sorting puts the house colour on the trim")
	var profile := CharacterProfile.sanitize({"appearance": {"body": "apprentice_f", "skin": 1, "set": true}})
	t.check(profile.appearance.body == "apprentice_f" and profile.appearance.set, "the server profile carries the look")


func _test_meals() -> void:
	t.section("Meals")
	t.check(FeastMeals.meal_at(7.5) == "MEAL_BREAKFAST" and FeastMeals.meal_at(12.2) == "MEAL_LUNCH" and FeastMeals.meal_at(19.0) == "MEAL_DINNER"
		and FeastMeals.meal_at(10.0) == "" and FeastMeals.meal_at(23.0) == "", "breakfast, lunch and dinner by the school clock")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var meals := castle.get_node_or_null("FeastMeals") as FeastMeals
	var cycle := castle.get_node("DayNightCycle") as DayNightCycle
	t.check(meals != null and meals.tables.size() >= 8, "the feast tables are known (%d)" % (meals.tables.size() if meals else 0))
	if meals == null or meals.tables.is_empty():
		castle.queue_free()
		return
	cycle.time_override = 15.0
	cycle.refresh()
	meals.update(true)
	var dishes := meals.get_children().filter(func(n: Node) -> bool: return n is MultiMeshInstance3D)
	t.check(meals.serving == "" and dishes.all(func(d: Node) -> bool: return not (d as Node3D).visible), "between meals the tables are bare")
	var p := await _spawn_player(Vector3(0, 1, 0), "apprentice_m")
	p.global_position = meals.tables[0] * Vector3(0.5, 0.05, -1.6)
	await _wait(0.3)
	t.check(p.try_sit() and meals.near_table(p.global_position), "a student sits at a feast bench")
	cycle.time_override = 18.7
	cycle.refresh()
	meals.update(false)
	t.check(meals.serving == "MEAL_DINNER" and dishes.all(func(d: Node) -> bool: return (d as Node3D).visible), "dinner appears on the tables")
	t.check(p.gestures.current == &"eat" and p.gestures.is_sitting(), "and the seated student eats")
	var music := castle.get_node("MusicDirector") as MusicDirector
	t.check(p.area_tracker.current_area_id() != FeastMeals.FEAST_AREA or music.event_track == &"feast", "the feast music plays in the great hall during the meal")
	cycle.time_override = 21.0
	cycle.refresh()
	meals.update(false)
	t.check(p.gestures.current == &"" and p.gestures.is_sitting() and music.event_track != &"feast", "after dinner the plates go, the student stops eating and the feast music ends")
	p.gestures.stand()
	cycle.time_override = NAN
	castle.queue_free()


func _test_mastery() -> void:
	t.section("Spell mastery")
	t.check(SpellMastery.level_of(0) == 0 and SpellMastery.level_of(20) == 1 and SpellMastery.level_of(149) == 2 and SpellMastery.level_of(500) == 3, "points make ranks")
	t.check(SpellMastery.to_next(10) == 10 and SpellMastery.to_next(1000) == 0, "points to the next rank")
	var p := await _spawn_player(Vector3(0, 1, 0))
	p.spell_caster.learn_spell(ARCANE_PULSE)
	p.spell_caster.equip(ARCANE_PULSE)
	p.spell_caster.try_cast()
	var novice := p.spell_caster.get_cooldown_remaining(ARCANE_PULSE)
	await _wait(1.5)
	p.spell_caster.mastery = {"arcane_pulse": 200}
	p.spell_caster.try_cast()
	var master := p.spell_caster.get_cooldown_remaining(ARCANE_PULSE)
	t.check(master < novice and is_equal_approx(p.spell_caster.mastery_level(ARCANE_PULSE), 3), "a master casts with a shorter cooldown (%.2f vs %.2f)" % [master, novice])
	t.check(CharacterProfile.sanitize({"mastery": {"arcane_pulse": 12, "bogus": 5}}).mastery == {"arcane_pulse": 12}, "the profile keeps mastery of real spells only")


func _test_runes() -> void:
	t.section("Rune tracing")
	t.check(RuneTracer.strokes_of([Vector2(60, 0)]) == "R" and RuneTracer.strokes_of([Vector2(0, -50), Vector2(0, -50), Vector2(50, 5)]) == "UR",
		"mouse paths become strokes, repeats collapsed")
	t.check(RuneTracer.matches("glowmote", "UR") and not RuneTracer.matches("glowmote", "RU") and not RuneTracer.matches("glowmote", ""), "a trace matches only its spell's rune")
	var seen := {}
	var ok := true
	for id: String in RuneTracer.RUNES:
		ok = ok and SpellRegistry.load_definition(id) != null and not seen.has(RuneTracer.RUNES[id])
		seen[RuneTracer.RUNES[id]] = true
	t.check(ok and RuneTracer.RUNES.size() == SpellRegistry.all().size(), "every spell has its own rune")
	var before := GameSession.trace_casting
	t.check(ChatCommands.run("/runy", null) == (tr("RUNES_OFF") if before else tr("RUNES_ON")), "/runes toggles tracing")
	GameSession.set_trace_casting(before)


func _test_journal() -> void:
	t.section("Journal")
	t.check(Journal.header_text({"year": 2}, 3) == tr("YEAR_2") + " · " + tr("HOUSE_3_NAME") and Journal.header_text({}, 0) == tr("YEAR_1"), "the journal names the year and house")
	var rec := Journal.record_bbcode({"subjects": {"sigilcraft": {"attended": 3, "self_study": 1, "quiz_right": 4, "quiz_total": 5, "practicals": 2}}})
	t.check(rec.contains(tr("SUBJECT_SIGILCRAFT_NAME")) and rec.contains(tr("JOURNAL_RECORD_LINE") % [3, 1, 4, 5, 2]), "the record lists each subject (%s)" % rec.replace("\n", " | "))
	t.check(Journal.record_bbcode({}) == tr("JOURNAL_RECORD_EMPTY"), "an empty record says so")
	var hw := Journal.homework_bbcode([
		{"id": "a", "subject": "sigilcraft", "by_name": "Vexley", "text": "Two uses", "due": 2000.0},
		{"id": "b", "subject": "sigilcraft", "by_name": "Vexley", "text": "Three uses", "due": 2000.0, "answer": {"text": "x", "grade": 5, "comment": "good"}}], 1000.0)
	t.check(hw.contains(tr("HOMEWORK_TODO")) and hw.contains(tr("HOMEWORK_GRADED") % [5, "good"]), "homework shows what to do and the grades (%s)" % hw.replace("\n", " | "))
	t.check(Journal.homework_bbcode([], 0.0) == tr("HOMEWORK_NONE"), "no homework says so")
	t.check(Journal.discoveries_bbcode(["loft", "map:loft", "founders_tale"]) == tr("JOURNAL_DISCOVERIES") % [2, 1], "discoveries and hidden rooms are counted")
	var caster := SpellCaster.new()
	caster.learn_spell(ARCANE_PULSE)
	caster.mastery = {"arcane_pulse": 25}
	var spells := Journal.spells_bbcode(caster)
	t.check(spells.contains(tr(ARCANE_PULSE.display_name)) and spells.contains(tr("MASTERY_ADEPT")) and spells.contains("→"), "the spellbook shows rank and rune (%s)" % spells.replace("\n", " | "))
	caster.free()


func _test_grades() -> void:
	t.section("Grades")
	t.check(SchoolGrades.grade({}) == 0, "no lessons, no grade")
	var good := {"attended": 6, "quiz_right": 9, "quiz_total": 10, "practicals": 2, "homework_count": 2, "homework_points": 11, "exam_right": 5, "exam_total": 5}
	var poor := {"attended": 1, "quiz_right": 0, "quiz_total": 6, "homework_count": 1, "homework_points": 1}
	t.check(SchoolGrades.grade(good) >= 5 and SchoolGrades.grade(poor) <= 2, "a strong record grades high, a weak one low (%d, %d)" % [SchoolGrades.grade(good), SchoolGrades.grade(poor)])
	t.check(SchoolGrades.grade({"attended": 3}) >= 1 and SchoolGrades.grade({"attended": 3}) <= 6, "missing parts are left out, not counted as zero")
	t.check(Journal.record_bbcode({"subjects": {"sigilcraft": good}}).contains(tr("JOURNAL_GRADE") % SchoolGrades.grade(good)), "the journal shows the grade")


func _test_books() -> void:
	t.section("Library books")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var books := castle.find_children("*", "LoreBook", true, false)
	t.check(books.size() >= 6 and books.all(func(b: Node) -> bool: return (b as LoreBook).page_keys().size() >= 2 and tr("BOOK_%s_TITLE" % (b as LoreBook).book) != "BOOK_%s_TITLE" % (b as LoreBook).book),
		"the library holds readable books, each titled with two or more pages (%d)" % books.size())
	var panel := BookPanel.new()
	add_child(panel)
	var book := books[0] as LoreBook
	book._on_interacted(null)
	t.check(panel.is_open and panel.pages.size() == book.page_keys().size() and GameSession.ui_input_captured, "reading a book opens it")
	panel.turn(1)
	t.check(panel.page == 1, "pages turn")
	panel.close()
	t.check(not GameSession.ui_input_captured, "and it closes")
	panel.queue_free()
	castle.queue_free()


func _test_prefects() -> void:
	t.section("Prefects")
	t.check(CharacterProfile.sanitize_role("prefect") == CharacterProfile.ROLE_PREFECT and CharacterProfile.title_key("prefect") == "ROLE_PREFECT_TITLE"
		and not CharacterProfile.is_staff("prefect"), "prefect is a role with a title, not staff")
	var door := HOUSE_DOOR_SCENE.instantiate() as HouseDoor
	door.house = 2
	add_child(door)
	var p := await _spawn_player(Vector3(0, 1, 0))
	p.house = 3
	t.check(not door.admits(p), "another house's door stays shut")
	NetworkManager.guest_passes[2] = NetworkManager.server_time() + 60.0
	t.check(door.admits(p), "a prefect's guest pass opens it")
	NetworkManager.guest_passes[2] = NetworkManager.server_time() - 1.0
	t.check(not door.admits(p), "until the pass runs out")
	NetworkManager.guest_passes.clear()
	door.queue_free()
	t.check(ChatCommands.run("/odejmij 2", null) == tr("DEDUCT_USAGE") and ChatCommands.run("/gosc", null) == tr("GUEST_USAGE"), "prefect commands explain themselves")


func _test_timetable() -> void:
	t.section("Timetable")
	# 2026-10-12 was a Monday; school time is UTC+2 (summer time) in this payload.
	var monday := 1791763200.0   # 2026-10-12 (a Monday) 00:00 UTC
	var tt := Timetable.new()
	t.check(not tt.received and NoticeBoard.board_text(tt, monday, 5).contains(tr("TIMETABLE_OFFLINE")), "offline the board says lessons are online")
	var charms := monday + 16 * 3600.0   # 18:00 school time
	tt.apply({"tz": 120, "slots": [
		{"id": "mon_transfiguration", "k": "lesson", "s": "shapeshaping", "a": "class_shapeshaping", "p": "", "t0": charms + 3600.0, "t1": charms + 3600.0 + 2700.0},
		{"id": "mon_charms", "k": "lesson", "s": "sigilcraft", "a": "class_sigilcraft", "p": "Vexley", "t0": charms, "t1": charms + 2700.0},
		{"id": "sun_study", "k": "study", "s": "", "a": "library", "p": "", "t0": charms + 6 * 86400.0, "t1": charms + 6 * 86400.0 + 5400.0},
		{"id": "broken", "t0": 10.0, "t1": 5.0}]})
	t.check(tt.received and tt.entries.size() == 3 and tt.entries[0].id == "mon_charms", "the server's slots are kept in start order, broken ones dropped")
	var st := tt.school_time(charms)
	t.check(st.weekday == 0 and st.hour == 18 and st.minute == 0 and tt.clock_text(charms) == "18:00" and tt.day_key(charms) == "DAY_MON",
		"times read in school time (Monday 18:00)")
	t.check(tt.next_after(charms - 60.0).id == "mon_charms" and tt.current(charms + 60.0, "class_sigilcraft").id == "mon_charms"
		and tt.current(charms + 60.0, "library").is_empty(), "next and running lessons")
	var events := tt.events_between(charms - 400.0, charms + 10.0)
	t.check(events.size() == 2 and events[0].event == "warn" and events[1].event == "start", "the bell warns 5 minutes before and rings at the start")
	t.check(tt.events_between(charms + 2690.0, charms + 2710.0)[0].event == "end", "and at the end")
	t.check(Timetable.title_of(tt.entries[2]) == tr("TIMETABLE_STUDY") and Timetable.title_of(tt.entries[0]) == tr("SUBJECT_SIGILCRAFT_NAME"), "entry titles")
	var board := NoticeBoard.board_text(tt, charms + 60.0, 5)
	t.check(board.contains(tr("TIMETABLE_NOW") + "   " + tr("SUBJECT_SIGILCRAFT_NAME")) and board.contains("19:00"), "the board marks the running lesson and lists the next (%s)" % board.replace("\n", " | "))
	t.check(tt.status_line(charms - 600.0) == tr("HUD_LESSON_NEXT") % [tr("SUBJECT_SIGILCRAFT_NAME"), "18:00"]
		and tt.status_line(charms + 60.0) == tr("HUD_LESSON_NOW") % [tr("SUBJECT_SIGILCRAFT_NAME"), "18:45"], "the HUD shows the running or next lesson")
	t.check(TimetablePanel.week_bbcode(tt, charms - 600.0, get_tree()).contains(tr("DAY_SUN_LONG")), "the week panel groups by day")

	# The school calendar (terms, breaks, exam weeks) rides along with the timetable.
	t.check(tt.calendar_line() == "", "no calendar, no calendar line")
	var cal_tt := Timetable.new()
	cal_tt.apply({"tz": 60, "slots": [{"id": "exam", "k": "lesson", "s": "sigilcraft", "a": "class_sigilcraft", "t0": charms, "t1": charms + 60.0, "x": true}],
		"cal": {"term": "TERM_AUTUMN", "week": 15, "exam": true}})
	t.check(cal_tt.calendar_line() == tr("CALENDAR_TERM_WEEK") % [tr("TERM_AUTUMN"), 15] + " · " + tr("CALENDAR_EXAMS") and cal_tt.entries[0].exam,
		"a term week with exams (%s)" % cal_tt.calendar_line())
	t.check(TimetablePanel.week_bbcode(cal_tt, charms - 600.0, get_tree()).contains(tr("TIMETABLE_EXAM"))
		and NoticeBoard.board_text(cal_tt, charms - 600.0, 5).contains(tr("TERM_AUTUMN")), "the panel marks exams and the board names the term")
	cal_tt.apply({"tz": 60, "slots": [], "cal": {"brk": "BREAK_WINTER", "exam": false}})
	t.check(cal_tt.calendar_line() == tr("CALENDAR_HOLIDAY") % tr("BREAK_WINTER"), "a break says there are no lessons")
	cal_tt.apply({"tz": 60, "slots": [], "cal": {"next_term": "TERM_SPRING", "next_day": 20825, "exam": false}})
	t.check(cal_tt.calendar_line().contains(tr("TERM_SPRING")) and cal_tt.calendar_line().contains("7.01.2027"), "between terms it names the next (%s)" % cal_tt.calendar_line())
	var cal_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/calendar.json"))
	var cal_ok := cal_data is Dictionary and (cal_data.get("terms", []) as Array).size() > 0
	if cal_ok:
		for list_name: String in ["terms", "breaks", "exam_weeks"]:
			for r: Dictionary in cal_data.get(list_name, []):
				var d0 := str(r.get("start", ""))
				var d1 := str(r.get("end", ""))
				var key := str(r.get("name_key", ""))
				if d0.length() != 10 or d1.length() != 10 or d1 < d0 or (list_name != "exam_weeks" and tr(key) == key):
					cal_ok = false
	t.check(cal_ok, "calendar.json: dates in order, every term and break named by a translated key")

	# The shipped timetable names real subjects and rooms.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/timetable.json"))
	var ok := data is Dictionary and (data.get("slots", []) as Array).size() > 0
	var problems: Array[String] = []
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	var zones := {}
	for z in (castle as Node).get_tree().get_nodes_in_group(AreaZone.GROUP):
		zones[str((z as AreaZone).area_id)] = z
	if ok:
		for slot: Dictionary in data.slots:
			var kind := str(slot.get("kind", "lesson"))
			var subject := SubjectRegistry.load_definition(str(slot.get("subject", "")))
			var room := str(slot.get("room", subject.classrooms[0] if subject != null else ""))
			if kind == "lesson" and subject == null:
				problems.append("%s: subject" % slot.id)
			if not zones.has(room):
				problems.append("%s: room %s" % [slot.id, room])
			if not ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].has(str(slot.get("day", ""))) or SchoolClock.parse(str(slot.get("start", ""))) < 0.0:
				problems.append("%s: day/start" % slot.id)
	t.check(ok and problems.is_empty(), "timetable.json slots name real subjects, rooms and times %s" % str(problems))

	# Notice boards hang in the entrance hall and every common room.
	var boards := castle.find_children("*", "NoticeBoard", true, false)
	var board_areas := {}
	for b: Node in boards:
		for id: String in zones:
			var z := zones[id] as AreaZone
			var local := z.to_local((b as Node3D).global_position)
			if absf(local.x) <= z.size.x / 2 and absf(local.y) <= z.size.y / 2 and absf(local.z) <= z.size.z / 2 and z.kind != "grounds":
				board_areas[z.kind if z.kind == "common_room" else id] = int(board_areas.get(z.kind if z.kind == "common_room" else id, 0)) + 1
	t.check(boards.size() == 5 and board_areas.get("entrance_hall", 0) == 1 and board_areas.get("common_room", 0) == 4, "a notice board in the entrance hall and each common room (%s)" % str(board_areas))

	# Bells ring from the shared timetable.
	var saved := NetworkManager.timetable
	NetworkManager.timetable = tt
	var bells := castle.get_node_or_null("SchoolBells") as SchoolBells
	t.check(bells != null and SchoolBells.bell_stream().data.size() > 10000, "the castle has a bell")
	if bells != null:
		bells.set_process(false)
		bells.check(charms - 301.0)
		bells.check(charms - 299.0)
		bells.check(charms + 1.0)
		t.check(bells.rung.size() == 2 and bells.rung[0].event == "warn" and bells.rung[1].event == "start", "bells ring the warning and the start once each")
	NetworkManager.timetable = saved
	castle.queue_free()
	await get_tree().process_frame


## A dry point of an outdoor area with nothing built on it, or INF.
func _open_ground(terrain: Terrain, z: AreaZone) -> Vector3:
	var half := Vector2(minf(z.size.x / 2.0 - 5.0, 60.0), minf(z.size.z / 2.0 - 5.0, 60.0))
	var c := z.global_position
	for offset in [Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var x := clampf(c.x + offset.x * half.x, -900.0, 900.0)
		var zz := clampf(c.z + offset.y * half.y, -900.0, 900.0)
		var ground := terrain.height_at(x, zz)
		if ground < terrain.water_level + 0.5 or not terrain.has_ground(x, zz):
			continue
		terrain.focus_on(Vector3(x, ground, zz), true)
		await get_tree().physics_frame
		var hit: Dictionary = terrain.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(Vector3(x, ground + 40.0, zz), Vector3(x, ground - 5.0, zz)))
		if not hit.is_empty() and absf((hit["position"] as Vector3).y - ground) < 0.3:
			return Vector3(x, ground, zz)
	return Vector3.INF


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


# --- Localization --------------------------------------------------------------

## Every key in localization/translations.csv must resolve in both locales, and
## locale resolution / display-name sanitizing must behave as documented.
func _test_localization() -> void:
	t.section("Localization")
	var previous := TranslationServer.get_locale()
	var loaded := TranslationServer.get_loaded_locales()
	t.check(loaded.has("pl") and loaded.has("en"), "pl and en translations loaded (%s)" % str(loaded))

	var file := FileAccess.open("res://localization/translations.csv", FileAccess.READ)
	t.check(file != null, "translations.csv readable")
	var header := file.get_csv_line()
	t.check(header.size() >= 3 and header[0] == "keys" and header[1] == "en" and header[2] == "pl", "csv header is keys,en,pl")
	var keys: PackedStringArray = []
	var missing: PackedStringArray = []
	var ragged: PackedStringArray = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 3:
			ragged.append(row[0])   # an unquoted comma split a cell
		if row.size() < 3 or row[0].is_empty():
			continue
		keys.append(row[0])
		if row[1].strip_edges().is_empty() or row[2].strip_edges().is_empty():
			missing.append(row[0])
	file.close()
	t.check(keys.size() > 60, "csv has the expected number of keys (%d)" % keys.size())
	t.check(missing.is_empty(), "no empty en/pl cell (%s)" % str(missing))
	t.check(ragged.is_empty(), "every row has exactly three cells: commas inside text are quoted (%s)" % str(ragged))
	var duplicates: PackedStringArray = []
	var seen: Dictionary = {}
	for key in keys:
		if seen.has(key):
			duplicates.append(key)
		seen[key] = true
	t.check(duplicates.is_empty(), "no duplicate keys (%s)" % str(duplicates))

	for locale in Localization.SUPPORTED:
		TranslationServer.set_locale(locale)
		var untranslated: PackedStringArray = []
		for key in keys:
			if tr(key) == key:
				untranslated.append(key)
		t.check(untranslated.is_empty(), "[%s] every key translates (stale import? %s)" % [locale, str(untranslated)])

	TranslationServer.set_locale("en")
	t.check(tr("MENU_PLAY_OFFLINE") == "Play OFFLINE", "en: MENU_PLAY_OFFLINE")
	t.check((tr("HUD_FRAGMENTS") % [3, 11]) == "Fragments: 3 / 11", "en: formatted HUD_FRAGMENTS")
	TranslationServer.set_locale("pl")
	t.check(tr("MENU_PLAY_OFFLINE") == "Graj OFFLINE", "pl: MENU_PLAY_OFFLINE")
	t.check(tr("PLAYER_DEFAULT_NAME") == "Uczeń", "pl: default player name has diacritics intact")
	t.check(GameSession.sanitize_display_name("") == "Uczeń", "pl: empty display name falls back to localized default")
	# Fallback locale is Polish: an unsupported locale gets Polish text.
	TranslationServer.set_locale("de")
	t.check(tr("MENU_PLAY_OFFLINE") == "Graj OFFLINE", "unsupported locale falls back to Polish")

	t.check(Localization.resolve("pl") == "pl" and Localization.resolve("en") == "en", "explicit setting wins")
	t.check(Localization.SUPPORTED.has(Localization.resolve(Localization.AUTO)), "auto resolves to a supported locale")
	t.check(Localization.SUPPORTED.has(Localization.resolve("garbage")), "unknown setting behaves like auto")

	t.check(GameSession.sanitize_display_name("Michał Żółć") == "Michał Żółć", "display names keep Polish letters")
	t.check(GameSession.sanitize_display_name(" [Ro]wan_1 ") == "Rowan_1", "display names drop brackets and outer spaces")
	TranslationServer.set_locale(previous)


# --- Characters -----------------------------------------------------------------------

func _test_characters() -> void:
	t.section("Characters")
	var floor_body := TestHelpers.make_floor(self, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	for id in CharacterRegistry.ids():
		if player != null:
			player.queue_free()
			await get_tree().process_frame
		player = PLAYER_SCENE.instantiate()
		player.is_local = true
		player.character_id = id
		add_child(player)
		player.global_position = Vector3(0, 0.1, 0)
		await _wait(0.3)
		t.check(player.visual.scene_file_path == CharacterRegistry.load_scene(id).resource_path, "%s: visual scene swapped in" % id)
		t.check(player.cast_origin != null and player.cast_origin.is_inside_tree(), "%s: cast origin found" % id)
		var socket := player.visual.find_child("OffHand", true, false)
		t.check(socket != null, "%s: OffHand socket present in the body" % id)
		player.inventory.load_state(ItemRegistry.default_state())
		player.inventory.hold_id(&"torch")
		t.check(_find_light(player) != null and _find_light(player).is_inside_tree(), "%s: held torch lights up in the off hand" % id)
		await _wait(0.2)
		var torch := player.held_item_mount.current_node
		var up_dot := torch.global_transform.basis.y.dot(Vector3.UP)
		t.check(up_dot > 0.8 and up_dot < 0.99, "%s: held torch is roughly upright with a lean, regardless of the hand pose" % id)
		t.check(torch.global_position.distance_to(player.off_hand.global_position) < 0.25, "%s: held torch stays in the hand" % id)
		var shaft_forward := torch.global_transform.basis.y.dot(-player.global_transform.basis.z)
		t.check(shaft_forward > 0.3, "%s: held torch leans forward in the character's facing" % id)
		player.inventory.release_held()
		var tree: AnimationTree = player.visual.get_node("AnimationTree")
		t.check(tree.active, "%s: animation tree active" % id)
		var ap: AnimationPlayer = tree.get_node(tree.anim_player)
		var missing := []
		for state in PlayerMovement.STATE_NAMES:
			var node_name: String = str(player.animation_controller.movement_state_map.get(state, "")).capitalize()
			var anim_node := (tree.tree_root as AnimationNodeBlendTree).get_node(node_name) as AnimationNodeAnimation
			if anim_node == null or not ap.has_animation(anim_node.animation):
				missing.append(state)
		t.check(missing.is_empty(), "%s: all movement states map to existing clips %s" % [id, str(missing)])
		var not_looping := []
		for state in player.animation_controller.looping_states:
			var anim_node := (tree.tree_root as AnimationNodeBlendTree).get_node(state.capitalize()) as AnimationNodeAnimation
			if anim_node != null and ap.has_animation(anim_node.animation) and ap.get_animation(anim_node.animation).loop_mode == Animation.LOOP_NONE:
				not_looping.append(state)
		t.check(not_looping.is_empty(), "%s: idle/walk/run/fall clips loop %s" % [id, str(not_looping)])
		player.movement.set_external_move(Vector3(0, 0, -1), false)
		await _wait(0.4)
		t.check(player.animation_controller.current_state_name == "walk", "%s: controller reaches walk state" % id)
		player.animation_controller.play_cast()
		await _wait(0.2)
		t.check(bool(tree.get("parameters/Cast/active")), "%s: cast one-shot plays" % id)
		player.movement.set_external_move(Vector3.ZERO)
	await _clear([floor_body])


## The server's generated content modules must match a fresh export, and the
## explicit registries must list exactly the definitions on disk.
func _test_server_content() -> void:
	t.section("Server content")
	var stale := ServerContentExporter.stale()
	t.check(stale.is_empty(), "nakama/modules/generated is up to date (stale: %s; run tools/export_server_content.tscn)" % ", ".join(stale))
	t.check(_ids_match_dir(SpellRegistry.SPELL_IDS, SpellRegistry.SPELLS_DIR), "SPELL_IDS lists exactly resources/spells/*.tres")
	t.check(_ids_match_dir(ItemRegistry.ITEM_IDS, ItemRegistry.ITEMS_DIR), "ITEM_IDS lists exactly resources/items/*.tres")
	for id in ItemRegistry.ITEM_IDS:
		var def := ItemRegistry.load_definition(id)
		t.check(def != null and str(def.id) == id, "item %s loads with a matching id" % id)
	var codes := {}
	var duplicate := false
	var constants: Dictionary = (NetworkProtocol as Script).get_script_constant_map()
	for name: String in constants:
		if name.begins_with("OP_"):
			duplicate = duplicate or codes.has(constants[name])
			codes[constants[name]] = name
	t.check(not duplicate and not codes.is_empty(), "protocol op codes are unique")
	t.check(HouseSorting.question_count() == 4, "sorting questionnaire loads from its resource")
	# Subjects: explicit list matches the files; every spell belongs to exactly one
	# subject; a classroom hosts at most one subject; names are translated.
	var subject_files: Array[String] = []
	for file_name in DirAccess.get_files_at(SubjectRegistry.SUBJECTS_DIR):
		if file_name.trim_suffix(".remap").ends_with(".tres"):
			subject_files.append(file_name.trim_suffix(".remap").trim_suffix(".tres"))
	var listed := SubjectRegistry.SUBJECT_IDS.duplicate()
	listed.sort()
	subject_files.sort()
	t.check(listed == subject_files, "SUBJECT_IDS lists exactly resources/school/subjects/*.tres")
	var owners := {}
	var rooms := {}
	var problems: Array[String] = []
	for def in SubjectRegistry.all():
		if str(def.id) + ".tres" != def.resource_path.get_file():
			problems.append("%s: id does not match its file" % def.id)
		if tr(def.display_name) == def.display_name:
			problems.append("%s: untranslated name" % def.id)
		for spell in def.spells():
			if not SpellRegistry.exists(spell) or owners.has(spell):
				problems.append("%s: spell %s unknown or taught twice" % [def.id, spell])
			owners[spell] = def.id
		for room in def.classrooms:
			if rooms.has(room):
				problems.append("%s: classroom %s already hosts %s" % [def.id, room, rooms[room]])
			rooms[room] = def.id
	for spell in SpellRegistry.SPELL_IDS:
		if not owners.has(spell):
			problems.append("spell %s belongs to no subject" % spell)
	var classroom_areas := {}
	var lua := FileAccess.get_file_as_string("res://nakama/modules/world_areas.lua")
	for m in RegEx.create_from_string('\\["([a-z0-9_]+)"\\] = \\{ kind = "classroom"').search_all(lua):
		classroom_areas[m.get_string(1)] = true
	for room: String in rooms:
		if not classroom_areas.has(room):
			problems.append("%s is not a classroom area" % room)
	t.check(problems.is_empty(), "subjects: each spell in one subject, classrooms are real and unshared (%s)" % "; ".join(problems))
	t.check(SubjectRegistry.for_area("greenhouse") == SubjectRegistry.load_definition("herblore") and SubjectRegistry.for_spell("uplift").id == &"sigilcraft", "subjects resolve by classroom and by spell")


func _ids_match_dir(ids: Array[String], dir_path: String) -> bool:
	var on_disk: Array[String] = []
	for file_name in DirAccess.get_files_at(dir_path):
		var clean := file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			on_disk.append(clean.trim_suffix(".tres"))
	var listed := ids.duplicate()
	listed.sort()
	on_disk.sort()
	return listed == on_disk


## Server state applied to each synced kind, and offline triggers still acting locally.
func _test_world_objects() -> void:
	t.section("World objects")
	var wall: SecretWall = SECRET_WALL_SCENE.instantiate()
	wall.object_id = "test/secret_wall"
	add_child(wall)
	await get_tree().process_frame
	t.check(not WorldObjectSync.request(wall, "spell", null), "offline, requests are refused so objects act locally")
	var wall_y: float = wall.get_node("Wall").position.y
	wall.apply_world_state("revealed", true)
	t.check(wall.is_revealed and is_equal_approx(wall.get_node("Wall").position.y, wall_y + wall.slide_offset.y), "secret wall: snapshot state reveals it instantly")
	wall.apply_world_state(null, true)
	t.check(not wall.is_revealed and is_equal_approx(wall.get_node("Wall").position.y, wall_y), "secret wall: default state closes it again")
	var switch: MagicSwitch = SWITCH_SCENE.instantiate()
	add_child(switch)
	await get_tree().process_frame
	switch.apply_world_state(true, false)
	t.check(switch.is_on, "switch: server state turns it on")
	switch.apply_world_state(null, true)
	t.check(not switch.is_on, "switch: default state turns it off")
	var torch: WallTorch = WALL_TORCH_SCENE.instantiate()
	add_child(torch)
	await get_tree().process_frame
	torch.apply_world_state(false, false)
	t.check(not torch.lit, "torch: server state puts it out")
	torch.apply_world_state(null, true)
	t.check(torch.lit, "torch: default state relights it")
	var lever: Lever = LEVER_SCENE.instantiate()
	add_child(lever)
	await get_tree().process_frame
	var pulled := [0]
	lever.pulled.connect(func() -> void: pulled[0] += 1)
	lever.apply_world_state(true, true)
	t.check(lever.is_on and pulled[0] == 1, "lever: server state pulls it (and emits pulled)")
	lever.apply_world_state(false, false)
	t.check(not lever.is_on, "lever: server state puts it back")
	var statue: RotatingStatue = STATUE_SCENE.instantiate()
	add_child(statue)
	await get_tree().process_frame
	statue.apply_world_state(3, true)
	t.check(statue.state == 3 and is_equal_approx(wrapf(statue.get_node("Pivot").rotation.y, 0.0, TAU), statue._angle_for(3)), "statue: server state turns it to state 3")
	statue.advance()
	t.check(statue.state == 0, "statue: advancing wraps to 0")
	statue.apply_world_state(null, true)
	t.check(statue.state == statue.initial_state, "statue: default state is its initial state")
	var door: MagicDoor = DOOR_SCENE.instantiate()
	add_child(door)
	await get_tree().process_frame
	door.apply_world_state(true, true)
	t.check(door.is_open, "door: server state opens it instantly")
	door.apply_world_state(null, true)
	t.check(not door.is_open, "door: default state closes it")
	var castle_door: CastleDoor = CASTLE_DOOR_SCENE.instantiate()
	castle_door.position = Vector3(60, 0, 60)   # clear of the objects above, for the collision checks
	add_child(castle_door)
	await get_tree().process_frame
	var leaf: Interactable = castle_door.get_node("HingeL/Interactable")
	leaf.interact(self)
	t.check(castle_door.is_open, "castle door: interacting offline opens it")
	leaf.interact(self)
	t.check(not castle_door.is_open, "castle door: interacting again closes it")
	castle_door.set_open(true, true)
	t.check(is_equal_approx(castle_door.get_node("HingeL").rotation.y, -deg_to_rad(castle_door.open_angle_degrees))
			and is_equal_approx(castle_door.get_node("HingeR").rotation.y, deg_to_rad(castle_door.open_angle_degrees)),
			"castle door: both leaves swing toward +Z")
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(not _capsule_blocked(castle_door.global_position + Vector3(0, 1.0, 0)), "castle door: an open doorway lets a player-sized capsule through")
	castle_door.set_open(false, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(_capsule_blocked(castle_door.global_position + Vector3(0, 1.0, 0)), "castle door: a closed door blocks the doorway")
	var locked_door: CastleDoor = CASTLE_DOOR_SCENE.instantiate()
	locked_door.locked = true
	add_child(locked_door)
	await get_tree().process_frame
	locked_door.get_node("HingeR/Interactable").interact(self)
	t.check(locked_door.is_locked and not locked_door.is_open, "castle door: a locked door refuses the handle")
	var receiver: SpellReceiver = locked_door.get_node("HingeR/SpellReceiver")
	t.check(not receiver.receive(SpellEffect.create(ARCANE_PULSE, self, "", Vector3.ZERO, Vector3.FORWARD)), "castle door: ignores spells other than unlock")
	receiver.receive(SpellEffect.create(UNBOLT, self, "", Vector3.ZERO, Vector3.FORWARD))
	t.check(not locked_door.is_locked and not locked_door.is_open, "castle door: Unbolt unlocks it, still closed")
	locked_door.get_node("HingeR/Interactable").interact(self)
	t.check(locked_door.is_open, "castle door: unlocked, it opens")
	locked_door.apply_world_state(null, true)
	t.check(locked_door.is_locked and not locked_door.is_open, "castle door: default state of a locked door is locked and shut")
	locked_door.apply_world_state(false, true)
	t.check(not locked_door.is_locked and not locked_door.is_open, "castle door: server state false = unlocked, closed")
	locked_door.apply_world_state(true, true)
	t.check(locked_door.is_open, "castle door: server state true opens it")
	var grand: CastleDoor = GRAND_DOOR_SCENE.instantiate()
	grand.start_open = true
	grand.position = Vector3(-60, 0, 60)
	add_child(grand)
	await get_tree().process_frame
	t.check(grand.is_open, "ceremonial door: a main-route door starts open")
	grand.apply_world_state(false, true)
	t.check(not grand.is_open, "ceremonial door: server state false closes it")
	grand.apply_world_state(null, true)
	t.check(grand.is_open, "ceremonial door: default state is open again")
	var leaf_mesh := (grand.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	t.check(leaf_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_NORMAL, "ceremonial door: leaf mesh has normals (generated when the export lacks them)")
	for n: Node in [wall, switch, torch, lever, statue, door, castle_door, locked_door, grand]:
		n.queue_free()
	await get_tree().process_frame


## True when a player-sized capsule at `centre` overlaps world geometry.
func _capsule_blocked(centre: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	q.shape = capsule
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), centre)
	return not get_viewport().world_3d.direct_space_state.intersect_shape(q).is_empty()


## Server-only mystery content (nakama/content/) refers only to things that
## exist, has both languages, and none of its text is in the shipped CSV.
func _test_mysteries() -> void:
	t.section("Mysteries (server content)")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/mysteries.json"))
	var strings: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/strings.json"))
	# Generated secrets (tools/castle/secrets.py) are merged like the server does.
	var gen_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/generated_mysteries.json"))
	var gen_strings: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://nakama/content/generated_strings.json"))
	if data is Dictionary and gen_data is Dictionary:
		data["mysteries"] = (data["mysteries"] as Array) + (gen_data["mysteries"] as Array)
	if strings is Dictionary and gen_strings is Dictionary:
		strings.merge(gen_strings)
	if not t.check(data is Dictionary and strings is Dictionary, "mysteries.json and strings.json parse"):
		return
	var objects := ServerContentExporter.world_objects(ServerContentExporter.CASTLE_SCENE)
	var areas := {}
	var area_re := RegEx.create_from_string('\\["([a-z0-9_]+)"\\] = \\{')
	for m in area_re.search_all(FileAccess.get_file_as_string("res://nakama/modules/world_areas.lua")):
		areas[m.get_string(1)] = true
	var effects := {}
	for def in SpellRegistry.all():
		effects[str(def.effect_type)] = true
	var problems: Array[String] = []
	var keys: Array[String] = []
	var ids := {}
	for m: Dictionary in data.get("mysteries", []):
		var mid := str(m.get("id", ""))
		if mid.is_empty() or ids.has(mid):
			problems.append("bad or duplicate id %s" % mid)
		ids[mid] = true
		for step: Dictionary in m.get("steps", []):
			var ev := str(step.get("event", ""))
			if ev in ["spell", "interact"]:
				var obj: Dictionary = objects.get(str(step.get("object", "")), {})
				if obj.is_empty():
					problems.append("%s: unknown object %s" % [mid, step.get("object")])
				elif ev == "spell" and step.has("effect_type") and not (effects.has(step["effect_type"]) and (obj["accepts"].has(step["effect_type"]) or obj["accepts"].has("any"))):
					problems.append("%s: %s does not take %s" % [mid, step["object"], step["effect_type"]])
			elif ev in ["enter", "together"]:
				if not areas.has(str(step.get("area", ""))):
					problems.append("%s: unknown area %s" % [mid, step.get("area")])
				if step.has("holding") and not ItemRegistry.exists(str(step["holding"])):
					problems.append("%s: unknown item %s" % [mid, step["holding"]])
			else:
				problems.append("%s: unknown event %s" % [mid, ev])
			if step.has("text"):
				keys.append(str(step["text"]))
		var solved: Dictionary = m.get("on_solved", {})
		for oid: String in solved.get("set_state", {}):
			if not objects.has(oid):
				problems.append("%s: on_solved sets unknown object %s" % [mid, oid])
		if solved.has("text"):
			keys.append(str(solved["text"]))
	t.check(problems.is_empty() and ids.size() >= 4, "%d mysteries refer only to existing objects, areas, effects and items (%s)" % [ids.size(), "; ".join(problems)])
	var missing: Array[String] = []
	for key in keys:
		var entry: Variant = strings.get(key)
		if not (entry is Dictionary and str(entry.get("pl", "")) != "" and str(entry.get("en", "")) != ""):
			missing.append(key)
	t.check(missing.is_empty(), "every mystery text has pl and en (missing: %s)" % ", ".join(missing))
	var csv := FileAccess.get_file_as_string("res://localization/translations.csv")
	var csv_keys := {}
	for line in csv.split("\n"):
		csv_keys[line.get_slice(",", 0)] = true
	var leaked: Array[String] = []
	for key: String in strings:
		if csv_keys.has(key):
			leaked.append(key)
		for loc in ["pl", "en"]:
			var text := str(strings[key].get(loc, ""))
			if text.length() > 12 and csv.contains(text):
				leaked.append("%s.%s" % [key, loc])
	t.check(leaked.is_empty(), "no server-only text is in the shipped translations.csv (%s)" % ", ".join(leaked))
