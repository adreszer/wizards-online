extends CanvasLayer
## Developer overlay toggled with F3 (`debug_overlay` action).
## Disabled entirely in release builds unless the `game/debug/enable_debug_overlay`
## project setting is on AND the build is a debug build.

@onready var _label: Label = %Label
@onready var _panel: PanelContainer = %Panel

var _player: Node
var _enabled: bool = false
var _draw_rays: bool = false
var _ray_mesh: ImmediateMesh
var _ray_instance: MeshInstance3D


func _ready() -> void:
	_enabled = OS.is_debug_build() and bool(ProjectSettings.get_setting("game/debug/enable_debug_overlay", true))
	_panel.visible = false
	if not _enabled:
		set_process(false)
		set_process_unhandled_input(false)
		return
	GameEvents.local_player_spawned.connect(func(p: Node) -> void: _player = p)
	GameEvents.local_player_removed.connect(func(_p: Node) -> void: _player = null)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		if _panel.visible and not _draw_rays:
			_draw_rays = true
		elif _panel.visible and _draw_rays:
			_panel.visible = false
			_draw_rays = false
			_clear_rays()
		else:
			_panel.visible = true
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var lines: PackedStringArray = []
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	if _player != null and is_instance_valid(_player):
		var body := _player as CharacterBody3D
		var movement: PlayerMovement = _player.movement
		var caster: SpellCaster = _player.spell_caster
		var interaction: InteractionController = _player.interaction_controller
		lines.append("Position: (%.2f, %.2f, %.2f)" % [body.global_position.x, body.global_position.y, body.global_position.z])
		lines.append("Velocity: (%.2f, %.2f, %.2f) |h|=%.2f" % [body.velocity.x, body.velocity.y, body.velocity.z, movement.get_horizontal_speed()])
		lines.append("Grounded: %s   State: %s" % [str(movement.is_grounded), movement.get_state_name()])
		lines.append("Spell: %s   Cooldown: %.2f" % [tr(caster.equipped_spell.display_name) if caster.equipped_spell else "none", caster.cooldown_remaining])
		lines.append("Spell target: %s" % (caster.current_target.name if caster.current_target else "-"))
		lines.append("Interact focus: %s" % (interaction.focused.get_parent().name if interaction.focused else "-"))
		lines.append("Health: %d / %d" % [_player.health.current, _player.health.max_health])
		if _draw_rays:
			_draw_debug_rays(body, caster, interaction)
	if NetworkManager.is_online():
		lines.append("Network: ONLINE  ping: %s ms  players: %d" % [str(NetworkManager.get_ping_ms()) if NetworkManager.get_ping_ms() >= 0 else "?", NetworkManager.get_player_count()])
	else:
		lines.append("Network: OFFLINE (%s)" % NetworkManager.Status.keys()[NetworkManager.status])
	lines.append("Rays: %s (F3 cycles)" % ("on" if _draw_rays else "off"))
	_label.text = "\n".join(lines)


func _draw_debug_rays(body: CharacterBody3D, caster: SpellCaster, interaction: InteractionController) -> void:
	if _ray_instance == null:
		_ray_mesh = ImmediateMesh.new()
		_ray_instance = MeshInstance3D.new()
		_ray_instance.mesh = _ray_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_ray_instance.material_override = mat
		body.get_tree().current_scene.add_child(_ray_instance)
	_ray_mesh.clear_surfaces()
	_ray_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Spell aim: wand → aim point
	if caster.cast_origin != null:
		_ray_mesh.surface_set_color(Color(0.7, 0.5, 1.0))
		_ray_mesh.surface_add_vertex(caster.cast_origin.global_position)
		_ray_mesh.surface_add_vertex(caster.last_aim_point)
	# Interaction: player → focused object
	if interaction.focused != null:
		_ray_mesh.surface_set_color(Color(0.3, 1.0, 0.4))
		_ray_mesh.surface_add_vertex(interaction.global_position)
		_ray_mesh.surface_add_vertex(interaction.focused.get_focus_point())
	# Velocity
	_ray_mesh.surface_set_color(Color(1.0, 0.8, 0.2))
	_ray_mesh.surface_add_vertex(body.global_position + Vector3.UP)
	_ray_mesh.surface_add_vertex(body.global_position + Vector3.UP + body.velocity * 0.3)
	_ray_mesh.surface_end()


func _clear_rays() -> void:
	if _ray_instance != null:
		_ray_instance.queue_free()
		_ray_instance = null
		_ray_mesh = null
