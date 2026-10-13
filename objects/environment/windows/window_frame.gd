class_name WindowFrame
extends Node3D
## Root of a window wrapper scene (objects/environment/windows/*.tscn): the
## model fitted with its origin at the bottom centre of the frame, the frame's
## mid-depth on z = 0, and its outer outline described below so WallWindow can
## cut a matching opening into the wall. The outline is a pointed arch: straight
## sides of `half_width` up to `spring`, two circular arcs meeting at `apex`
## (apex - spring == half_width gives a round arch).

@export var half_width: float = 0.42
@export var spring: float = 1.8
@export var apex: float = 2.7
## How far the stone overlaps the frame's outer edge, so its silhouette never
## shows a gap against the cut.
@export var inset: float = 0.025


## The opening cut into the wall for this window, relative to the window origin:
## Vector4(half width, bottom, spring, apex).
func opening() -> Vector4:
	return Vector4(half_width - inset, inset, spring, apex - inset)
