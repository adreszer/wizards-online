class_name DecorPanel
extends FeaturePanel
## Choosing what hangs over your dormitory bed: every decor item you own, up to three
## ticked (GameEvents.panel_requested("decor")). The server checks you own them.

const MAX := 3
var _list: VBoxContainer
var _boxes: Dictionary = {}


func _ready() -> void:
	half_size = Vector2(260, 220)
	super()
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "decor":
			open_panel())


func _build() -> void:
	title_label.text = tr("DECOR_TITLE")
	body.add_child(label(tr("DECOR_HINT"), 14))
	_list = VBoxContainer.new()
	body.add_child(_list)
	body.add_child(button(tr("DECOR_SAVE"), save))


func refresh() -> void:
	clear(_list)
	_boxes.clear()
	var current := mine()
	for id in owned_decor():
		var box := CheckBox.new()
		var def := ItemRegistry.load_definition(id)
		box.text = tr(def.display_name) if def != null else id
		box.button_pressed = current.has(id)
		box.add_theme_color_override("font_color", INK)
		_list.add_child(box)
		_boxes[id] = box
	if _boxes.is_empty():
		_list.add_child(label(tr("DECOR_NONE"), 14))


## Decor items in the local inventory.
static func owned_decor() -> Array[String]:
	var out: Array[String] = []
	var items: Variant = NetworkManager.get_local_inventory().get("items", [])
	for e: Variant in (items if items is Array else []):
		var def := ItemRegistry.load_definition(str((e as Dictionary).get("id", "")))
		if def != null and def.category == "decor":
			out.append(str(def.id))
	return out


## What hangs over my bed now.
static func mine() -> Array:
	var houses: Variant = NetworkManager.feature("dorm").get("houses", {})
	var beds: Variant = (houses as Dictionary).get(str(NetworkManager.get_local_house()), {}) if houses is Dictionary else {}
	for n: String in (beds if beds is Dictionary else {}):
		var e: Dictionary = beds[n]
		if str(e.get("name", "")) == NetworkManager.local_display_name:
			return e.get("decor", []) if e.get("decor", []) is Array else []
	return []


func save() -> void:
	var picked: Array = []
	for id: String in _boxes:
		if (_boxes[id] as CheckBox).button_pressed:
			picked.append(id)
	if picked.size() > MAX:
		status_label.text = tr("DECOR_TOO_MANY") % MAX
		return
	var r: Dictionary = await NetworkManager.request("dorm_decorate", {"decor": picked})
	show_result(r, "DECOR_SAVED")
