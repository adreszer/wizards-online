class_name SocialPose
extends PoseModifier
## Procedural social gestures layered over the animation: raise a hand, wave, bow,
## clap, point, shrug, cheer, take notes, and sit on a bench or chair. The rigs ship
## no clips for these, so this modifier writes the pose after the AnimationTree runs;
## Gestures (the player component) picks [member gesture] and ramps [member influence]
## in and out. Only the bones a gesture needs are written: the rest (legs while
## waving, arms while bowing) keep playing the idle animation.
##
## Directions are in skeleton space: the Mixamo rest faces +Z with +Y up and +X to
## the character's left.

const FWD := Vector3(0, 0, 1)
const UP := Vector3(0, 1, 0)
const LEFT := Vector3(1, 0, 0)
const RIGHT := Vector3(-1, 0, 0)

## The gesture being shown (Gestures.IDS, or eat); empty = none.
var gesture: StringName = &""
## Sitting: legs and hips on the seat; an arm gesture plays on top.
var seated := false
## Seconds since the gesture started (one-shot gestures time their motion by it).
var elapsed: float = 0.0
## Sitting: the seat's surface in world height; the hips settle just above it.
var seat_world_y: float = 0.0

var _time: float = 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or (gesture == &"" and not seated) or not _resolve(skeleton):
		return
	_time += delta
	elapsed += delta
	var g := {}
	for name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder"]:
		g[_bones[name]] = skeleton.get_bone_global_pose(_bones[name])
	if seated:
		_sit(skeleton, g, gesture == &"")
	match gesture:
		&"eat":
			# Spoon to mouth every couple of seconds, resting on the table between.
			var lift := smoothstep(0.0, 0.35, fposmod(_time, 2.2)) * (1.0 - smoothstep(0.9, 1.3, fposmod(_time, 2.2)))
			_reach(skeleton, g, "Right", (-UP * 0.5 + FWD * 0.75 + RIGHT * 0.25).lerp(-UP * 0.7 + FWD * 0.35 + RIGHT * 0.3, lift).normalized(),
				(FWD * 0.9 - UP * 0.2).lerp(UP * 0.85 + FWD * 0.2 + LEFT * 0.35, lift).normalized())
			_reach(skeleton, g, "Left", (-UP * 0.5 + FWD * 0.75 + LEFT * 0.25).normalized(), (FWD * 0.95 + RIGHT * 0.2 - UP * 0.15).normalized())
		&"raise_hand":
			var sway := sin(_time * 1.3) * 0.04
			_reach(skeleton, g, "Right", (UP + RIGHT * (0.18 + sway) + FWD * 0.12).normalized(), (UP + FWD * 0.04).normalized())
		&"wave":
			var swing := sin(elapsed * 9.0) * 0.5
			_reach(skeleton, g, "Right", (UP * 0.7 + RIGHT * 0.62 + FWD * 0.2).normalized(),
				(Basis(FWD, swing) * (UP * 0.95 + RIGHT * 0.1)).normalized())
		&"point":
			var aim := (FWD + UP * 0.1 + RIGHT * 0.1).normalized()
			_reach(skeleton, g, "Right", aim, aim)
		&"cheer":
			var bounce := absf(sin(elapsed * 6.0)) * 0.25
			_reach(skeleton, g, "Right", (UP + RIGHT * 0.35).normalized(), (UP + RIGHT * (0.1 + bounce)).normalized())
			_reach(skeleton, g, "Left", (UP + LEFT * 0.35).normalized(), (UP + LEFT * (0.1 + bounce)).normalized())
		&"clap":
			var beat := 0.5 + 0.5 * sin(elapsed * 13.0)
			for side in [1.0, -1.0]:
				var out: Vector3 = LEFT * side
				_reach(skeleton, g, "Left" if side > 0.0 else "Right", (FWD * 0.75 - UP * 0.45 + out * 0.3).normalized(),
					(FWD * 0.55 + UP * 0.35 - out * (0.45 + 0.35 * beat)).normalized())
		&"shrug":
			var lift := sin(clampf(elapsed / 0.5, 0.0, 1.0) * PI * 0.5)
			_place_relative(skeleton, g, "LeftShoulder", Basis(FWD, 0.28 * lift), 1.0)
			_place_relative(skeleton, g, "RightShoulder", Basis(FWD, -0.28 * lift), 1.0)
			_reach(skeleton, g, "Left", (-UP * 0.85 + LEFT * 0.4).normalized(), (FWD * 0.7 + LEFT * 0.6 + UP * 0.15).normalized())
			_reach(skeleton, g, "Right", (-UP * 0.85 + RIGHT * 0.4).normalized(), (FWD * 0.7 + RIGHT * 0.6 + UP * 0.15).normalized())
			_turn_head(skeleton, g, Basis(FWD, 0.15 * lift))
		&"bow":
			# Down in half a second, a moment held, then back up.
			var t := elapsed
			var depth := smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(1.1, 1.7, t))
			_place_relative(skeleton, g, "Spine", Basis(LEFT, 0.32 * depth), 1.0)
			_place_relative(skeleton, g, "Spine1", Basis(LEFT, 0.3 * depth), 1.0)
			_place_relative(skeleton, g, "Spine2", Basis(LEFT, 0.22 * depth), 1.0)
		&"nod":
			# Portraits only: two slow nods.
			var dip := sin(clampf(elapsed / 1.4, 0.0, 1.0) * TAU) * 0.5 + 0.5
			_turn_head(skeleton, g, Basis(LEFT, 0.22 * (1.0 - dip) * smoothstep(0.0, 0.2, elapsed)))
		&"salute":
			# Portraits only: the right hand up to the brow, held, then down.
			var up := smoothstep(0.0, 0.4, elapsed) * (1.0 - smoothstep(1.5, 1.9, elapsed))
			_reach(skeleton, g, "Right", (-UP).lerp(RIGHT * 0.75 + UP * 0.2 + FWD * 0.35, up).normalized(),
				(-UP * 0.3 + FWD * 0.5).lerp(LEFT * 0.8 + UP * 0.45 + FWD * 0.2, up).normalized())
		&"notes":
			var scribble := sin(_time * 11.0) * 0.06
			_turn_head(skeleton, g, Basis(LEFT, 0.38))
			_reach(skeleton, g, "Left", (-UP * 0.55 + FWD * 0.7 + LEFT * 0.2).normalized(), (FWD * 0.8 + RIGHT * 0.45 + UP * 0.1).normalized())
			_reach(skeleton, g, "Right", (-UP * 0.6 + FWD * 0.7 + RIGHT * 0.2).normalized(), (FWD * 0.85 + LEFT * (0.35 + scribble) - UP * 0.05).normalized())


## Points one arm: the upper arm along `upper_dir`, the forearm along `fore_dir`.
func _reach(skeleton: Skeleton3D, g: Dictionary, side: String, upper_dir: Vector3, fore_dir: Vector3) -> void:
	_aim(skeleton, g, side + "Arm", side + "ForeArm", upper_dir, 1.0)
	_aim(skeleton, g, side + "ForeArm", side + "Hand", fore_dir, 1.0)
	_place_relative(skeleton, g, side + "Hand", Basis.IDENTITY, 1.0)


func _turn_head(skeleton: Skeleton3D, g: Dictionary, turn: Basis) -> void:
	_place_relative(skeleton, g, "Head", turn, 1.0)


## Hips lowered onto the seat and pushed back a little; thighs forward along the seat,
## shins hanging to the floor, back straight; with `rest_hands`, hands on the knees.
func _sit(skeleton: Skeleton3D, g: Dictionary, rest_hands: bool) -> void:
	var hips: int = _bones["Hips"]
	var animated := skeleton.get_bone_global_pose(hips)
	var to_world := skeleton.global_transform
	var hips_world := to_world * animated.origin
	var back_world := (to_world.basis * -FWD).normalized() * 0.14
	var target_world := Vector3(hips_world.x, seat_world_y + 0.09, hips_world.z) + back_world
	var target := to_world.affine_inverse() * target_world
	var rest := skeleton.get_bone_global_rest(hips)
	var basis := rest.basis
	skeleton.set_bone_pose_rotation(hips, basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(hips, target)
	g[hips] = Transform3D(basis, target)
	_place(skeleton, g, "Spine", Basis(LEFT, 0.05))
	_place(skeleton, g, "Spine1", Basis(LEFT, 0.06))
	_place(skeleton, g, "Spine2", Basis(LEFT, 0.04))
	for side in [1.0, -1.0]:
		var prefix := "Left" if side > 0.0 else "Right"
		var out: Vector3 = LEFT * side
		_aim(skeleton, g, prefix + "UpLeg", prefix + "Leg", (FWD + out * 0.1 - UP * 0.04).normalized(), 1.0)
		_aim(skeleton, g, prefix + "Leg", prefix + "Foot", (-UP + FWD * 0.1).normalized(), 1.0)
		_place_relative(skeleton, g, prefix + "Foot", Basis.IDENTITY, 1.0)
	_place_relative(skeleton, g, "LeftShoulder", Basis.IDENTITY, 1.0)
	_place_relative(skeleton, g, "RightShoulder", Basis.IDENTITY, 1.0)
	_place_relative(skeleton, g, "Neck", Basis.IDENTITY, 1.0)
	if not rest_hands:
		return
	_reach(skeleton, g, "Left", (-UP * 0.75 + FWD * 0.6 + LEFT * 0.1).normalized(), (FWD + RIGHT * 0.15 - UP * 0.25).normalized())
	_reach(skeleton, g, "Right", (-UP * 0.75 + FWD * 0.6 + RIGHT * 0.1).normalized(), (FWD + LEFT * 0.15 - UP * 0.25).normalized())
