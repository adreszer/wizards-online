class_name CauldronPanel
extends FeaturePanel
## A cauldron in the Potions classroom (server feature "brew"): add what you carry,
## stir, set the heat, wait, and bottle; the recipe book lists what the school brews.
## Potions you carry can be drunk from here too. Opened from the cauldron (Interact).
## The pot bubbles while the panel is open; adding pours, bottling fizzes or burps.

const BUBBLING := preload("res://assets/audio/school/cauldron_bubble_loop.wav")

var _steps: Label
var _ingredients: HBoxContainer
var _drinks: HBoxContainer
var _book: RichTextLabel
var _bubbling: AudioStreamPlayer


func _ready() -> void:
	half_size = Vector2(380, 270)
	super()
	_bubbling = AudioStreamPlayer.new()
	_bubbling.name = "Bubbling"
	_bubbling.stream = Sfx.looped(BUBBLING)
	_bubbling.bus = &"UI"
	_bubbling.volume_db = -10.0
	add_child(_bubbling)
	GameEvents.panel_requested.connect(func(panel: String, _args: Dictionary) -> void:
		if panel == "cauldron":
			open_panel())
	NetworkManager.pushed.connect(func(kind: String, _d: Dictionary) -> void:
		if kind == "brew" and is_open:
			refresh())
	NetworkManager.inventory_received.connect(func(_s: Dictionary) -> void:
		if is_open:
			refresh())


func _build() -> void:
	title_label.text = tr("CAULDRON_TITLE")
	_steps = label("", 15)
	body.add_child(_steps)
	_ingredients = HBoxContainer.new()
	body.add_child(_ingredients)
	var row := HBoxContainer.new()
	row.add_child(button(tr("CAULDRON_STIR"), func() -> void: _ask("brew_stir", {})))
	row.add_child(button(tr("CAULDRON_HEAT_LOW"), func() -> void: _ask("brew_heat", {"level": "low"})))
	row.add_child(button(tr("CAULDRON_HEAT_HIGH"), func() -> void: _ask("brew_heat", {"level": "high"})))
	row.add_child(button(tr("CAULDRON_BOTTLE"), _bottle))
	row.add_child(button(tr("CAULDRON_EMPTY"), func() -> void: _ask("brew_empty", {})))
	body.add_child(row)
	_drinks = HBoxContainer.new()
	body.add_child(_drinks)
	_book = RichTextLabel.new()
	_book.bbcode_enabled = true
	_book.fit_content = true
	body.add_child(_book)


func refresh() -> void:
	_steps.text = steps_text(NetworkManager.feature("brew").get("steps", []))
	clear(_ingredients)
	clear(_drinks)
	for e: Variant in _items():
		var id := str((e as Dictionary).get("id", ""))
		var def := ItemRegistry.load_definition(id)
		if def == null:
			continue
		if def.category == "herb" or def.category == "ingredient":
			_ingredients.add_child(button("%s ×%d" % [tr(def.display_name), int((e as Dictionary).get("count", 1))], func() -> void: _ask("brew_add", {"item": id})))
		elif def.category == "potion":
			_drinks.add_child(button(tr("CAULDRON_DRINK") % tr(def.display_name), func() -> void: _ask("potion_drink", {"item": id})))
	if _ingredients.get_child_count() == 0:
		_ingredients.add_child(label(tr("CAULDRON_NO_INGREDIENTS"), 13))
	_book.text = book_bbcode(NetworkManager.feature("recipes").get("recipes", {}))


static func _items() -> Array:
	var items: Variant = NetworkManager.get_local_inventory().get("items", [])
	return items if items is Array else []


static func steps_text(steps: Variant) -> String:
	var parts := PackedStringArray()
	for s: Variant in (steps if steps is Array else []):
		parts.append(step_text(s))
	return TranslationServer.translate("CAULDRON_STEPS") % (" → ".join(parts) if not parts.is_empty() else TranslationServer.translate("CAULDRON_EMPTY_POT"))


static func step_text(s: Variant) -> String:
	var d: Dictionary = s if s is Dictionary else {}
	if d.has("add"):
		var def := ItemRegistry.load_definition(str(d.add))
		return TranslationServer.translate(def.display_name) if def != null else str(d.add)
	if d.has("stir"):
		return TranslationServer.translate("CAULDRON_STIR_N") % int(d.stir)
	if d.has("heat"):
		return TranslationServer.translate("CAULDRON_HEAT_HIGH" if str(d.heat) == "high" else "CAULDRON_HEAT_LOW")
	return "?"


## The recipe book: each potion with its steps and wait.
static func book_bbcode(recipes: Variant) -> String:
	var out := PackedStringArray(["[b]%s[/b]" % TranslationServer.translate("CAULDRON_BOOK")])
	if not recipes is Dictionary:
		return ""
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		var parts := PackedStringArray()
		for s: Variant in (r.get("steps", []) if r.get("steps", []) is Array else []):
			parts.append(step_text(s))
		var def := ItemRegistry.load_definition(id)
		out.append("%s: %s → %s" % [TranslationServer.translate(def.display_name) if def != null else id, " → ".join(parts),
			TranslationServer.translate("CAULDRON_WAIT") % int(r.get("wait", 0))])
	return "\n".join(out)


func _bottle() -> void:
	var r: Dictionary = await NetworkManager.request("brew_bottle", {})
	if not r.ok:
		show_result(r)
		return
	var potion := str(r.data.get("potion", ""))
	UiSounds.play(&"potion_brew_fail" if potion == "" else &"potion_brew_success")
	if potion == "":
		status_label.text = tr("CAULDRON_SLUDGE")
	else:
		var def := ItemRegistry.load_definition(potion)
		status_label.text = tr("CAULDRON_BREWED") % [tr(def.display_name) if def != null else potion, int(r.data.get("quality", 0))]


func _ask(kind: String, payload: Dictionary) -> void:
	var r: Dictionary = await NetworkManager.request(kind, payload)
	if not r.ok:
		show_result(r)
	elif kind == "brew_add":
		UiSounds.play(&"potion_pour")
	elif kind == "potion_drink":
		close()


func open_panel() -> void:
	super()
	if is_open:
		_bubbling.play()


func close() -> void:
	_bubbling.stop()
	super()
