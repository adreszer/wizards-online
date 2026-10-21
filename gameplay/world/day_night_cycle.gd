class_name DayNightCycle
extends Node
## Lights the world from the school clock (NetworkManager.school_hours(), the same
## on every client): the sky's colours and stars, the sun or moon over the grounds,
## the faint daylight that reaches the interiors, ambient light, fog, the
## window panes, and (through the Lamplighter) the candles of rooms with windows. The level adds it next to its WorldEnvironment (castle.gd).
##
## Lights it drives, found by name on the level root:
##   Moon  the outdoor light (render layer 11 only: terrain, water, facade). It is
##         the sun by day and the moon by night; the switch happens while the body
##         is at the horizon and the light has faded to nothing.
##   Sun   the faint fill that lights interiors through the windows (all layers);
##         a little brighter and warmer by day. It shines straight down, so daylight in
##         a room comes from above and no wall is lit more than the one facing it; with
##         global illumination on it is stronger (FILL_GI) and the bounce spreads it.
##         GI also drops the flat ambient light, so with GI on four weak horizontal
##         fills and one shining up (BOUNCE_FILLS, interiors only, no highlights) stand
##         in for the light walls and ceilings would get from the whole room; they are
##         created here and off without GI.
## Looks between the key hours in KEYS are blended linearly.

signal phase_changed(phase: SchoolClock.Phase)

## Highest elevation of the sun at noon and of the moon at midnight (degrees).
const MAX_ELEVATION_DEG := 58.0
const SUN_ENERGY := 1.25
const MOON_ENERGY := 0.38
const SUN_LOW := Color(1.0, 0.58, 0.32)
const SUN_HIGH := Color(1.0, 0.96, 0.9)
const MOON_COLOR := Color(0.55, 0.64, 0.95)
## The fill's energy multiplier with global illumination on: GI drops the flat ambient,
## so the overhead fill and its bounce carry the daylight in rooms.
const FILL_GI := 5.0
## The bounce fills (GI only): direction the light travels → share of the overhead fill.
const BOUNCE_FILLS := {Vector3.LEFT: 0.35, Vector3.RIGHT: 0.35, Vector3.FORWARD: 0.35, Vector3.BACK: 0.35, Vector3.UP: 0.25}
## Every render layer but the outdoor one (11): the wall fills light interiors only.
const INTERIOR_LAYERS := 0xFFFFF & ~(1 << 10)

## Key looks by school hour. day: how much daylight (0–1) drives windows and glows.
const KEYS := [
	{"h": 0.0, "top": Color(0.015, 0.02, 0.045), "hor": Color(0.07, 0.08, 0.12), "gnd": Color(0.07, 0.08, 0.11),
		"amb": Color(0.5, 0.5, 0.56), "amb_e": 0.22, "fog": Color(0.09, 0.1, 0.13), "fog_d": 0.0016,
		"fill": Color(0.85, 0.86, 0.95), "fill_e": 0.06, "stars": 1.0, "day": 0.0},
	{"h": 4.6, "top": Color(0.015, 0.02, 0.045), "hor": Color(0.07, 0.08, 0.12), "gnd": Color(0.07, 0.08, 0.11),
		"amb": Color(0.5, 0.5, 0.56), "amb_e": 0.22, "fog": Color(0.09, 0.1, 0.13), "fog_d": 0.0016,
		"fill": Color(0.85, 0.86, 0.95), "fill_e": 0.06, "stars": 1.0, "day": 0.0},
	{"h": 6.0, "top": Color(0.16, 0.22, 0.4), "hor": Color(0.93, 0.55, 0.36), "gnd": Color(0.3, 0.24, 0.22),
		"amb": Color(0.72, 0.6, 0.56), "amb_e": 0.27, "fog": Color(0.55, 0.42, 0.38), "fog_d": 0.0015,
		"fill": Color(1.0, 0.72, 0.55), "fill_e": 0.1, "stars": 0.15, "day": 0.45},
	{"h": 8.0, "top": Color(0.24, 0.42, 0.72), "hor": Color(0.66, 0.74, 0.84), "gnd": Color(0.3, 0.3, 0.29),
		"amb": Color(0.75, 0.8, 0.88), "amb_e": 0.34, "fog": Color(0.62, 0.7, 0.8), "fog_d": 0.0011,
		"fill": Color(1.0, 0.96, 0.9), "fill_e": 0.16, "stars": 0.0, "day": 1.0},
	{"h": 17.0, "top": Color(0.24, 0.42, 0.72), "hor": Color(0.66, 0.74, 0.84), "gnd": Color(0.3, 0.3, 0.29),
		"amb": Color(0.75, 0.8, 0.88), "amb_e": 0.34, "fog": Color(0.62, 0.7, 0.8), "fog_d": 0.0011,
		"fill": Color(1.0, 0.96, 0.9), "fill_e": 0.16, "stars": 0.0, "day": 1.0},
	{"h": 18.8, "top": Color(0.2, 0.22, 0.42), "hor": Color(0.96, 0.48, 0.26), "gnd": Color(0.3, 0.22, 0.2),
		"amb": Color(0.78, 0.6, 0.52), "amb_e": 0.27, "fog": Color(0.58, 0.4, 0.34), "fog_d": 0.0014,
		"fill": Color(1.0, 0.66, 0.45), "fill_e": 0.1, "stars": 0.1, "day": 0.45},
	{"h": 20.6, "top": Color(0.015, 0.02, 0.045), "hor": Color(0.07, 0.08, 0.12), "gnd": Color(0.07, 0.08, 0.11),
		"amb": Color(0.5, 0.5, 0.56), "amb_e": 0.22, "fog": Color(0.09, 0.1, 0.13), "fog_d": 0.0016,
		"fill": Color(0.85, 0.86, 0.95), "fill_e": 0.06, "stars": 1.0, "day": 0.0},
]

## Pins the time of day (hours) for tests and tools; NAN follows the school clock.
@export var time_override: float = NAN
## Seconds between updates: one school hour lasts minutes, so a few updates a second
## move the sun in invisible steps.
@export var update_interval: float = 0.25

var environment: Environment
var sky_material: ProceduralSkyMaterial
var sky_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var bounce_fills: Array[DirectionalLight3D] = []
var hours := 0.0
var phase := SchoolClock.Phase.NIGHT
var daylight := 0.0

var _timer := 0.0
var _phase_known := false
## CastleExterior and Village nodes: their window glows follow the daylight (set_daylight).
var _exteriors: Array[Node] = []


func _ready() -> void:
	var level := get_parent()
	var world_env := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		# A copy, so the scene's resource (and other users of it) stay as authored.
		environment = world_env.environment.duplicate(true)
		world_env.environment = environment
		if environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
			sky_material = environment.sky.sky_material as ProceduralSkyMaterial
			sky_material.sky_cover = _star_texture()
	sky_light = level.get_node_or_null("Moon") as DirectionalLight3D
	fill_light = level.get_node_or_null("Sun") as DirectionalLight3D
	if fill_light != null:
		fill_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # no second disc in the sky
		fill_light.light_specular = 0.2   # sky light: no sharp highlight on the floors
		fill_light.shadow_enabled = false   # it shines through the ceilings (the shadows setting skips it)
		fill_light.set_meta(GameSettings.NO_SHADOWS, true)
		for dir: Vector3 in BOUNCE_FILLS:
			var bounce := DirectionalLight3D.new()
			bounce.name = "BounceFill"
			bounce.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
			bounce.light_cull_mask = INTERIOR_LAYERS
			bounce.light_specular = 0.0
			bounce.shadow_enabled = false
			bounce.set_meta(GameSettings.NO_SHADOWS, true)
			bounce.visible = false
			bounce.basis = Basis.looking_at(dir, Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP)
			bounce.set_meta(&"share", BOUNCE_FILLS[dir])
			level.add_child.call_deferred(bounce)
			bounce_fills.append(bounce)
	for type in ["CastleExterior", "Village"]:
		_exteriors.append_array(level.find_children("*", type, true, false))
	NetworkManager.school_clock_changed.connect(func(_by: String) -> void: refresh())
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		refresh()


## Applies the look for the current time (or time_override) right away.
func refresh() -> void:
	hours = time_override if not is_nan(time_override) else NetworkManager.school_hours()
	apply_hours(hours)
	var p := SchoolClock.phase_of(hours)
	if p != phase or not _phase_known:
		var announce := _phase_known
		phase = p
		_phase_known = true
		phase_changed.emit(phase)
		GameEvents.time_phase_changed.emit(phase)
		if announce and phase == SchoolClock.Phase.DAWN:
			GameEvents.notify(tr("NOTIFY_DAWN"), 4.0, ToastStack.Kind.INFO, "day")
		elif announce and phase == SchoolClock.Phase.NIGHT:
			GameEvents.notify(tr("NOTIFY_NIGHTFALL"), 4.0, ToastStack.Kind.INFO, "night")


## Direction toward the sun (unit vector) at `h` school hours: it rises in the east
## (+X) at 6:00, stands south (+Z) at noon and sets in the west at 18:00.
static func sun_direction(h: float) -> Vector3:
	var theta := (h - 6.0) / 24.0 * TAU
	var tilt := deg_to_rad(MAX_ELEVATION_DEG)
	return Vector3(cos(theta), sin(theta) * sin(tilt), sin(theta) * cos(tilt)).normalized()


## The blended look at `h` hours (see KEYS).
static func look_at_hour(h: float) -> Dictionary:
	h = fposmod(h, 24.0)
	var a: Dictionary = KEYS[KEYS.size() - 1]
	var b: Dictionary = KEYS[0]
	var a_h: float = a.h
	var span: float = 24.0 - a_h + float(b.h)
	var t: float = (h - a_h) / span if h >= a_h else (h + 24.0 - a_h) / span
	for i in range(KEYS.size() - 1):
		var h0: float = KEYS[i].h
		var h1: float = KEYS[i + 1].h
		if h >= h0 and h < h1:
			a = KEYS[i]
			b = KEYS[i + 1]
			t = (h - h0) / (h1 - h0)
			break
	var out := {}
	for key: String in a:
		if key == "h":
			continue
		var va: Variant = a[key]
		out[key] = (va as Color).lerp(b[key], t) if va is Color else lerpf(va, b[key], t)
	return out


## Per-area atmosphere over the hour's look: cold blue dungeons, a green greenhouse, a
## warm hazy great hall, a golden library, starlit towers. Where the local player stands
## picks it; it fades in and out over a second or two. fill_k scales the daylight fill
## (no daylight reaches the dungeons).
const ATMOSPHERES := {
	"dungeon": {"amb": Color(0.45, 0.55, 0.78), "amb_k": 0.45, "fog": Color(0.12, 0.17, 0.28), "fog_k": 3.0, "fill_k": 0.0},
	"greenhouse": {"amb": Color(0.55, 0.82, 0.5), "amb_k": 1.1, "fog": Color(0.28, 0.42, 0.26), "fog_k": 2.0},
	"great_hall": {"amb": Color(0.95, 0.72, 0.5), "amb_k": 1.15, "fog": Color(0.45, 0.33, 0.22), "fog_k": 2.4},
	"library": {"amb": Color(0.9, 0.75, 0.55), "amb_k": 1.0, "fog": Color(0.34, 0.28, 0.2), "fog_k": 1.5},
	"tower": {"amb": Color(0.6, 0.66, 0.92), "amb_k": 0.95, "fog": Color(0.18, 0.2, 0.34), "fog_k": 1.3},
}
var atmosphere := ""
var _atmosphere_weight := 0.0
## Area kinds under the open sky; everywhere else is indoors.
const OPEN_AIR_KINDS := ["outdoor", "grounds", "bridge", "station"]
## Indoors the flat ambient light falls to this share: rooms are lit by their candles and
## torches, and by what you carry. (With global illumination on, light that really comes
## in through windows and doors replaces the flat ambient anyway.)
const INDOOR_AMBIENT := 0.35
## 0 outdoors … 1 indoors, eased like the atmosphere.
var indoors := 0.0


## Which atmosphere an area has ("" for none).
static func atmosphere_for(area_id: String, kind: String) -> String:
	if area_id in ["cellars", "dungeon_corridor", "old_cells", "undercroft", "cold_store", "hidden_wine_cellar"] or area_id.ends_with("_cm1"):
		return "dungeon"
	if area_id == "greenhouse":
		return "greenhouse"
	if area_id == "great_hall":
		return "great_hall"
	if kind == "library":
		return "library"
	if kind == "tower":
		return "tower"
	return ""


func _current_atmosphere() -> String:
	var tracker := _tracker()
	if tracker == null:
		return ""
	return atmosphere_for(str(tracker.current_area_id()), tracker.current_kind())


## Whether an area of `kind` is indoors ("" is no area: the open grounds).
static func is_indoor_kind(kind: String) -> bool:
	return kind != "" and not OPEN_AIR_KINDS.has(kind)


func _tracker() -> AreaTracker:
	var me := get_tree().get_first_node_in_group(&"local_player") if is_inside_tree() else null
	return me.get("area_tracker") if me != null else null


func apply_hours(h: float) -> void:
	var look := look_at_hour(h)
	daylight = look.day
	var target := _current_atmosphere()
	if target != atmosphere:
		_atmosphere_weight = maxf(0.0, _atmosphere_weight - 0.2)
		if _atmosphere_weight <= 0.0:
			atmosphere = target
	elif atmosphere != "":
		_atmosphere_weight = minf(1.0, _atmosphere_weight + 0.2)
	var tracker := _tracker()
	var want_indoors := 1.0 if tracker != null and is_indoor_kind(tracker.current_kind()) else 0.0
	indoors = move_toward(indoors, want_indoors, 0.2)
	if environment != null:
		var atm: Dictionary = ATMOSPHERES.get(atmosphere, {})
		var w := _atmosphere_weight if not atm.is_empty() else 0.0
		environment.ambient_light_color = (look.amb as Color).lerp(atm.get("amb", look.amb), w * 0.6)
		environment.ambient_light_energy = float(look.amb_e) * lerpf(1.0, float(atm.get("amb_k", 1.0)), w) * lerpf(1.0, INDOOR_AMBIENT, indoors)
		environment.fog_light_color = (look.fog as Color).lerp(atm.get("fog", look.fog), w * 0.7)
		environment.fog_density = float(look.fog_d) * lerpf(1.0, float(atm.get("fog_k", 1.0)), w) * morning_mist(h) * (Seasons.RAIN_FOG if Seasons.rain_today else 1.0)
	if sky_material != null:
		sky_material.sky_top_color = look.top
		sky_material.sky_horizon_color = look.hor
		sky_material.ground_horizon_color = look.gnd
		sky_material.sky_cover_modulate = Color(1, 1, 1, look.stars)
	var gi := environment != null and environment.sdfgi_enabled
	if fill_light != null:
		var atm_fill := float(ATMOSPHERES.get(atmosphere, {}).get("fill_k", 1.0))
		fill_light.light_color = look.fill
		fill_light.light_energy = float(look.fill_e) * (FILL_GI if gi else 1.0) * lerpf(1.0, atm_fill, _atmosphere_weight)
		for bounce in bounce_fills:
			bounce.visible = gi
			bounce.light_color = look.fill
			bounce.light_energy = fill_light.light_energy * float(bounce.get_meta(&"share"))
	if sky_light != null:
		_place_sky_light(sun_direction(h))
	WallWindow.set_daylight(daylight, gi)
	if is_inside_tree():
		Lamplighter.apply(get_tree(), h)
	for exterior in _exteriors:
		if is_instance_valid(exterior):
			exterior.call("set_daylight", daylight)


## The sun while it is above the horizon, the moon (opposite it) otherwise; each
## fades in over its first ~15° so the swap at the horizon never shows.
func _place_sky_light(to_sun: Vector3) -> void:
	var is_sun := to_sun.y >= 0.0
	var to_body := to_sun if is_sun else -to_sun
	var rise := smoothstep(0.0, 0.26, to_body.y)
	if is_sun:
		sky_light.light_color = SUN_LOW.lerp(SUN_HIGH, smoothstep(0.1, 0.5, to_body.y))
		sky_light.light_energy = SUN_ENERGY * rise
	else:
		sky_light.light_color = MOON_COLOR
		# The moon waxes and wanes with the real calendar: a new moon gives a darker night.
		sky_light.light_energy = MOON_ENERGY * rise * lerpf(0.25, 1.0, moon_illumination(Time.get_unix_time_from_system()))
	# A light shines along its -Z: point it from the body toward the ground.
	sky_light.global_basis = Basis.looking_at(-to_body, Vector3.UP)
	sky_light.visible = rise > 0.001


## How much of the moon is lit at unix time `t` (0 new … 1 full), from a known new moon
## (2000-01-06 18:14 UTC) and the synodic month. Astronomy lessons can read it too.
const NEW_MOON := 947182440.0
const SYNODIC_DAYS := 29.530588


static func moon_illumination(t: float) -> float:
	var age := fposmod((t - NEW_MOON) / 86400.0, SYNODIC_DAYS) / SYNODIC_DAYS
	return (1.0 - cos(age * TAU)) / 2.0


## Mornings are misty: extra fog from first light until the sun is well up.
static func morning_mist(hours: float) -> float:
	if hours < 4.5 or hours > 9.0:
		return 1.0
	return 1.0 + 1.6 * sin((hours - 4.5) / 4.5 * PI)


## A star field for the night sky (equirectangular, blended in by sky_cover_modulate).
## Generated once: a few thousand points, denser and brighter away from the horizon.
static var _stars: ImageTexture

static func _star_texture() -> ImageTexture:
	if _stars != null:
		return _stars
	var w := 2048
	var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for i in 3200:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h / 2 - 8)   # upper half: above the horizon
		var height := 1.0 - float(y) / (h / 2.0)   # 0 at the horizon, 1 overhead
		var b := rng.randf_range(0.25, 1.0) * lerpf(0.35, 1.0, height)
		var tint := Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.92, 0.8), rng.randf())
		img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, b))
		if b > 0.85 and x + 1 < w:
			img.set_pixel(x + 1, y, Color(tint.r, tint.g, tint.b, b * 0.5))
	_stars = ImageTexture.create_from_image(img)
	return _stars
