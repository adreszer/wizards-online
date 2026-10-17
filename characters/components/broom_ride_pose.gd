class_name BroomRidePose
extends PoseModifier
## Procedural riding pose layered over the animation while on a broom: the
## character sits astride the shaft, leans over it, grips it with both hands
## and tucks or dangles the legs with the flight. The rig has no riding clip,
## so this modifier writes the pose after the AnimationTree runs; [member
## influence] (ramped by BroomRider) blends it in and out on mount and landing.
##
## Everything is placed relative to [member mount] (the broom node: seat at
## its origin, shaft toward its -Z), so the pose follows the broom whatever the
## model's orientation or scale. Works on any Mixamo-named rig.
##
## BroomRider feeds the flight each frame: [member speed] 0 hover … 1 boost,
## [member climb] −1 dive … 1 climb, [member turn] −1 … 1 (left/right). A cast
## frees the wand arm for the clip ([method release_wand_hand]).

## Broom node the pose sits on.
var mount: Node3D
var speed: float = 0.0
var climb: float = 0.0
var turn: float = 0.0

## Hover: upright-ish, legs dangling. Fast: low over the shaft, legs tucked back.
@export var lean_hover: float = 0.38
@export var lean_fast: float = 0.85
## Hips above the shaft (thighs resting on it).
@export var seat_clearance: float = 0.085
## Hand grips along the shaft, in front of the seat (front hand, back hand).
@export var grip_front: float = 0.50
@export var grip_back: float = 0.34

var _time: float = 0.0
## 1 while the wand hand holds the shaft, 0 while it is free for a cast.
var wand_grip: float = 1.0
var _wand_release: float = 0.0
## Last broom frame in skeleton space (kept while blending out after landing).
var _frame: Transform3D = Transform3D.IDENTITY
var _has_frame: bool = false


## A spell is being cast: let the wand (right) arm play the cast clip for a moment.
func release_wand_hand(seconds: float = 0.9) -> void:
	_wand_release = maxf(_wand_release, seconds)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not _resolve(skeleton):
		return
	_time += delta
	_wand_release = maxf(_wand_release - delta, 0.0)
	wand_grip = move_toward(wand_grip, 0.0 if _wand_release > 0.0 else 1.0, delta * 6.0)
	if mount != null and is_instance_valid(mount) and mount.is_inside_tree():
		_frame = skeleton.global_transform.affine_inverse() * mount.global_transform
		_frame.basis = _frame.basis.orthonormalized()
		_has_frame = true
	if not _has_frame:
		return
	_pose(skeleton)


func _pose(skeleton: Skeleton3D) -> void:
	var seat := _frame.origin
	var fwd := -_frame.basis.z
	var up := _frame.basis.y
	var left := up.cross(fwd).normalized()
	var hover := 1.0 - clampf(speed * 2.0, 0.0, 1.0)
	# The rig's rest faces +Z with +Y up and +X to its left; turn it onto the broom.
	var onto := Basis(left, up, fwd)
	var lean := lerpf(lean_hover, lean_fast, clampf(speed, 0.0, 1.0)) + 0.04 * sin(_time * 1.7) * hover
	lean = clampf(lean - climb * 0.12, 0.2, 1.0)

	# Hips on the shaft, tipped forward with the lean; the spine curls the rest.
	var hips: int = _bones["Hips"]
	var hips_basis := Basis(left, lean * 0.35) * onto * skeleton.get_bone_global_rest(hips).basis
	var g := {}
	g[hips] = Transform3D(hips_basis, seat + up * seat_clearance - fwd * 0.04)
	skeleton.set_bone_pose_rotation(hips, hips_basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(hips, g[hips].origin)
	var bank := Basis(fwd, turn * 0.12)
	_place(skeleton, g, "Spine", Basis(left, lean * 0.55) * onto)
	_place(skeleton, g, "Spine1", bank * Basis(left, lean * 0.8) * onto)
	_place(skeleton, g, "Spine2", bank * Basis(left, lean) * onto)
	# Neck and head tip back up so the eyes stay on the way ahead, glancing into turns.
	var look := Basis(up, -turn * 0.35) * Basis(left, lean * 0.3 - climb * 0.15)
	_place(skeleton, g, "Neck", bank * Basis(left, lean * 0.7) * onto)
	_place(skeleton, g, "Head", look * onto)

	# Arms: both hands on the shaft ahead (left in front); a cast frees the right.
	_place(skeleton, g, "LeftShoulder", bank * Basis(left, lean) * onto)
	_place(skeleton, g, "RightShoulder", bank * Basis(left, lean) * onto)
	var reach := lerpf(0.0, 0.08, clampf(speed, 0.0, 1.0))
	_arm(skeleton, g, "Left", seat + fwd * (grip_front + reach) + left * 0.03 + up * 0.035, left, 1.0)
	_arm(skeleton, g, "Right", seat + fwd * (grip_back + reach) - left * 0.03 + up * 0.035, -left, wand_grip)

	# Legs: thighs along the shaft and splayed around it; shins hang when
	# hovering (swinging a little) and fold back toward the twigs at speed.
	var tuck := clampf(speed, 0.0, 1.0)
	for side in [1.0, -1.0]:
		var prefix := "Left" if side > 0.0 else "Right"
		var outward: Vector3 = left * side
		var swing := sin(_time * 1.9 + (0.0 if side > 0.0 else 1.9)) * 0.1 * hover
		var thigh_angle := lerpf(1.05, 1.25, tuck) + swing * 0.5
		var thigh_dir := (-up * cos(thigh_angle) + fwd * sin(thigh_angle)).normalized() + outward * 0.24 - up * 0.08
		var shin_angle := lerpf(0.1, 0.95, tuck) - swing + climb * 0.2
		var shin_dir := (-up * cos(shin_angle) - fwd * sin(shin_angle)).normalized() + outward * 0.06
		_aim(skeleton, g, prefix + "UpLeg", prefix + "Leg", thigh_dir.normalized(), 1.0)
		_aim(skeleton, g, prefix + "Leg", prefix + "Foot", shin_dir.normalized(), 1.0)
		# Toes pointed along the shin.
		_place_relative(skeleton, g, prefix + "Foot", Basis(left, lerpf(0.5, 0.9, tuck)), 1.0)


## Two-bone reach: shoulder → elbow → hand at `target`, the elbow bowed toward `outward` and down.
func _arm(skeleton: Skeleton3D, g: Dictionary, prefix: String, target: Vector3, outward: Vector3, weight: float) -> void:
	var arm: int = _bones[prefix + "Arm"]
	var shoulder_global: Transform3D = g[skeleton.get_bone_parent(arm)]
	var origin := shoulder_global * skeleton.get_bone_rest(arm).origin
	var upper := skeleton.get_bone_rest(_bones[prefix + "ForeArm"]).origin.length()
	var lower := skeleton.get_bone_rest(_bones[prefix + "Hand"]).origin.length()
	var to_target := target - origin
	var dist := clampf(to_target.length(), 0.05, (upper + lower) * 0.999)
	var dir := to_target.normalized()
	var up := _frame.basis.y
	var pole := (outward * 0.8 - up * 0.6).normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	var along := (upper * upper + dist * dist - lower * lower) / (2.0 * dist)
	var elbow := origin + dir * along + pole * sqrt(maxf(upper * upper - along * along, 0.0))
	_aim(skeleton, g, prefix + "Arm", prefix + "ForeArm", (elbow - origin).normalized(), weight)
	var hand := origin + dir * dist
	var fore_global: Transform3D = g[arm] * skeleton.get_bone_rest(_bones[prefix + "ForeArm"])
	_aim(skeleton, g, prefix + "ForeArm", prefix + "Hand", (hand - fore_global.origin).normalized(), weight)
	_place_relative(skeleton, g, prefix + "Hand", Basis.IDENTITY, weight)
