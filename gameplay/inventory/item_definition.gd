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
## Scene shown under the rider while the item is ridden (a broom). Non-null
## makes the item a mount: the satchel and the Mount action fly on it instead
## of taking it in hand (see BroomRider).
@export var mount_scene: PackedScene
## What kind of thing it is: "tool", "decor" (hangs over a dormitory bed), "seed",
## "herb", "ingredient", "potion" (drunk for an effect), "treat", "familiar", "map".
@export var category: String = "tool"
## Price in coins at a village shop (0 = not sold) and which shop's area sells it.
@export var price: int = 0
@export var shop: String = ""
## Coins a shop pays for one (herbs at the apothecary; 0 = not bought).
@export var sell_price: int = 0
## Potions: the effect drinking one gives and for how long.
@export var effect: String = ""
@export var effect_seconds: float = 0.0


func is_stackable() -> bool:
	return max_stack > 1


func is_mount() -> bool:
	return mount_scene != null
