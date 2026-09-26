class_name CollectibleDefinition
extends Resource
## Data for a collectible type. Instances live in `res://resources/collectibles/`.

@export var id: StringName = &"fragment"
@export var display_name: String = "Fragment"
@export var value: int = 1
@export var color: Color = Color(0.6, 0.9, 1.0)
@export var pickup_sound: AudioStream
