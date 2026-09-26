class_name ItemDefinition
extends Resource
## Data for one kind of inventory item. Items are resources under
## `resources/items/<id>.tres`; the id doubles as the network / storage key
## (see ItemRegistry), so keep it short, lowercase and stable.

## Stable identifier, equal to the resource file name.
@export var id: StringName = &""
## Translation keys (localization/translations.csv).
@export var display_name: String = "ITEM_DEFAULT_NAME"
@export var description: String = ""
@export var icon: Texture2D
## How many of this item fit in one inventory slot.
@export_range(1, 999) var max_stack: int = 1
## True if the player can take the item into their off hand (see HeldItemMount).
@export var holdable: bool = false
## Scene instantiated in the hand while held: visuals plus, for light sources,
## the light itself. Null for holdable items with no visual yet.
@export var held_scene: PackedScene
## Seconds the item keeps working while held; 0 = never runs out. Not consumed
## by anything yet: the first torch never expires, and future consumable
## light sources will count this down server-side.
@export var burn_seconds: float = 0.0


func is_stackable() -> bool:
	return max_stack > 1
