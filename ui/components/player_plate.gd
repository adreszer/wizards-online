class_name PlayerPlate
extends HBoxContainer
## Who you are, top left of the HUD (docs/ui.md, Milestone 67): the house crest, the
## character's name, and under it the house in its colour and the school year; staff
## see their title instead of the year.

var badge: HouseBadge
var name_label: Label
var meta_label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	badge = HouseBadge.new(0, HouseBadge.Size.MEDIUM, false)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(badge)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.add_theme_constant_override("separation", -2)
	add_child(lines)
	name_label = Label.new()
	name_label.theme_type_variation = &"HudName"
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lines.add_child(name_label)
	meta_label = Label.new()
	meta_label.theme_type_variation = &"HudMeta"
	meta_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lines.add_child(meta_label)


## Fills the plate: `house` 0 for the unsorted, `year` 1–7, `role` a CharacterProfile role.
func show_player(display_name: String, house: int, year: int, role: String) -> void:
	name_label.text = display_name
	name_label.visible = display_name != ""
	badge.house = house
	var sorted := house >= 1 and house <= CharacterProfile.MAX_HOUSE
	var second := tr("YEAR_%d" % clampi(year, 1, CharacterProfile.MAX_YEAR))
	if CharacterProfile.is_staff(role):
		second = tr("HUD_ROLE_ADMIN") if role == CharacterProfile.ROLE_ADMIN else tr("HUD_ROLE_PROFESSOR")
	var first := CharacterProfile.house_name(house) if sorted else tr("PROFILE_UNSORTED")
	first = first.left(1).to_upper() + first.substr(1)
	meta_label.text = "%s · %s" % [first, second]
	if sorted:
		meta_label.add_theme_color_override("font_color", CharacterProfile.house_color(house).lightened(0.3))
	else:
		meta_label.remove_theme_color_override("font_color")
