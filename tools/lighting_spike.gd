extends Node
## Dev tool: the global-illumination spike (roadmap 5.1). Loads the castle and, for each
## view and school hour, renders it under each lighting mode, saving a PNG and the
## average frame time, draw calls and shadow draw calls (needs a window; not --headless;
## Metal reports no GPU timings, and --always-on-top keeps macOS from throttling the window).
##   godot --always-on-top --path . tools/lighting_spike.tscn -- --out=/abs/dir [--modes=base,ssil,sdfgi,voxelgi] [--hours=0,12]
##       [--views=great_hall,dungeon] [--scale=2.0] [--lights=asis|game|fade|noshadow|near|still|movers]
## --scale renders the 3D at that multiple of the window (2.0 makes a fast GPU the
## bottleneck, roughly a mid laptop at 1080p); --lights changes every placed light first.
## Modes: base (no GI, no SSAO), ssil (SSAO + SSIL), sdfgi (SDFGI + SSAO), voxelgi (a
## VoxelGI baked at runtime around the view + SSAO), sdfgi_nofill (no daylight fill),
## sdfgi_sun (no fill; the sun lights every layer and casts shadows, so daylight comes in
## through the windows), sdfgi_topfill / base_topfill (the fill straight down),
## sdfgi_windows (no fill; window panes glow as GI light sources), sdfgi_both (both).
## The castle's own setup is "--modes=sdfgi --lights=game". Findings: docs/lighting.md.
## Writes report.json next to the PNGs.

const CASTLE := "res://levels/castle/castle.tscn"
const VIEWS := [
	["great_hall", Vector3(28, 1.7, 44), Vector3(28, 4, 10)],
	["entrance_hall", Vector3(0, 1.7, 44), Vector3(0, 3, 20)],
	["corridor_w", Vector3(-16, 1.7, 20), Vector3(-16, 2, -30)],
	["library", Vector3(-15, 2.0, -45), Vector3(10, 3, -58)],
	["classroom", Vector3(-42, 1.7, 5), Vector3(-22, 1.5, -4)],
	["dungeon", Vector3(-16, -7.3, 20), Vector3(-16, -7.5, -30)],
	["cellars", Vector3(-40, -7.3, -3), Vector3(-24, -8, -12)],
]

var out_dir := "user://lighting_spike"
var modes: PackedStringArray = ["base", "ssil", "sdfgi", "voxelgi"]
var hours: PackedFloat64Array = [0.0, 12.0]
var only_views: PackedStringArray = []
var scale := 1.0
var lights_mode := "asis"
var _env: Environment
var _cam: Camera3D
var _voxel: VoxelGI
var _fill: DirectionalLight3D
var _sky: DirectionalLight3D
var _fill_basis: Basis


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--modes="):
			modes = arg.trim_prefix("--modes=").split(",")
		elif arg.begins_with("--views="):
			only_views = arg.trim_prefix("--views=").split(",")
		elif arg.begins_with("--scale="):
			scale = float(arg.trim_prefix("--scale="))
		elif arg.begins_with("--lights="):
			lights_mode = arg.trim_prefix("--lights=")
		elif arg.begins_with("--hours="):
			hours = PackedFloat64Array(Array(arg.trim_prefix("--hours=").split(",")).map(func(s: String) -> float: return float(s)))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _run()


func _run() -> void:
	_cam = Camera3D.new()
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true
	_cam.global_position = VIEWS[0][1]
	var castle: Node3D = (load(CASTLE) as PackedScene).instantiate()
	add_child(castle)
	await _frames(10)
	_env = (castle.get_node("WorldEnvironment") as WorldEnvironment).environment
	var cycle := castle.get_node("DayNightCycle") as DayNightCycle
	cycle.set_process(false)   # the modes below change its lights; refresh() only on a new hour
	_fill = castle.get_node("Sun") as DirectionalLight3D
	_sky = castle.get_node("Moon") as DirectionalLight3D
	_fill_basis = _fill.global_basis
	get_viewport().scaling_3d_scale = scale
	var lights := castle.find_children("*", "OmniLight3D", true, false)
	if lights_mode == "still":
		for c in ["Torches", "Lights", "Props", "Tomes", "Collectibles", "Puzzles"]:
			castle.get_node(c).process_mode = Node.PROCESS_MODE_DISABLED
	if lights_mode == "noflicker":
		for c in ["Torches", "Lights"]:
			castle.get_node(c).process_mode = Node.PROCESS_MODE_DISABLED
	if lights_mode == "game":
		LightQuality.shadow_distance = LightQuality.distance_for("high", true)
		LightQuality.watch(get_tree())
	for l: OmniLight3D in lights:
		if lights_mode == "noshadow":
			l.shadow_enabled = false
		elif lights_mode == "fade":
			l.distance_fade_enabled = true
			l.distance_fade_begin = 40.0
			l.distance_fade_length = 10.0
			l.distance_fade_shadow = 20.0
	var report := {"lights": lights.size(), "scale": scale, "lights_mode": lights_mode, "views": {}}
	for v: Array in VIEWS:
		if not only_views.is_empty() and not only_views.has(v[0]):
			continue
		_cam.global_position = v[1]
		_cam.look_at(v[2], Vector3.UP)
		if lights_mode.begins_with("near"):
			var shadowed := 0
			for l: OmniLight3D in lights:
				l.shadow_enabled = l.global_position.distance_to(v[1]) < 20.0
				shadowed += int(l.shadow_enabled)
			print("shadowed lights near ", v[0], ": ", shadowed)
		if lights_mode == "movers":
			await _report_movers(castle, v[1])
		if lights_mode == "near_still":
			for c in ["Torches", "Lights", "Props", "Tomes", "Collectibles", "Puzzles"]:
				castle.get_node(c).process_mode = Node.PROCESS_MODE_DISABLED
		for h in hours:
			cycle.time_override = h
			cycle.refresh()
			for mode in modes:
				cycle.refresh()
				await _apply_mode(mode, v[1])
				await _frames(150 if mode.begins_with("sdfgi") else 60)   # SDFGI converges over frames
				var m := await _measure(90)
				var key := "%s_%02d_%s" % [v[0], int(h), mode]
				report["views"][key] = m
				get_viewport().get_texture().get_image().save_png(out_dir.path_join(key + ".png"))
				print(key, " ", m)
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	get_tree().quit(0)


func _apply_mode(mode: String, at: Vector3) -> void:
	_env.sdfgi_enabled = mode.begins_with("sdfgi")
	_env.ssil_enabled = mode == "ssil"
	_fill.visible = mode not in ["sdfgi_nofill", "sdfgi_sun", "sdfgi_windows"]
	if mode in ["sdfgi_windows", "sdfgi_both"]:
		# Window panes as daylight sources for the GI (SDFGI reads emissive geometry).
		var glass := WallWindow._get_glass_material()
		glass.emission_energy_multiplier *= float(OS.get_environment("WIN_K")) if OS.has_environment("WIN_K") else 6.0
	if mode.ends_with("topfill") or mode == "sdfgi_both":
		# A near-vertical fill: daylight from above, even on every wall, not from one side.
		_fill.global_basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
		_fill.light_energy *= float(OS.get_environment("TOPFILL_K")) if OS.has_environment("TOPFILL_K") else 1.5
	else:
		_fill.global_basis = _fill_basis
	if mode == "sdfgi_sun":
		_sky.light_cull_mask = 0xFFFFF
		_sky.shadow_enabled = true
		_sky.directional_shadow_max_distance = 120.0
	else:
		_sky.light_cull_mask = 1 << 10
		_sky.shadow_enabled = false
	_env.ssao_enabled = mode != "base"
	if _voxel != null:
		_voxel.queue_free()
		_voxel = null
	if mode.begins_with("sdfgi"):
		_env.sdfgi_use_occlusion = true
		_env.sdfgi_cascades = 4
		_env.sdfgi_min_cell_size = 0.25
		_env.sdfgi_bounce_feedback = 0.5
		_env.sdfgi_energy = 1.0
	elif mode == "voxelgi":
		_voxel = VoxelGI.new()
		_voxel.size = Vector3(72, 24, 72)
		add_child(_voxel)
		_voxel.global_position = at + Vector3(0, 6, 0)
		_voxel.subdiv = VoxelGI.SUBDIV_128
		var t := Time.get_ticks_msec()
		_voxel.bake()
		print("voxelgi bake ms ", Time.get_ticks_msec() - t)
	await _frames(2)


func _measure(n: int) -> Dictionary:
	var total := 0.0
	var draws := 0
	var shadow_draws := 0
	for i in range(n):
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		total += (Time.get_ticks_usec() - t) / 1000.0
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		shadow_draws += RenderingServer.viewport_get_render_info(get_viewport().get_viewport_rid(),
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return {"frame_ms": snappedf(total / n, 0.01), "draws": draws / n, "shadow_draws": shadow_draws / n}


## Prints shadow-casting geometry near `at` whose transform changes: each one makes every
## shadowed light around it render its shadow again.
func _report_movers(root: Node, at: Vector3) -> void:
	var before := {}
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.is_visible_in_tree() \
				and g.global_position.distance_to(at) < 30.0:
			before[g] = g.global_transform
	await _frames(30)
	var counts := {}
	for g: GeometryInstance3D in before:
		if is_instance_valid(g) and not g.global_transform.is_equal_approx(before[g]):
			var owner_path := str(g.owner.scene_file_path if g.owner != null else "") + " :: " + str(g.get_path()).get_slice("/", 4)
			counts[owner_path] = counts.get(owner_path, 0) + 1
	# Particles and skinned meshes animate without moving their node.
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		var animated := g is GPUParticles3D or g is CPUParticles3D or (g is MeshInstance3D and (g as MeshInstance3D).skin != null) \
			or (g is MeshInstance3D and not (g as MeshInstance3D).skeleton.is_empty() and g.get_node_or_null((g as MeshInstance3D).skeleton) != null)
		if animated and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.is_visible_in_tree() \
				and g.global_position.distance_to(at) < 30.0:
			var key := "animated " + g.get_class() + " " + str(g.owner.scene_file_path if g.owner != null else g.get_path())
			counts[key] = counts.get(key, 0) + 1
	print("movers: ", JSON.stringify(counts, "  "))


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
