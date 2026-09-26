class_name InteractionController
extends Area3D
## Local-player component. Collects nearby Interactables (Area3D overlap on
## the "interactable" layer), picks the one best aligned with the view
## direction that has line of sight, shows the prompt and fires interactions.

signal focus_changed(interactable: Interactable)
signal interaction_performed(interactable: Interactable)

## Node exposing get_aim_ray(); falls back to the parent's forward.
@export var aim_source: Node
@export var max_angle_degrees: float = 60.0
@export var los_mask: int = 1  # world
@export var debug_draw: bool = false

var focused: Interactable
var interactor: Node
var exclude_rids: Array[RID] = []


func setup(p_interactor: CollisionObject3D, p_aim_source: Node) -> void:
	interactor = p_interactor
	aim_source = p_aim_source
	exclude_rids = [p_interactor.get_rid()]


func _physics_process(_delta: float) -> void:
	var best := _pick_best()
	if best != focused:
		if focused != null:
			focused.set_focused(false)
		focused = best
		if focused != null:
			focused.set_focused(true)
		focus_changed.emit(focused)


func try_interact() -> bool:
	if focused == null or not focused.can_interact():
		return false
	if focused.interact(interactor):
		interaction_performed.emit(focused)
		return true
	return false


func _pick_best() -> Interactable:
	var candidates: Array[Interactable] = []
	for body in get_overlapping_bodies():
		var i := Interactable.find_on(body)
		if i != null:
			candidates.append(i)
	for area in get_overlapping_areas():
		var i := Interactable.find_on(area)
		if i != null:
			candidates.append(i)
	if candidates.is_empty():
		return null
	var view_origin := global_position
	var view_dir := -global_transform.basis.z
	if aim_source != null and aim_source.has_method("get_aim_ray"):
		var ray: Dictionary = aim_source.get_aim_ray()
		view_origin = ray["origin"]
		view_dir = (ray["direction"] as Vector3).normalized()
	var max_angle := deg_to_rad(max_angle_degrees)
	var best: Interactable = null
	var best_score := INF
	for c in candidates:
		if not c.can_interact():
			continue
		var p := c.get_focus_point()
		var to := p - view_origin
		var angle := view_dir.angle_to(to)
		if angle > max_angle:
			continue
		if not _has_line_of_sight(global_position, p, c.get_parent()):
			continue
		var score := angle + global_position.distance_to(p) * 0.15
		if score < best_score:
			best_score = score
			best = c
	return best


func _has_line_of_sight(from: Vector3, to: Vector3, expected: Node) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, los_mask | 16, exclude_rids)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return result["collider"] == expected
