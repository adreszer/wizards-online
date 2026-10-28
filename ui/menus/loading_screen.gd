class_name LoadingScreen
extends CanvasLayer
## Between the menu and the castle (docs/ui.md, Milestone 68): the dusk backdrop, a
## parchment lore card (LORE_n), a tip (LOADING_TIP_n) and the spinner, over everything
## while the world builds; finish() fades it out and frees it. The world is built in one
## blocking step, so the screen is drawn before it starts.

const LORE_COUNT := 6
const TIP_COUNT := 8

var lore_title: Label
var lore_text: Label
var tip_label: Label
var _root: Control


func _init(seed_value := -1) -> void:
	name = "LoadingScreen"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(MenuBackdrop.new())
	# Bottom left: a lore card on parchment.
	var card := PanelContainer.new()
	card.theme = load(UiTokens.PARCHMENT_THEME)
	card.theme_type_variation = &"ParchmentPanel"
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = 96
	card.offset_bottom = -72
	card.custom_minimum_size.x = 520
	_root.add_child(card)
	var lines := UiBox.v(UiTokens.SPACE_2)
	card.add_child(lines)
	var n := rng.randi_range(1, LORE_COUNT)
	lore_title = Label.new()
	lore_title.text = "LORE_%d_TITLE" % n
	lore_title.theme_type_variation = &"TitleLabel"
	lines.add_child(lore_title)
	lore_text = Label.new()
	lore_text.text = "LORE_%d_TEXT" % n
	lore_text.theme_type_variation = &"BookLabel"
	lore_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(lore_text)
	# Bottom right: the spinner, what is happening and a tip.
	var side := UiBox.v(UiTokens.SPACE_2)
	side.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side.offset_right = -96
	side.offset_bottom = -72
	side.custom_minimum_size.x = 420
	_root.add_child(side)
	var status := UiBox.h(UiTokens.SPACE_3, BoxContainer.ALIGNMENT_END)
	side.add_child(status)
	var loading := Label.new()
	loading.text = "LOADING_TEXT"
	loading.theme_type_variation = &"HudPlace"
	status.add_child(loading)
	status.add_child(UiSpinner.new())
	tip_label = Label.new()
	tip_label.text = tr("LOADING_TIP") + ": " + tr("LOADING_TIP_%d" % rng.randi_range(1, TIP_COUNT))
	tip_label.theme_type_variation = &"HudMeta"
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	side.add_child(tip_label)


## Fades out (instantly under reduced motion) and frees itself.
func finish() -> void:
	var tween := UiMotion.fade(_root, 0.0, UiTokens.SLOW) if is_inside_tree() else null
	if tween == null:
		queue_free()
		return
	tween.chain().tween_callback(queue_free)
