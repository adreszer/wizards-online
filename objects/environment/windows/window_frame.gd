class_name WindowFrame
extends Node3D
## Root of a window wrapper scene (objects/environment/windows/*.tscn): the
## model fitted with its origin at the bottom centre of the frame, the frame's
## mid-depth on z = 0, and its outer outline described below so WallWindow can
## cut a matching opening into the wall. The outline is one or more pointed
## arches side by side: each has straight sides of `half_width` up to `spring`
## and two circular arcs meeting at `apex` (apex - spring == half_width gives a
## round arch); `arches` of them sit `arch_pitch` apart, centred on x = 0, and
## below the springing line the opening is one rectangle spanning them all.

@export var half_width: float = 0.42
@export var spring: float = 1.8
@export var apex: float = 2.7
@export var arches: int = 1
## Distance between neighbouring arch centres (unused for a single arch).
@export var arch_pitch: float = 0.0
## How far the stone overlaps the frame's outer edge, so its silhouette never
## shows a gap against the cut.
@export var inset: float = 0.025
## The model has open lights (no glass of its own): WallWindow fills the
## opening with a glass pane on the frame's mid-plane. Leave off for models
## that bring their own glass.
@export var glass: bool = false


## The opening cut into the wall for this window, relative to the window origin:
## Vector4(half width of one arch, bottom, spring, apex).
func opening() -> Vector4:
	return Vector4(half_width - inset, inset, spring, apex - inset)


## Vector2(arch count, arch pitch).
func layout() -> Vector2:
	return Vector2(maxi(1, arches), arch_pitch)
