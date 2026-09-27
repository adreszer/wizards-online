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
const INVENTORY_PANEL_SCENE := preload("res://ui/inventory/inventory_panel.tscn")
const BLOCK_SCENE := preload("res://objects/puzzles/pushable_block.tscn")
const WALL_TORCH_SCENE := preload("res://objects/environment/props/wall_torch.tscn")
const HUD_SCENE := preload("res://ui/hud/hud.tscn")
const PROFESSOR_PANEL_SCENE := preload("res://ui/school/professor_panel.tscn")
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
	await _test_spellbook()
	await _test_spell_effects()
	await _test_school()
	await _test_inventory()
	await _test_interaction()
	await _test_moving_platform()
	await _test_level_wiring()
	await _test_castle()
	_test_localization()
	await _test_characters()
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
	t.check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "cursor is free by default")
	rig.start_orbit()
	# The headless display server has no cursor capture, so only assert the mode on a real one.
	var headless := DisplayServer.get_name() == "headless"
	t.check(rig.is_orbiting and (headless or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "right button drag captures the cursor")
	var yaw_before := rig.get_yaw()
	rig._unhandled_input(_mouse_motion(Vector2(50, 0)))
	t.check(absf(rig.get_yaw() - yaw_before) > 0.05, "dragging with the right button orbits the camera")
	rig.stop_orbit()
	t.check(not rig.is_orbiting and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "releasing the right button frees the cursor")
	yaw_before = rig.get_yaw()
	rig._unhandled_input(_mouse_motion(Vector2(50, 0)))
	t.check(is_equal_approx(rig.get_yaw(), yaw_before), "mouse motion without the right button leaves the camera alone")
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
	t.check(remote.role == "professor" and remote.house == 2 and remote.nameplate.text == tr("ROLE_PROFESSOR_TITLE") + " Remote", "professors get a title on the nameplate")
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
	t.check(get_tree().get_nodes_in_group("secret_walls").size() >= 3, "castle has secret passages")
	t.check(GameSession.get_total(&"arcane_fragment") >= 10, "castle registers its fragments (got %d)" % GameSession.get_total(&"arcane_fragment"))
	var tome_spells: Dictionary = {}
	for tome in castle.get_node("Tomes").get_children():
		if tome is SpellTome and tome.spell != null:
			tome_spells[tome.spell.id] = true
	t.check(tome_spells.size() == SpellRegistry.SPELL_IDS.size(), "a practice tome for every spell is placed in the castle (%d)" % tome_spells.size())
	# Every area has a floor under its centre (rooms with stair holes keep their centre solid).
	var fell: Array[String] = []
	for z in zones:
		var base_y := z.global_position.y - z.size.y / 2.0
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
	# Tower flight: from the foot of the southwest tower's stair to its first floor.
	await _spawn_player(Vector3(-38.025, 1.2, 38.5))
	player.movement.set_external_move(Vector3(0, 0, -1), false)
	await _wait(8.0)
	player.movement.set_external_move(Vector3.ZERO)
	t.check(player.global_position.y > 8.5, "stairs: tower flight reaches the first floor (y %.2f, z %.2f)" % [player.global_position.y, player.global_position.z])
	castle.queue_free()
	await get_tree().process_frame


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
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 3 or row[0].is_empty():
			continue
		keys.append(row[0])
		if row[1].strip_edges().is_empty() or row[2].strip_edges().is_empty():
			missing.append(row[0])
	file.close()
	t.check(keys.size() > 60, "csv has the expected number of keys (%d)" % keys.size())
	t.check(missing.is_empty(), "no empty en/pl cell (%s)" % str(missing))
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
			var node_name: String = state.capitalize()
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
