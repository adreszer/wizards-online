class_name ItemSlot
extends PanelContainer
## A satchel square (docs/ui.md, "Components"): an inset slot with brass corners, the
## item's icon, a count in the corner and a selected state.

const SIZE := 60
const ICON := 36

var icon_rect: TextureRect
var count_label: Label
var selected := false:
	set(value):
		selected = value
		theme_type_variation = &"ItemSlotSelected" if selected else &"ItemSlot"
		icon_rect.modulate = UiTokens.BRASS_BRIGHT if selected else UiTokens.CANDLE


func _init() -> void:
	theme_type_variation = &"ItemSlot"
	custom_minimum_size = Vector2(SIZE, SIZE)
	icon_rect = TextureRect.new()
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.modulate = UiTokens.CANDLE
	add_child(icon_rect)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	count_label.add_theme_font_size_override("font_size", UiTokens.SIZE_SMALL)
	count_label.add_theme_color_override("font_outline_color", UiTokens.OAK_SOLID)
	count_label.add_theme_constant_override("outline_size", 4)
	add_child(count_label)


## Shows an item: an icon id from UiIcons (or "" for an empty slot) and how many; a
## count of 1 or less shows no number.
func set_item(icon_id: String, count := 1) -> void:
	icon_rect.texture = UiIcons.icon(icon_id, ICON) if icon_id != "" else null
	count_label.text = str(count) if count > 1 else ""


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltip.from_text(for_text)
