class_name LightQuality
extends RefCounted
## The light budget. Every omni and spot light in the world fades out with distance
## (so the castle's ~700 placed lights never all reach the renderer at once), and only
## lights near the camera render shadows, out to a distance set by the graphics preset.
## A shadowed light re-renders its shadow whenever something that casts a shadow moves
## within its range, so the shadow distance is what bounds the shadow cost; geometry that
## animates every frame (bobbing tomes, floating candles…) should not cast shadows, and
## particles never do (watch() turns their shadows off as they enter the tree).
## GameSettings.apply() installs it (watch) and re-applies it when settings change.

## Lights farther than this from the camera start to fade…
const FADE_BEGIN := 45.0
## …and are gone this much farther. Shadows fade over the same length.
const FADE_LENGTH := 10.0
## How far (m) light shadows reach per preset, fade included; 0 = no light shadows
## (sun and moon shadows apart).
const SHADOW_DISTANCE := {"low": 0.0, "medium": 12.0, "high": 20.0, "ultra": 30.0}
## Meta on a light: whether it was authored with a shadow (the settings can only take it away).
const META_SHADOW := &"authored_shadow"

static var shadow_distance := 20.0
static var _watched: SceneTree


## Configures every light already in `tree` and every light added later.
static func watch(tree: SceneTree) -> void:
	if _watched != tree:
		_watched = tree
		tree.node_added.connect(_on_node_added)
	for node in tree.root.find_children("*", "Node3D", true, false):
		_on_node_added(node)


## Applies the fade and the shadow distance to one light (directional lights are left alone).
static func configure(light: Light3D) -> void:
	if light is DirectionalLight3D:
		return
	if not light.has_meta(META_SHADOW):
		light.set_meta(META_SHADOW, light.shadow_enabled)
	light.distance_fade_enabled = true
	light.distance_fade_begin = FADE_BEGIN
	light.distance_fade_length = FADE_LENGTH
	var shadowed: bool = light.get_meta(META_SHADOW) and shadow_distance > 0.0
	light.shadow_enabled = shadowed
	# Godot renders a shadow out to distance_fade_shadow + the fade length.
	light.distance_fade_shadow = clampf(shadow_distance - FADE_LENGTH, 0.0, FADE_BEGIN)


## Shadow distance for the current settings: the preset's, or none with shadows off.
static func distance_for(preset: String, shadows: bool) -> float:
	return float(SHADOW_DISTANCE.get(preset, SHADOW_DISTANCE["high"])) if shadows else 0.0


static func _on_node_added(node: Node) -> void:
	if node is Light3D:
		configure(node as Light3D)
	elif node is GPUParticles3D or node is CPUParticles3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
