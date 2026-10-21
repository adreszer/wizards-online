extends Control
## The UI style guide (docs/ui.md, "Technical foundation" 4): every component of the
## kit in its states, in both material families, in the current language. It is the
## design reference, the place to tune the theme and a capture target
## (tools/capture_ui.gd saves each page).
##   godot --path . levels/dev/ui_gallery.tscn [-- --page=2 --lang=en]
## Pages: windows and controls, play surfaces, icons and houses, dialogs.

const PAGES := ["GALLERY_PAGE_WINDOWS", "GALLERY_PAGE_PLAY", "GALLERY_PAGE_ICONS", "GALLERY_PAGE_DIALOGS"]
const BACKDROP_TOP := Color("2a2f2c")
const BACKDROP_BOTTOM := Color("121513")

var tabs: TabContainer
var toasts: ToastStack
var banner: AreaBanner
var _dialog: UiDialog


func _ready() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, BACKDROP_TOP)
	grad.set_color(1, BACKDROP_BOTTOM)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(0, 1)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiTokens.SPACE_4)
	add_child(margin)
	tabs = TabContainer.new()
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	margin.add_child(tabs)
	_page_windows()
	_page_play()
	_page_icons()
	_page_dialogs()
	for i in PAGES.size():
		tabs.set_tab_title(i, tr(PAGES[i]))
	tabs.tab_changed.connect(_on_tab)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--page="):
			show_page(int(arg.trim_prefix("--page=")))
		elif arg.begins_with("--lang="):
			TranslationServer.set_locale(arg.trim_prefix("--lang="))


func show_page(i: int) -> void:
	tabs.current_tab = clampi(i, 0, PAGES.size() - 1)


## Opens the sample question (page 4), or the sample failure when `error`.
func show_dialog(error := false) -> UiDialog:
	if is_instance_valid(_dialog):
		_dialog.ui_back()
	if error:
		_dialog = UiDialog.error(self, tr("GALLERY_ERROR_TITLE"), tr("GALLERY_ERROR_TEXT"))
	else:
		_dialog = UiDialog.confirm(self, tr("GALLERY_DIALOG_TITLE"), tr("GALLERY_DIALOG_TEXT"))
	return _dialog


func _on_tab(i: int) -> void:
	if i == 1:
		banner.show_area(tr("AREA_GREAT_HALL"), tr("MAP_FLOOR_GROUND"), 0.0)


# --- Page 1: windows and controls ---

func _page_windows() -> void:
	var row := HBoxContainer.new()
	row.name = "Windows"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiTokens.SPACE_6)
	tabs.add_child(row)
	for family in [UiWindow.Family.PARCHMENT, UiWindow.Family.CHROME]:
		var w := UiWindow.new(family)
		w.custom_minimum_size = Vector2(700, 0)
		w.size_flags_vertical = Control.SIZE_EXPAND_FILL
		w.title_label.text = tr("GALLERY_PARCHMENT" if family == UiWindow.Family.PARCHMENT else "GALLERY_CHROME")
		w.status_label.text = tr("GALLERY_STATUS")
		w.add_key_hint(&"pause", tr("UI_CLOSE"))
		w.add_key_hint(&"interact", tr("GALLERY_CHOOSE"))
		_controls(w.body, family == UiWindow.Family.PARCHMENT)
		row.add_child(w)


func _controls(body: VBoxContainer, paper: bool) -> void:
	body.add_theme_constant_override("separation", UiTokens.SPACE_3)
	var text := Label.new()
	text.theme_type_variation = &"BookLabel" if paper else &""
	text.text = tr("GALLERY_SAMPLE_TEXT")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(text)
	body.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UiTokens.SPACE_2)
	for state in ["normal", "pressed", "disabled"]:
		var b := Button.new()
		b.text = tr({"normal": "GALLERY_BUTTON", "pressed": "GALLERY_PRESSED", "disabled": "GALLERY_DISABLED"}[state])
		b.toggle_mode = state == "pressed"
		b.button_pressed = state == "pressed"
		b.disabled = state == "disabled"
		buttons.add_child(b)
	var opt := OptionButton.new()
	for key in ["GALLERY_OPTION_1", "GALLERY_OPTION_2"]:
		opt.add_item(tr(key))
	buttons.add_child(opt)
	body.add_child(buttons)
	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var empty := LineEdit.new()
	empty.placeholder_text = tr("GALLERY_FIELD_HINT")
	empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(empty)
	var filled := LineEdit.new()
	filled.text = tr("GALLERY_FIELD_TEXT")
	filled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(filled)
	var ro := LineEdit.new()
	ro.text = tr("GALLERY_DISABLED")
	ro.editable = false
	ro.custom_minimum_size.x = 140
	fields.add_child(ro)
	body.add_child(fields)
	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", UiTokens.SPACE_4)
	for on in [true, false]:
		var c := CheckBox.new()
		c.text = tr("GALLERY_CHECK_ON" if on else "GALLERY_CHECK_OFF")
		c.button_pressed = on
		checks.add_child(c)
	var toggle := CheckButton.new()
	toggle.text = tr("GALLERY_TOGGLE")
	toggle.button_pressed = true
	checks.add_child(toggle)
	body.add_child(checks)
	var slider := HSlider.new()
	slider.value = 60
	body.add_child(slider)
	var bar := ProgressBar.new()
	bar.value = 42
	body.add_child(bar)
	var inner := TabContainer.new()
	inner.custom_minimum_size.y = 120
	for key in ["GALLERY_TAB_1", "GALLERY_TAB_2", "GALLERY_TAB_3"]:
		var list := ItemList.new()
		list.name = key
		for i in 4:
			list.add_item(tr("GALLERY_LIST_ITEM") % (i + 1))
		list.select(1)
		inner.add_child(list)
		inner.set_tab_title(inner.get_tab_count() - 1, tr(key))
	body.add_child(inner)


# --- Page 2: play surfaces ---

func _page_play() -> void:
	var page := Control.new()
	page.name = "Play"
	tabs.add_child(page)
	banner = AreaBanner.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-300, 20)
	banner.custom_minimum_size = Vector2(600, 0)
	page.add_child(banner)
	toasts = ToastStack.new()
	toasts.position = Vector2(20, 20)
	page.add_child(toasts)
	var kinds := [ToastStack.Kind.INFO, ToastStack.Kind.REWARD, ToastStack.Kind.LEARNED, ToastStack.Kind.DISCOVERY]
	for i in kinds.size():
		toasts.push(tr("GALLERY_TOAST_%d" % (i + 1)), kinds[i], "", 0.0)
	var warn := ToastStack.new()
	warn.position = Vector2(20, 330)
	page.add_child(warn)
	warn.push(tr("GALLERY_TOAST_5"), ToastStack.Kind.WARNING, "", 0.0)

	var right := VBoxContainer.new()
	right.position = Vector2(1000, 150)
	right.add_theme_constant_override("separation", UiTokens.SPACE_4)
	page.add_child(right)
	var ribbon := PanelContainer.new()
	ribbon.theme_type_variation = &"Ribbon"
	var rl := Label.new()
	rl.theme_type_variation = &"RibbonLabel"
	rl.text = tr("GALLERY_RIBBON")
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon.add_child(rl)
	right.add_child(ribbon)
	var tip := PanelContainer.new()
	tip.theme_type_variation = &"TooltipPanel"
	tip.add_child(UiTooltip.make(tr("GALLERY_TIP_TITLE"), tr("GALLERY_TIP_TEXT"), &"interact", tr("GALLERY_TIP_VERB")))
	tip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(tip)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", UiTokens.SPACE_2)
	for action in [&"interact", &"jump", &"cast", &"map", &"journal"]:
		chips.add_child(KeyChip.new(action))
	chips.add_child(KeyChip.new(&"", "Esc"))
	right.add_child(chips)
	var loading := HBoxContainer.new()
	loading.add_theme_constant_override("separation", UiTokens.SPACE_2)
	loading.add_child(UiSpinner.new())
	var ll := Label.new()
	ll.text = tr("UI_LOADING")
	loading.add_child(ll)
	right.add_child(loading)
	var vials := VBoxContainer.new()
	vials.add_theme_constant_override("separation", UiTokens.SPACE_2)
	for spec in [[100.0, UiTokens.DANGER, 0.0], [28.0, UiTokens.DANGER, 0.3], [60.0, Color("4f7fc4"), 0.0]]:
		var v := ProgressVial.new()
		v.custom_minimum_size = Vector2(260, 18)
		v.max_value = 100.0
		v.value = spec[0]
		v.liquid = spec[1]
		v.low = spec[2]
		v.show_value = true
		vials.add_child(v)
	right.add_child(vials)
	var seps := VBoxContainer.new()
	seps.custom_minimum_size.x = 360
	seps.add_child(HSeparator.new())
	var paper := PanelContainer.new()
	paper.theme = load(UiTokens.PARCHMENT_THEME)
	paper.theme_type_variation = &"ParchmentPanel"
	var paper_box := VBoxContainer.new()
	var pl := Label.new()
	pl.text = tr("GALLERY_PAPER_NOTE")
	pl.theme_type_variation = &"BookLabel"
	paper_box.add_child(pl)
	paper_box.add_child(HSeparator.new())
	paper.add_child(paper_box)
	seps.add_child(paper)
	right.add_child(seps)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-430, -230)
	bottom.add_theme_constant_override("separation", UiTokens.SPACE_4)
	page.add_child(bottom)
	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", UiTokens.SPACE_1)
	var specs := [
		{"color": Color("e0a43c"), "icon": "spell", "mastery": 2},
		{"color": Color("6fb6e8"), "icon": "wand", "selected": true, "mastery": 3},
		{"color": Color("9d6be0"), "icon": "learned", "cooldown": 0.65, "mastery": 1},
		{"color": Color("6cc07a"), "icon": "subject_herbology", "mastery": 0},
		{"color": Color("d8584a"), "icon": "candle", "disabled": true, "mastery": 0},
		{}, {}, {}, {}, {},
	]
	for i in specs.size():
		var slot := SpellSlot.new()
		var s: Dictionary = specs[i]
		slot.empty = s.is_empty()
		if not s.is_empty():
			slot.spell_color = s["color"]
			slot.icon_id = s["icon"]
			slot.selected = s.get("selected", false)
			slot.cooldown = s.get("cooldown", 0.0)
			slot.disabled = s.get("disabled", false)
			slot.mastery_max = 3
			slot.mastery = s["mastery"]
		slot.key_chip.key_text = str((i + 1) % 10)
		hotbar.add_child(slot)
	bottom.add_child(hotbar)
	var items := HBoxContainer.new()
	items.add_theme_constant_override("separation", UiTokens.SPACE_1)
	for spec in [["lantern", 1, false], ["book", 3, true], ["cauldron", 1, false], ["coins", 25, false], ["", 0, false], ["", 0, false]]:
		var it := ItemSlot.new()
		it.set_item(spec[0], spec[1])
		it.selected = spec[2]
		items.add_child(it)
	bottom.add_child(items)


# --- Page 3: icons and houses ---

func _page_icons() -> void:
	var page := HBoxContainer.new()
	page.name = "Icons"
	page.add_theme_constant_override("separation", UiTokens.SPACE_5)
	tabs.add_child(page)
	var houses := PanelContainer.new()
	houses.theme_type_variation = &"ChromePanel"
	houses.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", UiTokens.SPACE_3)
	houses.add_child(hv)
	for size in [HouseBadge.Size.LARGE, HouseBadge.Size.MEDIUM, HouseBadge.Size.SMALL]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTokens.SPACE_4)
		for h in ([1, 2] if size == HouseBadge.Size.LARGE else [1, 2, 3, 4, 0]):
			row.add_child(HouseBadge.new(h, size))
		hv.add_child(row)
		if size == HouseBadge.Size.LARGE:
			var row2 := HBoxContainer.new()
			row2.add_theme_constant_override("separation", UiTokens.SPACE_4)
			for h in [3, 4]:
				row2.add_child(HouseBadge.new(h, size))
			hv.add_child(row2)
	page.add_child(houses)
	var grids := VBoxContainer.new()
	grids.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grids.add_theme_constant_override("separation", UiTokens.SPACE_3)
	page.add_child(grids)
	for paper in [false, true]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"ParchmentPanel" if paper else &"ChromePanel"
		if paper:
			panel.theme = load(UiTokens.PARCHMENT_THEME)
		var grid := GridContainer.new()
		grid.columns = 12
		grid.add_theme_constant_override("h_separation", UiTokens.SPACE_2)
		grid.add_theme_constant_override("v_separation", UiTokens.SPACE_2)
		for id in UiIcons.ids():
			var t := TextureRect.new()
			t.texture = UiIcons.icon(id, 36)
			t.modulate = UiTokens.INK if paper else UiTokens.BRASS
			t.tooltip_text = id
			t.custom_minimum_size = Vector2(40, 40)
			t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			grid.add_child(t)
		panel.add_child(grid)
		grids.add_child(panel)


# --- Page 4: dialogs ---

func _page_dialogs() -> void:
	var page := CenterContainer.new()
	page.name = "Dialogs"
	tabs.add_child(page)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	for error in [false, true]:
		var b := Button.new()
		b.text = tr("GALLERY_SHOW_ERROR" if error else "GALLERY_SHOW_QUESTION")
		b.pressed.connect(show_dialog.bind(error))
		row.add_child(b)
	page.add_child(row)
