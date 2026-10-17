class_name PoseModifier
extends SkeletonModifier3D
## Base for procedural poses written over the animation on a Mixamo-named rig
## (BroomRidePose, SocialPose): bone lookup and helpers that place, aim and blend
## bones in skeleton space. Subclasses call _resolve() and then pose bones parent
## first, recording each global pose in a dictionary `g` (bone index → Transform3D)
## so children build on what was actually written.

const BONE_PREFIX := "mixamorig_"
const BONE_NAMES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]

var _bones: Dictionary = {}


func _resolve(skeleton: Skeleton3D) -> bool:
	if not _bones.is_empty():
		return true
	for name in BONE_NAMES:
		var index := skeleton.find_bone(BONE_PREFIX + name)
		if index < 0:
			_bones.clear()
			return false
		_bones[name] = index
	return true


## The animated global pose of `bone_name` (as the AnimationTree left it this frame).
func _animated_global(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	return skeleton.get_bone_global_pose(_bones[bone_name])


## Sets `bone` to its rest orientation turned by `turn_basis` (skeleton space)
## and records its global pose in `g`.
func _place(skeleton: Skeleton3D, g: Dictionary, bone_name: String, turn_basis: Basis) -> void:
	var bone: int = _bones[bone_name]
	var parent := skeleton.get_bone_parent(bone)
	var parent_global: Transform3D = g[parent]
	var rest := skeleton.get_bone_rest(bone)
	var global := Transform3D(turn_basis * skeleton.get_bone_global_rest(bone).basis, parent_global * rest.origin)
	_write(skeleton, g, bone, parent_global, global, 1.0)


## Keeps `bone` at its rest offset under its (already posed) parent, then turns
## it by `turn_basis` in skeleton space.
func _place_relative(skeleton: Skeleton3D, g: Dictionary, bone_name: String, turn_basis: Basis, weight: float) -> void:
	var bone: int = _bones[bone_name]
	var parent_global: Transform3D = g[skeleton.get_bone_parent(bone)]
	var global := parent_global * skeleton.get_bone_rest(bone)
	global.basis = turn_basis * global.basis
	_write(skeleton, g, bone, parent_global, global, weight)


## Points `bone` (from its rest orientation under its posed parent) so the
## segment toward `child_name` runs along `dir`.
func _aim(skeleton: Skeleton3D, g: Dictionary, bone_name: String, child_name: String, dir: Vector3, weight: float) -> void:
	var bone: int = _bones[bone_name]
	var parent_global: Transform3D = g[skeleton.get_bone_parent(bone)]
	var global := parent_global * skeleton.get_bone_rest(bone)
	var current := (global.basis * skeleton.get_bone_rest(_bones[child_name]).origin).normalized()
	if current.dot(dir) < 0.99999:
		global.basis = Basis(Quaternion(current, dir)) * global.basis
	_write(skeleton, g, bone, parent_global, global, weight)


## Writes `global` as the bone's local pose (blended with the animated pose by
## `weight`) and records the global actually used.
func _write(skeleton: Skeleton3D, g: Dictionary, bone: int, parent_global: Transform3D, global: Transform3D, weight: float) -> void:
	var local := parent_global.affine_inverse() * global
	var rotation := local.basis.get_rotation_quaternion()
	if weight < 1.0:
		rotation = skeleton.get_bone_pose_rotation(bone).slerp(rotation, weight)
	skeleton.set_bone_pose_rotation(bone, rotation)
	skeleton.set_bone_pose_position(bone, local.origin)
	g[bone] = parent_global * Transform3D(Basis(rotation), local.origin)
