class_name HouseTally
extends StaticBody3D
## The house columns in the great hall: one glass column per house (house 1
## on the left as you face it) that fills with light in the house colour as
## its points grow, a rank numeral above each (ties share a rank, the leader
## glows brightest) and the name and points on the plinth. Totals come from
## the server (NetworkManager.house_totals_changed); a change sends a burst of
## sparks up the column (gain) or down it (loss). Offline there is no tally:
## the columns stand empty and unranked.

const COLUMN_BASE := preload("res://assets/models/school/column_base.glb")
const COLUMN_CAP := preload("res://assets/models/school/column_cap.glb")
const COLUMN_PITCH := 1.75
## The columns hum softly; a burst rises with chimes or falls with dim tones.
const HUM := preload("res://assets/audio/school/house_column_loop.wav")
const GAIN_SOUND := preload("res://assets/audio/school/house_points_gain.wav")
const LOSS_SOUND := preload("res://assets/audio/school/house_points_loss.wav")
const COLUMN_HEIGHT := 3.6
const COLUMN_RADIUS := 0.42
const PLINTH_HEIGHT := 0.6
## Columns fill against a scale of whole hundreds above the leader, so the
## leading column stands between half and fully lit and small early tallies
## don't look full.
const SCALE_STEP := 100
## A house with any points never shows an empty column.
const MIN_FILL := 0.03
const NUMERALS: Array[String] = ["I", "II", "III", "IV"]
## Height of the house crest standing on the lintel above each column, metres.
const CREST_SIZE := 0.8

## Totals in house order (index 0 = house 1); empty while there is no tally.
var totals: PackedInt32Array = PackedInt32Array()
## Rank per house (index 0 = house 1), 1 = leading; 0 while there is no tally.
var ranks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Number of bursts started so far, for tests.
var burst_count := 0

var _fills: Array[MeshInstance3D] = []
var _fill_materials: Array[StandardMaterial3D] = []
var _lights: Array[OmniLight3D] = []
var _rank_labels: Array[Label3D] = []
var _point_labels: Array[Label3D] = []
var _bursts: Array[CPUParticles3D] = []
var _fill_target: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _fill_now: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _flash: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _phase := 0.0


func _ready() -> void:
	_build()
	var hum := Sfx.loop_player(self, "Hum", HUM, -16.0, 14.0)
	hum.position.y = PLINTH_HEIGHT + COLUMN_HEIGHT / 2.0
	Sfx.start_loop(hum)
	NetworkManager.house_totals_changed.connect(set_totals)
	set_totals(NetworkManager.get_house_totals())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _fills.is_empty():
		(get_node("Title") as Label3D).text = tr("TALLY_TITLE")
		var current := totals
		totals = PackedInt32Array()   # no bursts for a relabel
		set_totals(current)


func _process(delta: float) -> void:
	_phase += delta
	for i in CharacterProfile.MAX_HOUSE:
		_fill_now[i] = move_toward(_fill_now[i], _fill_target[i], delta * 0.6)
		_flash[i] = maxf(0.0, _flash[i] - delta * 1.5)
		var h := maxf(_fill_now[i], 0.001) * (COLUMN_HEIGHT - 0.1)
		_fills[i].scale.y = h
		_fills[i].position.y = PLINTH_HEIGHT + 0.05 + h * 0.5
		var lead := 1.0 if ranks[i] == 1 else 0.0
		var pulse := 0.15 * sin(_phase * 1.6 + i) * lead
		_fill_materials[i].emission_energy_multiplier = 0.6 + 1.6 * _fill_now[i] + 0.8 * lead + pulse + 4.0 * _flash[i]
		_lights[i].position.y = PLINTH_HEIGHT + 0.05 + h
		_lights[i].light_energy = (0.25 + 1.2 * _fill_now[i] + 0.6 * lead + 3.0 * _flash[i]) if _fill_now[i] > 0.0 else 0.0


## Shows new totals (house order); anything shorter than four houses clears the
## tally. Houses whose total changed get a burst.
func set_totals(new_totals: PackedInt32Array) -> void:
	var houses := CharacterProfile.MAX_HOUSE
	var known := new_totals.size() >= houses
	var previous := totals
	totals = new_totals.slice(0, houses) if known else PackedInt32Array()
	ranks = rank_of(totals)
	var top := 0
	for p in totals:
		top = maxi(top, p)
	var scale_max := maxi(SCALE_STEP, ceili(float(top) / SCALE_STEP) * SCALE_STEP)
	for i in houses:
		var house := i + 1
		var points: int = totals[i] if known else 0
		_fill_target[i] = fill_fraction(points, scale_max) if known else 0.0
		_rank_labels[i].text = NUMERALS[ranks[i] - 1] if known else ""
		_rank_labels[i].modulate = Color(1.0, 0.86, 0.45) if ranks[i] == 1 else Color(0.85, 0.85, 0.9)
		_rank_labels[i].font_size = 150 if ranks[i] == 1 else 112
		_point_labels[i].text = "%s\n%s" % [CharacterProfile.house_name(house), tr("TALLY_POINTS") % points if known else "—"]
		if known and previous.size() >= houses and previous[i] != points:
			_burst(i, points > previous[i])


## Rank per house (ties share the better rank); zeros when `values` is not a
## full tally.
static func rank_of(values: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(CharacterProfile.MAX_HOUSE)
	out.fill(0)
	if values.size() < CharacterProfile.MAX_HOUSE:
		return out
	for i in CharacterProfile.MAX_HOUSE:
		var rank := 1
		for j in CharacterProfile.MAX_HOUSE:
			if values[j] > values[i]:
				rank += 1
		out[i] = rank
	return out


## How full a column stands for `points` against a scale of `scale_max`.
static func fill_fraction(points: int, scale_max: int) -> float:
	if points <= 0:
		return 0.0
	return clampf(float(points) / maxf(1.0, float(scale_max)), MIN_FILL, 1.0)


## Fill fraction a column is heading to (index 0 = house 1), for tests.
func fill_target(house: int) -> float:
	return _fill_target[house - 1]


func _burst(i: int, gain: bool) -> void:
	burst_count += 1
	_flash[i] = 1.0 if gain else 0.5
	var p := _bursts[i]
	p.position.y = PLINTH_HEIGHT + 0.1 if gain else PLINTH_HEIGHT + COLUMN_HEIGHT
	p.direction = Vector3.UP if gain else Vector3.DOWN
	p.gravity = Vector3(0, 0.6 if gain else -2.0, 0)
	p.color = CharacterProfile.house_color(i + 1) if gain else CharacterProfile.house_color(i + 1).darkened(0.5)
	p.restart()
	p.emitting = true
	Sfx.play_at(p, GAIN_SOUND if gain else LOSS_SOUND, -2.0, 40.0)


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.34, 0.32, 0.36)
	stone.roughness = 0.85
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.8, 0.85, 0.95, 0.16)
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	var width := COLUMN_PITCH * CharacterProfile.MAX_HOUSE + 0.4
	_box("Plinth", Vector3(width, PLINTH_HEIGHT, 1.5), Vector3(0, PLINTH_HEIGHT * 0.5, 0), stone)
	_box("Lintel", Vector3(width, 0.4, 1.0), Vector3(0, PLINTH_HEIGHT + COLUMN_HEIGHT + 0.2, 0), stone)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, PLINTH_HEIGHT + COLUMN_HEIGHT + 0.4, 1.5)
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)

	var title := _label("Title", tr("TALLY_TITLE"), 80, Vector3(0, PLINTH_HEIGHT + COLUMN_HEIGHT + 0.2, 0.51))
	title.modulate = Color(0.95, 0.88, 0.7)

	for i in CharacterProfile.MAX_HOUSE:
		var house := i + 1
		var x := (i - (CharacterProfile.MAX_HOUSE - 1) * 0.5) * COLUMN_PITCH
		var colour := CharacterProfile.house_color(house)
		var column := Node3D.new()
		column.name = "Column%d" % house
		column.position.x = x
		add_child(column)

		var tube := MeshInstance3D.new()
		var tube_mesh := CylinderMesh.new()
		tube_mesh.top_radius = COLUMN_RADIUS
		tube_mesh.bottom_radius = COLUMN_RADIUS
		tube_mesh.height = COLUMN_HEIGHT
		tube_mesh.cap_top = false
		tube_mesh.cap_bottom = false
		tube.mesh = tube_mesh
		tube.material_override = glass
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tube.position.y = PLINTH_HEIGHT + COLUMN_HEIGHT * 0.5
		column.add_child(tube)
		# An ornate brass foot and crown hold each glass column (Meshy, cut from one model).
		var foot := COLUMN_BASE.instantiate() as Node3D
		foot.scale = Vector3(1, 0.55, 1)
		foot.position.y = PLINTH_HEIGHT
		column.add_child(foot)
		var crown := COLUMN_CAP.instantiate() as Node3D
		crown.scale = Vector3(1, 0.6, 1)
		crown.position.y = PLINTH_HEIGHT + COLUMN_HEIGHT - 0.12
		column.add_child(crown)

		var fill := MeshInstance3D.new()
		var fill_mesh := CylinderMesh.new()
		fill_mesh.top_radius = COLUMN_RADIUS - 0.06
		fill_mesh.bottom_radius = COLUMN_RADIUS - 0.06
		fill_mesh.height = 1.0
		fill.mesh = fill_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.emission_enabled = true
		mat.emission = colour
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.85
		fill.material_override = mat
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fill.scale.y = 0.001
		column.add_child(fill)
		_fills.append(fill)
		_fill_materials.append(mat)

		var light := OmniLight3D.new()
		light.light_color = colour
		light.omni_range = 4.5
		light.light_energy = 0.0
		column.add_child(light)
		_lights.append(light)

		var crest := Sprite3D.new()
		crest.name = "Crest"
		crest.texture = CharacterProfile.crest(house)
		crest.pixel_size = CREST_SIZE / crest.texture.get_width()
		crest.position = Vector3(0, PLINTH_HEIGHT + COLUMN_HEIGHT + 0.4 + CREST_SIZE * 0.55, 0.35)
		column.add_child(crest)

		var rank := _label("Rank", "", 92, Vector3(0, PLINTH_HEIGHT + COLUMN_HEIGHT + 1.6, 0), column)
		rank.outline_size = 18
		_rank_labels.append(rank)
		var points := _label("Points", "", 56, Vector3(0, PLINTH_HEIGHT * 0.5, 0.76), column)
		points.modulate = colour.lightened(0.35)
		_point_labels.append(points)

		var burst := CPUParticles3D.new()
		burst.emitting = false
		burst.one_shot = true
		burst.explosiveness = 0.85
		burst.amount = 36
		burst.lifetime = 1.6
		burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		burst.emission_sphere_radius = COLUMN_RADIUS * 0.8
		burst.spread = 25.0
		burst.initial_velocity_min = 1.0
		burst.initial_velocity_max = 2.4
		burst.scale_amount_min = 0.5
		burst.scale_amount_max = 1.0
		var spark := SphereMesh.new()
		spark.radius = 0.035
		spark.height = 0.07
		var spark_mat := StandardMaterial3D.new()
		spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spark_mat.vertex_color_use_as_albedo = true
		spark.material = spark_mat
		burst.mesh = spark
		column.add_child(burst)
		_bursts.append(burst)


func _box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)


func _label(node_name: String, text: String, size: int, pos: Vector3, parent: Node = self) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.04, 0.06)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(label)
	return label
