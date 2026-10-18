class_name ShopPanel
extends FeaturePanel
## A village shop's counter (server feature "shops"): what it sells and for how much,
## what it buys from you (herbs at the apothecary), and your purse. Opened at the
## counter (GameEvents.panel_requested("shop", {shop})).

var shop := ""
var _list: VBoxContainer
var _purse: Label


func _ready() -> void:
	half_size = Vector2(320, 240)
	super()
	GameEvents.panel_requested.connect(func(panel: String, args: Dictionary) -> void:
		if panel == "shop":
			shop = str(args.get("shop", ""))
			open_panel())
	NetworkManager.wallet_changed.connect(func(_c: int, _d: int, _s: String, _x: String) -> void:
		if is_open:
			refresh())


func _build() -> void:
	_purse = label("", 15)
	body.add_child(_purse)
	_list = VBoxContainer.new()
	body.add_child(_list)


func refresh() -> void:
	title_label.text = tr("AREA_" + shop.to_upper())
	_purse.text = tr("SHOP_PURSE") % NetworkManager.get_coins()
	clear(_list)
	var f := NetworkManager.feature("shops")
	if not f.get("open", true):
		_list.add_child(label(tr("SHOP_CLOSED"), 14))
	for e: Variant in _of(f.get("shops", {}), shop):
		var d: Dictionary = e
		var id := str(d.get("id", ""))
		var def := ItemRegistry.load_definition(id)
		var row := HBoxContainer.new()
		var l := label("%s — %d" % [tr(def.display_name) if def != null else id, int(d.get("price", 0))], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = tr(def.description) if def != null else ""
		row.add_child(l)
		row.add_child(button(tr("SHOP_BUY"), func() -> void: show_result(await NetworkManager.request("shop_buy", {"item": id}), "SHOP_BOUGHT")))
		_list.add_child(row)
	for e: Variant in _of(f.get("buys", {}), shop):
		var d: Dictionary = e
		var id := str(d.get("id", ""))
		var def := ItemRegistry.load_definition(id)
		var row := HBoxContainer.new()
		var l := label(tr("SHOP_WE_BUY") % [tr(def.display_name) if def != null else id, int(d.get("price", 0))], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(button(tr("SHOP_SELL"), func() -> void: show_result(await NetworkManager.request("shop_sell", {"item": id}), "SHOP_SOLD")))
		_list.add_child(row)


static func _of(by_shop: Variant, s: String) -> Array:
	var list: Variant = (by_shop as Dictionary).get(s, []) if by_shop is Dictionary else []
	return list if list is Array else []
