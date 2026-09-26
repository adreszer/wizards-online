
extends RefCounted
## Tiny assertion helper for the headless test runners.

var passed: int = 0
var failed: int = 0
var log_lines: PackedStringArray = []


func check(condition: bool, label: String) -> bool:
	if condition:
		passed += 1
		log_lines.append("  PASS  %s" % label)
	else:
		failed += 1
		log_lines.append("  FAIL  %s" % label)
		push_error("TEST FAIL: %s" % label)
	return condition


func section(name: String) -> void:
	log_lines.append("[%s]" % name)
	print("--- %s" % name)


func summary() -> String:
	return "\n".join(log_lines) + "\nRESULT: %d passed, %d failed" % [passed, failed]


static func make_floor(parent: Node, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = center
	return body


## A stand-in for the camera: aims from `origin` toward `target`.
class FixedAim extends Node:
	var origin: Vector3
	var target: Vector3

	func get_aim_ray() -> Dictionary:
		return {"origin": origin, "direction": (target - origin).normalized()}
