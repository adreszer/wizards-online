class_name SitterPose
extends PoseModifier
## A portrait sitter's resting life, under SocialPose's gestures: slow breathing in
## the chest, the head turned toward [member look] (yaw, pitch in radians, eased),
## and for sitters generated in a T-pose ([member relaxed]) the hands folded in
## front, as their paintings show them. Directions are skeleton space, as in
## SocialPose (+Z forward, +X the sitter's left).

const FWD := Vector3(0, 0, 1)
const UP := Vector3(0, 1, 0)
const LEFT := Vector3(1, 0, 0)
const RIGHT := Vector3(-1, 0, 0)

## Lower the T-pose arms and fold the hands in front.
var relaxed := false
## Where the head should turn: x = yaw (toward the sitter's left), y = pitch (down).
var look := Vector2.ZERO
## Seconds into the breathing cycle (offset per sitter so neighbours differ).
var phase := 0.0

var _look := Vector2.ZERO


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not _resolve(skeleton):
		return
	phase += delta
	_look = _look.lerp(look, minf(1.0, delta * 2.5))
	var g := {}
	for name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder"]:
		g[_bones[name]] = skeleton.get_bone_global_pose(_bones[name])
	var breath := sin(phase * TAU / 4.2) * 0.018
	_place_relative(skeleton, g, "Spine1", Basis(LEFT, breath), 1.0)
	_place_relative(skeleton, g, "Spine2", Basis(LEFT, breath * 0.6), 1.0)
	_place_relative(skeleton, g, "Neck", Basis(UP, _look.x * 0.35), 1.0)
	_place_relative(skeleton, g, "Head", Basis(UP, _look.x * 0.65) * Basis(LEFT, _look.y), 1.0)
	if relaxed:
		for side in [1.0, -1.0]:
			var prefix := "Left" if side > 0.0 else "Right"
			var out: Vector3 = LEFT * side
			_place_relative(skeleton, g, prefix + "Shoulder", Basis.IDENTITY, 1.0)
			_aim(skeleton, g, prefix + "Arm", prefix + "ForeArm", (-UP + out * 0.14 + FWD * 0.22).normalized(), 1.0)
			_aim(skeleton, g, prefix + "ForeArm", prefix + "Hand", (-out * 0.6 - UP * 0.3 + FWD * 0.72).normalized(), 1.0)
			_place_relative(skeleton, g, prefix + "Hand", Basis.IDENTITY, 1.0)
