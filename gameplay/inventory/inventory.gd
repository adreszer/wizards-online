class_name Inventory
extends Node
## Player component: the items a character carries and the one it holds in its
## off hand. Pure data + signals; visuals are HeldItemMount's job and the
## authoritative copy lives on the server (Nakama storage) when online.
##
## Registers itself on the parent as meta "inventory" so level objects can do
## `interactor.get_meta("inventory")` without NodePaths.

signal changed()
signal item_added(definition: ItemDefinition, count: int)
signal item_removed(definition: ItemDefinition, count: int)
## `definition` is null when the hands are free again.
signal held_item_changed(definition: ItemDefinition)

## Slots in display order: {"def": ItemDefinition, "count": int}.
var slots: Array[Dictionary] = []
var held_item: ItemDefinition


func _ready() -> void:
	get_parent().set_meta("inventory", self)


static func find_on(node: Object) -> Inventory:
	if node != null and node.has_meta("inventory"):
		return node.get_meta("inventory") as Inventory
	return null


func is_empty() -> bool:
	return slots.is_empty()


func count_of(id: StringName) -> int:
	var total := 0
	for slot in slots:
		if (slot["def"] as ItemDefinition).id == id:
			total += int(slot["count"])
	return total


func has(id: StringName) -> bool:
	return count_of(id) > 0


func get_definition(id: StringName) -> ItemDefinition:
	for slot in slots:
		if (slot["def"] as ItemDefinition).id == id:
			return slot["def"]
	return null


## Adds `count` items, filling existing stacks first. Returns how many were added.
func add(definition: ItemDefinition, count: int = 1) -> int:
	if definition == null or count <= 0:
		return 0
	var remaining := count
	for slot in slots:
		if remaining == 0:
			break
		if slot["def"] != definition:
			continue
		var room: int = definition.max_stack - int(slot["count"])
		if room <= 0:
			continue
		var n := mini(room, remaining)
		slot["count"] = int(slot["count"]) + n
		remaining -= n
	while remaining > 0:
		var n := mini(definition.max_stack, remaining)
		slots.append({"def": definition, "count": n})
		remaining -= n
	item_added.emit(definition, count)
	changed.emit()
	return count


## Removes up to `count` items of `id`. Returns how many were removed. Removing
## the last held item frees the hands.
func remove(id: StringName, count: int = 1) -> int:
	var removed := 0
	var definition: ItemDefinition = null
	for i in range(slots.size() - 1, -1, -1):
		if removed == count:
			break
		var slot := slots[i]
		if (slot["def"] as ItemDefinition).id != id:
			continue
		definition = slot["def"]
		var n := mini(int(slot["count"]), count - removed)
		slot["count"] = int(slot["count"]) - n
		removed += n
		if int(slot["count"]) == 0:
			slots.remove_at(i)
	if removed == 0:
		return 0
	if held_item != null and held_item.id == id and not has(id):
		release_held()
	item_removed.emit(definition, removed)
	changed.emit()
	return removed


## Takes an owned, holdable item into the off hand. Returns false otherwise.
func hold(definition: ItemDefinition) -> bool:
	if definition == null or not definition.holdable or not has(definition.id):
		return false
	if held_item == definition:
		return true
	held_item = definition
	held_item_changed.emit(definition)
	changed.emit()
	return true


func hold_id(id: StringName) -> bool:
	return hold(get_definition(id))


func release_held() -> void:
	if held_item == null:
		return
	held_item = null
	held_item_changed.emit(null)
	changed.emit()


## Hold if not held, put away if held.
func toggle_hold(definition: ItemDefinition) -> void:
	if held_item == definition:
		release_held()
	else:
		hold(definition)


func held_id() -> String:
	return String(held_item.id) if held_item != null else ""


# --- Serialization (same shape as the Nakama storage object) -----------------

func to_state() -> Dictionary:
	var items: Array = []
	for slot in slots:
		items.append({"id": String((slot["def"] as ItemDefinition).id), "count": int(slot["count"])})
	return {"items": items, "held": held_id()}


## Replaces the whole inventory. Unknown item ids are dropped; the held item
## must be owned and holdable or the hands end up free.
func load_state(state: Dictionary) -> void:
	slots.clear()
	for entry in state.get("items", []):
		if not entry is Dictionary:
			continue
		var def := ItemRegistry.load_definition(str(entry.get("id", "")))
		var count := int(entry.get("count", 0))
		if def == null or count <= 0:
			continue
		var remaining := count
		while remaining > 0:
			var n := mini(def.max_stack, remaining)
			slots.append({"def": def, "count": n})
			remaining -= n
	var previous := held_item
	held_item = null
	var wanted := get_definition(StringName(str(state.get("held", ""))))
	if wanted != null and wanted.holdable:
		held_item = wanted
	if held_item != previous:
		held_item_changed.emit(held_item)
	changed.emit()
