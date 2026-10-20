class_name Seasons
extends Node3D
## The school year shows on the grounds and in the great hall. The season comes from the
## date in school time: autumn (September–November) turns the trees' leaves russet with
## leaves drifting down, winter (December–February) whitens them and brings snow outdoors,
## spring (March–May) brings blossom; summer is green. Holidays dress the great hall:
## Lantern Night (late October: floating lanterns), Midwinter (December to Twelfth Night:
## garlands of light and a tall tree), the end of the year (late June: house banners), and a
## ball (a school event of kind "ball" running): floating lights over the hall. Candles
## float under the hall's ceiling all year.
## castle.gd adds it; nothing here is gameplay.

const HALL := &"great_hall"
const LEAF_COLOURS := {"autumn": Color(0.55, 0.28, 0.07), "winter": Color(0.72, 0.74, 0.76), "spring": Color(0.62, 0.45, 0.52), "summer": Color(0.12, 0.22, 0.08)}
const BUSH_COLOURS := {"autumn": Color(0.34, 0.24, 0.08), "winter": Color(0.6, 0.62, 0.62), "spring": Color(0.16, 0.32, 0.1), "summer": Color(0.1, 0.2, 0.08)}
const PARTICLE_COLOURS := {"autumn": Color(0.75, 0.38, 0.1), "winter": Color(0.95, 0.97, 1.0), "spring": Color(1.0, 0.75, 0.85)}

var season := ""
var holiday := ""
## Rain falls on some days (not in winter), the same days for everyone: a hash of the date.
static var rain_today := false
const RAIN_FOG := 1.8
const RAIN_COLOUR := Color(0.7, 0.75, 0.85)
var particles: GPUParticles3D
var candles: Node3D
var _hall: AreaZone
var _decor: Node3D
var _timer := 0.0


static func season_of(month: int) -> String:
	if month >= 3 and month <= 5:
		return "spring"
	if month >= 6 and month <= 8:
		return "summer"
	if month >= 9 and month <= 11:
		return "autumn"
	return "winter"


## The holiday on `month`/`day` ("" for none).
static func holiday_of(month: int, day: int) -> String:
	if (month == 10 and day >= 25) or (month == 11 and day <= 2):
		return "lantern_night"
	if month == 12 or (month == 1 and day <= 6):
		return "midwinter"
	if month == 6 and day >= 20:
		return "year_end"
	return ""


## Today in school time ({year, month, day}).
static func school_date() -> Dictionary:
	var t := NetworkManager.server_time() if NetworkManager.is_in_world() else Time.get_unix_time_from_system()
	var tz := NetworkManager.timetable.offset_minutes_at(t) if NetworkManager.timetable.received else int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(int(t) + tz * 60)


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(AreaZone.GROUP):
		if (node as AreaZone).area_id == HALL:
			_hall = node
	particles = _build_particles()
	add_child(particles)
	if _hall != null:
		candles = build_candles(_hall.global_position, _hall.size)
		add_child(candles)
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 30.0
		refresh()
	var me := get_tree().get_first_node_in_group(&"local_player") as Node3D
	var tracker: AreaTracker = me.get("area_tracker") if me != null else null
	var outdoors := tracker != null and (tracker.current_kind() == "grounds" or tracker.current_kind() == "outdoor" or tracker.current_kind() == "")
	particles.emitting = outdoors and (PARTICLE_COLOURS.has(season) or rain_today)
	if me != null:
		particles.global_position = me.global_position + Vector3.UP * 12.0
	if candles != null:
		var t := Time.get_ticks_msec() / 1000.0
		var i := 0
		for c in candles.get_children():
			(c as Node3D).position.y += sin(t * 0.8 + i) * 0.0015
			i += 1


## Whether it rains on `year`/`month`/`day`: about one day in five, never in winter (it snows).
static func rains_on(year: int, month: int, day: int) -> bool:
	if season_of(month) == "winter":
		return false
	return hash("%d-%d-%d" % [year, month, day]) % 5 == 0


## Applies today's season, weather and holiday (also whenever a school event starts or ends).
func refresh() -> void:
	var date := school_date()
	set_season(season_of(int(date.month)))
	rain_today = rains_on(int(date.year), int(date.month), int(date.day))
	var mat := particles.process_material as ParticleProcessMaterial
	if rain_today:
		mat.color = RAIN_COLOUR
		mat.gravity = Vector3(0.2, -14.0, 0.1)
		mat.initial_velocity_min = 6.0
		mat.initial_velocity_max = 9.0
	elif PARTICLE_COLOURS.has(season):
		mat.color = PARTICLE_COLOURS[season]
		mat.gravity = Vector3(0.3, -1.2, 0.1) if season == "winter" else Vector3(0.6, -1.8, 0.2)
		mat.initial_velocity_min = 0.5
		mat.initial_velocity_max = 1.5
	var h := holiday_of(int(date.month), int(date.day))
	if ball_running():
		h = "ball"
	set_holiday(h)


static func ball_running() -> bool:
	var now := NetworkManager.server_time()
	for e: Variant in (NetworkManager.feature("events").get("events", []) if NetworkManager.feature("events").get("events", []) is Array else []):
		var d: Dictionary = e
		if str(d.get("kind", "")) == "ball" and float(d.get("at", 0)) <= now and now < float(d.get("at", 0)) + float(d.get("minutes", 0)) * 60.0:
			return true
	return false


func set_season(s: String) -> void:
	if s == season:
		return
	season = s
	_tint("broadleaf", 1, LEAF_COLOURS[s])
	_tint("bush", 0, BUSH_COLOURS[s])
	_tint("conifer", 1, Color(0.62, 0.66, 0.66) if s == "winter" else Color(0.07, 0.17, 0.09))
	if PARTICLE_COLOURS.has(s):
		var mat := particles.process_material as ParticleProcessMaterial
		mat.color = PARTICLE_COLOURS[s]
		mat.gravity = Vector3(0.3, -1.2, 0.1) if s == "winter" else Vector3(0.6, -1.8, 0.2)


## The placeholder flora (shared meshes) take the season's colour.
static func _tint(kind: String, surface: int, colour: Color) -> void:
	var mesh := FloraMeshes.mesh_for(kind)
	if mesh == null or surface >= mesh.get_surface_count():
		return
	var mat := mesh.surface_get_material(surface) as StandardMaterial3D
	if mat != null:
		mat.albedo_color = colour


func _build_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SeasonParticles"
	p.amount = 400
	p.lifetime = 8.0
	p.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 30, 60))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(25, 1, 25)
	mat.direction = Vector3.DOWN
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = qm
	p.draw_pass_1 = quad
	p.emitting = false
	return p


func set_holiday(h: String) -> void:
	if h == holiday:
		return
	holiday = h
	if _decor != null:
		_decor.queue_free()
		_decor = null
	if h == "" or _hall == null:
		return
	_decor = build_decor(h, _hall.global_position, _hall.size)
	_decor.name = "Decor_" + h
	add_child(_decor)


## The great hall's decorations for holiday `h`, around the hall box (centre, size).
static func build_decor(h: String, center: Vector3, size: Vector3) -> Node3D:
	var root := Node3D.new()
	var floor_y := center.y - size.y / 2.0
	var top := floor_y + minf(size.y - 1.0, 7.5)
	match h:
		"lantern_night", "ball":
			var colour := Color(1.0, 0.6, 0.25) if h == "lantern_night" else Color(0.85, 0.85, 1.0)
			for i in 24:
				var a := float(i) / 24.0 * TAU
				var lantern := _glow_ball(colour, 0.18, i % 4 == 0)
				lantern.position = Vector3(center.x + cos(a) * size.x * 0.35, top - 1.0 - (i % 3) * 0.6, center.z + sin(a) * size.z * 0.35)
				root.add_child(lantern)
		"midwinter":
			for side in [-1.0, 1.0]:
				for i in 16:
					var bulb := _glow_ball([Color(1, 0.3, 0.3), Color(0.3, 1, 0.4), Color(1, 0.85, 0.3)][i % 3], 0.08, i % 5 == 0)
					bulb.position = Vector3(center.x + side * (size.x / 2.0 - 0.4), top - 0.5 - sin(float(i) / 15.0 * PI) * 0.8, center.z - size.z / 2.0 + 1.0 + i * (size.z - 2.0) / 15.0)
					root.add_child(bulb)
			var tree := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 1.6
			cone.height = 5.0
			tree.mesh = cone
			var green := StandardMaterial3D.new()
			green.albedo_color = Color(0.06, 0.2, 0.1)
			tree.material_override = green
			tree.position = Vector3(center.x, floor_y + 2.5, center.z - size.z * 0.4)
			root.add_child(tree)
			var star := _glow_ball(Color(1, 0.9, 0.5), 0.25, true)
			star.position = tree.position + Vector3(0, 2.7, 0)
			root.add_child(star)
		"year_end":
			for hse in range(1, 5):
				root.add_child(CharacterProfile.banner(hse, Vector3(center.x + (hse - 2.5) * size.x * 0.2, top - 0.2, center.z - size.z / 2.0 + 0.2), 1.07))
	return root


static func _glow_ball(colour: Color, radius: float, with_light: bool) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = colour
		l.light_energy = 0.8
		l.omni_range = 5.0
		n.add_child(l)
	return n


## Floating candles under the great hall's ceiling, all year: a slow bob, a few lights.
static func build_candles(center: Vector3, size: Vector3, count: int = 36) -> Node3D:
	var root := Node3D.new()
	root.name = "FloatingCandles"
	var floor_y := center.y - size.y / 2.0
	var y := floor_y + minf(size.y - 1.5, 6.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.95, 0.92, 0.82)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(1.0, 0.75, 0.35)
	for i in count:
		var c := Node3D.new()
		c.position = Vector3(center.x + rng.randf_range(-0.42, 0.42) * size.x, y + rng.randf_range(-0.4, 0.4), center.z + rng.randf_range(-0.42, 0.42) * size.z)
		var body := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = 0.28
		body.mesh = cyl
		body.material_override = wax
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(body)
		var tip := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.025
		s.height = 0.06
		tip.mesh = s
		tip.material_override = flame
		tip.position = Vector3(0, 0.17, 0)
		c.add_child(tip)
		if i % 6 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.75, 0.45)
			l.light_energy = 0.5
			l.omni_range = 6.0
			c.add_child(l)
		root.add_child(c)
	return root
