extends Node
## Headless stair-walking measurements. Run:
##   godot --headless --path . tests/run_stairs_test.tscn
## (`-- --castle` also walks the castle's own flights and turret spirals.)
## Walks a player up and down straight flights between walls (centred, hugging a
## wall, angled into it, running), a spiral, and low ledges, and checks what the
## owner feels when playing: the body keeps a steady speed (no surges, no
## stalls), stays grounded, never gets stuck, and the mesh moves smoothly.
## Exit code 1 on any failure.

const PLAYER_SCENE := preload("res://characters/player/player.tscn")
const CASTLE_SCENE := preload("res://levels/castle/castle.tscn")
const TestHelpers := preload("res://tests/test_helpers.gd")

var t := TestHelpers.new()
var player: Player
var verbose := false
## `-- --trace=<text>` prints every tick of the cases whose label contains the text.
var trace := ""
var _label := ""


func _ready() -> void:
	var castle := false
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--castle":
			castle = true
		elif arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
		elif arg == "--verbose":
			verbose = true
		elif arg.begins_with("--trace="):
			trace = arg.get_slice("=", 1)
	if only == "" or only == "straight":
		await _test_straight_flights()
	if only == "" or only == "spiral":
		await _test_spiral()
	if only == "" or only == "ledges":
		await _test_ledges()
	if castle or only == "castle":
		await _test_castle_stairs()
	print(t.summary())
	get_tree().quit(1 if t.failed > 0 else 0)


func _tick() -> void:
	await get_tree().physics_frame


func _spawn(at: Vector3) -> void:
	if player != null:
		player.queue_free()
		await get_tree().process_frame
	player = PLAYER_SCENE.instantiate()
	player.is_local = true
	player.display_name = "Tester"
	add_child(player)
	player.global_position = at
	player.respawn_handler.set_checkpoint(player.global_transform)
	for i in range(20):
		await _tick()


## Where the mesh is drawn at the end of a tick (body plus the step easing offset).
func _presented() -> Vector3:
	return player.global_position + player._visual_offset + player.movement.step_lag()


## Drives the player with `dir_fn` (called each tick with the player, returns a world
## direction) until `done_fn` is true or `max_seconds` pass, and measures the walk.
func _walk(dir_fn: Callable, done_fn: Callable, sprint: bool, max_seconds: float, mid_fn := Callable()) -> Dictionary:
	var target_speed := player.movement.run_speed if sprint else player.movement.walk_speed
	var body_speeds: Array[float] = []
	var mesh_speeds: Array[float] = []
	var mesh_dy: Array[float] = []
	## Vertical mesh speed on the ticks `mid_fn` calls mid-flight (the camera follows it).
	var mid_dy: Array[float] = []
	var airborne := 0
	var fall_states := 0
	var reached := false
	var prev_body := player.global_position
	var prev_mesh := _presented()
	var ticks := 0
	var path := 0.0
	player.movement.debug_step = trace != "" and _label.find(trace) >= 0
	for i in range(int(max_seconds * 60.0)):
		player.movement.set_external_move(dir_fn.call(player), sprint)
		await _tick()
		ticks += 1
		var body := player.global_position
		var mesh := _presented()
		var flat := Vector2(body.x - prev_body.x, body.z - prev_body.z).length()
		path += flat
		if i >= 12:
			body_speeds.append(flat * 60.0)
			mesh_speeds.append(Vector2(mesh.x - prev_mesh.x, mesh.z - prev_mesh.z).length() * 60.0)
			mesh_dy.append(absf(mesh.y - prev_mesh.y))
			# (A trick step holding the player still is no pause in the pace.)
			if mid_fn.is_valid() and mid_fn.call(player) and not player.movement.is_held() and player.movement.get_horizontal_speed() > 0.5:
				mid_dy.append(absf(mesh.y - prev_mesh.y) * 60.0)
			if not player.movement.is_grounded:
				airborne += 1
			if player.movement.state in [PlayerMovement.State.FALL, PlayerMovement.State.LAND, PlayerMovement.State.JUMP]:
				fall_states += 1
		if trace != "" and _label.find(trace) >= 0:
			if player.movement.state == PlayerMovement.State.IDLE:
				var params := PhysicsTestMotionParameters3D.new()
				params.from = player.global_transform
				params.motion = Vector3.UP * 0.42
				var res := PhysicsTestMotionResult3D.new()
				if PhysicsServer3D.body_test_motion(player.get_rid(), params, res):
					var col := res.get_collider() as Node
					print("    above: %s %s at %s n=%s" % [col.get_path(), col.get_class(), res.get_collision_point() - body, res.get_collision_normal()])
			for k in player.get_slide_collision_count():
				var c := player.get_slide_collision(k)
				print("    hit %s n=%s at %s" % [c.get_collider().get_parent().name + "/" + c.get_collider().name if c.get_collider() else "?", c.get_normal(), c.get_position()])
			print("%s t%d pos %s mesh_dy %.3f off %.3f grounded %s state %s vel %s held %.2f" % [_label, i, str(body), mesh.y - prev_mesh.y, player._visual_offset.y, player.movement.is_grounded, player.movement.get_state_name(), str(player.velocity), player.movement._held])
		prev_body = body
		prev_mesh = mesh
		if done_fn.call(player):
			reached = true
			break
	player.movement.set_external_move(Vector3.ZERO)
	return {
		"reached": reached, "ticks": ticks, "path": path, "target": target_speed,
		"body": _stats(body_speeds, target_speed), "mesh": _stats(mesh_speeds, target_speed),
		"max_mesh_dy": mesh_dy.max() if not mesh_dy.is_empty() else 0.0,
		"airborne": airborne, "fall_states": fall_states, "mid_dy": mid_dy,
	}


func _stats(speeds: Array[float], target: float) -> Dictionary:
	if speeds.is_empty():
		return {"mean": 0.0, "min": 0.0, "max": 0.0, "off": 0}
	var total := 0.0
	var off := 0
	for s in speeds:
		total += s
		if absf(s - target) > target * 0.2:
			off += 1
	return {"mean": total / speeds.size(), "min": speeds.min(), "max": speeds.max(), "off": off, "n": speeds.size()}


## The usual checks for one walk; `label` names the case in the log.
func _check_walk(label: String, r: Dictionary, expect_steady := true) -> void:
	var b: Dictionary = r.body
	var m: Dictionary = r.mesh
	var target: float = r.target
	if verbose:
		print("%s: %s" % [label, str(r)])
	t.check(r.reached, "%s: gets there (%d ticks)" % [label, r.ticks])
	t.check(r.airborne == 0 and r.fall_states == 0, "%s: stays grounded (%d airborne ticks, %d fall/jump states)" % [label, r.airborne, r.fall_states])
	if expect_steady:
		# Horizontal speed: never surging past the walk/run speed, never stalling. A step may
		# carry the body 3 cm further in one tick (paid back after, and the mesh never shows it).
		t.check(b.max < target * 1.15 + 0.035 * 60.0, "%s: body never surges (max %.2f m/s, speed %.2f)" % [label, b.max, target])
		t.check(m.max < target * 1.25, "%s: mesh never surges (max %.2f m/s)" % [label, m.max])
		t.check(m.min > target * 0.6, "%s: mesh never stalls (min %.2f m/s)" % [label, m.min])
		t.check(m.off <= maxi(2, int(m.n * 0.05)), "%s: mesh speed steady (%d of %d ticks off by >20%%)" % [label, m.off, m.n])
		t.check(absf(m.mean - target) < target * 0.12, "%s: average pace is the walking pace (%.2f m/s)" % [label, m.mean])
	# The mesh climbs a step at up to step_climb_ratio x the walking speed.
	var max_dy := maxf(0.12, target * player.step_climb_ratio / 60.0 + 0.01)
	t.check(r.max_mesh_dy < max_dy, "%s: mesh rises/falls smoothly (max %.3f m per tick)" % [label, r.max_mesh_dy])
	var mid: Array[float] = r.mid_dy
	if mid.size() > 20:
		# Mid-flight the mesh (and the camera) should rise or sink at an even rate, not
		# drop a step, pause, drop a step.
		var mean := 0.0
		for v in mid:
			mean += v
		mean /= mid.size()
		var uneven := mid.filter(func(v: float) -> bool: return absf(v - mean) > mean * 0.35).size()
		t.check(uneven <= int(mid.size() * 0.1), "%s: even vertical pace mid-flight (%d of %d ticks off the %.2f m/s mean by >35%%, min %.2f max %.2f)" % [label, uneven, mid.size(), mean, mid.min(), mid.max()])


# --- Fixtures -------------------------------------------------------------------

func _wall(parent: Node, centre: Vector3, size: Vector3) -> void:
	TestHelpers.make_floor(parent, centre, size).reparent(parent)


## A straight flight climbing along -Z from z = 0 between two walls, with landings.
## Returns the fixture root.
func _build_flight(origin: Vector3, rise: float, run: float, width: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = origin
	_wall(root, origin + Vector3(0, -0.5, 6), Vector3(width + 2, 1, 12))          # bottom landing
	_wall(root, origin + Vector3(0, rise - 0.5, -run - 6), Vector3(width + 2, 1, 12))  # top landing
	var flight := Staircase.new()
	flight.rise = rise
	flight.run = run
	flight.width = width
	root.add_child(flight)
	# Climbs along local +X; turn it to climb along -Z.
	flight.rotation.y = PI / 2.0
	flight.global_position = origin
	for side in [-1.0, 1.0]:
		_wall(root, origin + Vector3(side * (width / 2.0 + 0.25), rise / 2.0, -run / 2.0), Vector3(0.5, rise + 6, run + 24))
	return root


# --- Straight flights -------------------------------------------------------------

func _test_straight_flights() -> void:
	t.section("Straight flights")
	var origin := Vector3(0, 0, 0)
	var rise := 3.6
	var run := 5.6
	var width := 3.0
	var root := _build_flight(origin, rise, run, width)
	await _tick()
	var half := width / 2.0
	var r_body := 0.36
	# lateral offsets: centre, hugging the left wall, hugging the right wall
	var cases := [
		["walk up, centre", 0.0, Vector3(0, 0, -1), false],
		["walk up, hugging the left wall", -half + r_body, Vector3(0, 0, -1), false],
		["walk up, hugging the right wall", half - r_body, Vector3(0, 0, -1), false],
		["walk up, angled into the wall", -half + r_body + 0.3, Vector3(-0.35, 0, -1).normalized(), false],
		["run up, centre", 0.0, Vector3(0, 0, -1), true],
		["run up, hugging the wall", -half + r_body, Vector3(0, 0, -1), true],
		["walk up, diagonal across", half - 0.5, Vector3(-0.3, 0, -1).normalized(), false],
	]
	for c: Array in cases:
		await _spawn(origin + Vector3(c[1], 0.05, 3.0))
		var dir: Vector3 = c[2]
		_label = c[0]
		var r := await _walk(func(_p: Player) -> Vector3: return dir,
			func(p: Player) -> bool: return p.global_position.z < -run - 1.0 and p.global_position.y > rise - 0.1, c[3], 8.0,
			func(p: Player) -> bool: return p.global_position.z < -1.0 and p.global_position.z > -run + 1.0)
		# Angled into a wall: the wall takes part of the speed, so only the smoothness rules apply.
		_check_walk(c[0], r, c[0].find("angled") < 0)
	var down_cases := [
		["walk down, centre", 0.0, Vector3(0, 0, 1), false],
		["walk down, hugging the left wall", -half + r_body, Vector3(0, 0, 1), false],
		["walk down, hugging the right wall", half - r_body, Vector3(0, 0, 1), false],
		["run down, centre", 0.0, Vector3(0, 0, 1), true],
		["walk down, diagonal across", -half + 0.5, Vector3(0.3, 0, 1).normalized(), false],
	]
	for c: Array in down_cases:
		await _spawn(origin + Vector3(c[1], rise + 0.05, -run - 2.0))
		var dir: Vector3 = c[2]
		_label = c[0]
		var r := await _walk(func(_p: Player) -> Vector3: return dir,
			func(p: Player) -> bool: return p.global_position.z > 1.5, c[3], 8.0,
			func(p: Player) -> bool: return p.global_position.z < -1.0 and p.global_position.z > -run + 1.0)
		_check_walk(c[0], r)
	# Stopping on the stairs: no sliding, and starting again works.
	await _spawn(origin + Vector3(0, 0.05, 3.0))
	await _walk(func(_p: Player) -> Vector3: return Vector3(0, 0, -1),
		func(p: Player) -> bool: return p.global_position.z < -run / 2.0, false, 6.0)
	var stop_at := player.global_position
	for i in range(60):
		await _tick()
	t.check(player.global_position.distance_to(stop_at) < 0.6 and player.movement.is_grounded, "stops on the stairs and stays put (moved %.2f m)" % player.global_position.distance_to(stop_at))
	stop_at = player.global_position
	for i in range(60):
		await _tick()
	t.check(player.global_position.distance_to(stop_at) < 0.01, "standing on a tread does not creep (%.3f m)" % player.global_position.distance_to(stop_at))
	# Turn round on the stairs and walk down.
	var r2 := await _walk(func(_p: Player) -> Vector3: return Vector3(0, 0, 1),
		func(p: Player) -> bool: return p.global_position.z > 1.5, false, 6.0)
	t.check(r2.reached and r2.fall_states == 0, "turns round mid-flight and walks down")
	# Strafing across the flight on a tread: the body stays on its tread.
	await _spawn(origin + Vector3(0, 0.05, 3.0))
	await _walk(func(_p: Player) -> Vector3: return Vector3(0, 0, -1),
		func(p: Player) -> bool: return p.global_position.z < -run / 2.0, false, 6.0)
	var y0 := player.global_position.y
	var r3 := await _walk(func(_p: Player) -> Vector3: return Vector3(-1, 0, 0),
		func(p: Player) -> bool: return p.global_position.x < -half + 0.5, false, 3.0)
	t.check(r3.reached and absf(player.global_position.y - y0) < 0.4 and r3.fall_states == 0,
		"walks sideways along a tread to the wall (dy %.2f)" % (player.global_position.y - y0))
	root.queue_free()
	await _tick()


# --- Spiral -----------------------------------------------------------------------

func _test_spiral() -> void:
	t.section("Spiral")
	var root := Node3D.new()
	add_child(root)
	var centre := Vector3(40, 0, 0)
	_wall(root, centre + Vector3(0, -0.5, 0), Vector3(12, 1, 12))
	var spiral := SpiralStaircase.new()
	spiral.turns = 1.0
	spiral.rise_per_turn = 9.0
	spiral.steps_per_turn = 30
	spiral.landing_steps = 5
	spiral.half_size = 3.8
	spiral.lanterns = false
	root.add_child(spiral)
	spiral.global_position = centre
	for s in [-1.0, 1.0]:
		_wall(root, centre + Vector3(s * 4.05, 6, 0), Vector3(0.5, 14, 9))
		_wall(root, centre + Vector3(0, 6, s * 4.05), Vector3(9, 14, 0.5))
	await _tick()
	var start_angle := deg_to_rad(spiral.start_angle_degrees) - 0.5
	for radius: float in [2.3, 1.4, 3.3]:
		await _spawn(centre + Vector3(cos(start_angle), 0, sin(start_angle)) * radius + Vector3(0, 0.05, 0))
		var keep: float = radius
		var r := await _walk(func(p: Player) -> Vector3:
				var rel := p.global_position - centre
				var radial := Vector3(rel.x, 0, rel.z)
				var tangent := Vector3(-rel.z, 0, rel.x).normalized()
				return (tangent + radial.normalized() * (keep - radial.length()) * 0.8).normalized(),
			func(p: Player) -> bool: return p.global_position.y > centre.y + 8.9, false, 16.0)
		_check_walk("spiral up at %.1f m from the column" % radius, r, false)
		var r_down := await _walk(func(p: Player) -> Vector3:
				var rel := p.global_position - centre
				var radial := Vector3(rel.x, 0, rel.z)
				var tangent := -Vector3(-rel.z, 0, rel.x).normalized()
				return (tangent + radial.normalized() * (keep - radial.length()) * 0.8).normalized(),
			func(p: Player) -> bool: return p.global_position.y < centre.y + 0.2, false, 16.0)
		_check_walk("spiral down at %.1f m from the column" % radius, r_down, false)
	root.queue_free()
	await _tick()


# --- Ledges ------------------------------------------------------------------------

func _test_ledges() -> void:
	t.section("Ledges and obstacles")
	var root := Node3D.new()
	add_child(root)
	var o := Vector3(-40, 0, 0)
	_wall(root, o + Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	var heights := [0.15, 0.3, 0.4, 0.55, 0.9]
	for i in range(heights.size()):
		var h: float = heights[i]
		_wall(root, o + Vector3(-8 + i * 4, h / 2.0, -4), Vector3(2.5, h, 2))
	await _tick()
	for i in range(heights.size()):
		var h: float = heights[i]
		await _spawn(o + Vector3(-8 + i * 4, 0.05, 0))
		var r := await _walk(func(_p: Player) -> Vector3: return Vector3(0, 0, -1),
			func(p: Player) -> bool: return p.global_position.z < o.z - 4.5, false, 2.5)
		if h <= player.movement.step_height:
			t.check(r.reached and player.global_position.y > h - 0.05, "steps up a %.2f m ledge (y %.2f)" % [h, player.global_position.y])
			t.check(r.fall_states == 0, "%.2f m ledge: no jump/fall animation" % h)
		else:
			t.check(not r.reached and player.global_position.y < 0.1, "a %.2f m block stops the player (y %.2f)" % [h, player.global_position.y])
	# Off a real drop (1.5 m): the player falls, it is not a stair.
	_wall(root, o + Vector3(10, 0.75, 8), Vector3(4, 1.5, 4))
	await _tick()
	await _spawn(o + Vector3(10, 1.6, 8))
	var fell := false
	for i in range(80):
		player.movement.set_external_move(Vector3(0, 0, 1))
		await _tick()
		if player.movement.state == PlayerMovement.State.FALL:
			fell = true
	player.movement.set_external_move(Vector3.ZERO)
	t.check(fell and player.global_position.y < 0.2, "walking off a 1.5 m drop falls")
	# Walking along a wall with a low skirting step (like a plinth): no snagging.
	_wall(root, o + Vector3(0, 3, 12), Vector3(20, 6, 0.5))
	_wall(root, o + Vector3(0, 0.1, 11.6), Vector3(20, 0.2, 0.3))
	await _tick()
	await _spawn(o + Vector3(-8, 0.05, 11.0))
	var r_skirt := await _walk(func(_p: Player) -> Vector3: return Vector3(1, 0, 0.15).normalized(),
		func(p: Player) -> bool: return p.global_position.x > o.x + 8, false, 6.0)
	_check_walk("along a wall with a skirting step", r_skirt, false)
	t.check(r_skirt.mesh.mean > player.movement.walk_speed * 0.8, "skirting step: keeps walking pace (%.2f m/s)" % r_skirt.mesh.mean)
	root.queue_free()
	await _tick()


# --- Castle ------------------------------------------------------------------------

func _test_castle_stairs() -> void:
	t.section("Castle stairs")
	var castle := CASTLE_SCENE.instantiate()
	add_child(castle)
	await get_tree().process_frame
	await _tick()
	for node in castle.get_node("Stairs").get_children():
		if not node is Staircase:
			continue
		var flight := node as Staircase
		var along := flight.global_transform.basis.x.normalized()
		var side := flight.global_transform.basis.z.normalized()
		for lateral: float in [0.0, -(flight.width / 2.0 - 0.4), flight.width / 2.0 - 0.4]:
			var foot: Vector3 = flight.global_position - along * 1.5 + side * lateral
			await _spawn(foot + Vector3(0, 0.3, 0))
			_label = "%s up (lateral %.1f)" % [flight.name, lateral]
			var mid := func(p: Player) -> bool:
				var d := (p.global_position - flight.global_position).dot(along)
				return d > 1.0 and d < flight.run - 1.0
			var r := await _walk(func(_p: Player) -> Vector3: return along,
				func(p: Player) -> bool:
					return p.global_position.y > flight.global_position.y + flight.rise - 0.2 and \
						(p.global_position - flight.global_position).dot(along) > flight.run + 0.4, false, 10.0, mid)
			_check_walk("%s up (lateral %.1f)" % [flight.name, lateral], r, false)
			if not r.reached:
				continue
			_label = "%s down (lateral %.1f)" % [flight.name, lateral]
			var r_down := await _walk(func(_p: Player) -> Vector3: return -along,
				func(p: Player) -> bool:
					return (p.global_position - flight.global_position).dot(along) < -0.6, false, 10.0, mid)
			_check_walk("%s down (lateral %.1f)" % [flight.name, lateral], r_down, false)
	castle.queue_free()
	await _tick()
