class_name AreaBanner
extends VBoxContainer
## The big title shown on entering a named area (docs/ui.md, "Components"): the area in
## the display face, a brass rule and a small line under it (the floor, the lesson),
## fading in, holding HOLD seconds and fading out. The owner places it (upper middle of
## the HUD).

const HOLD := 2.5

var title_label: Label
var subtitle_label: Label
var _tween: Tween


func _init() -> void:
	name = "AreaBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 0)
	title_label = Label.new()
	title_label.theme_type_variation = &"BannerLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(title_label)
	var rule := HSeparator.new()
	rule.custom_minimum_size.x = 360
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(rule)
	subtitle_label = Label.new()
	subtitle_label.theme_type_variation = &"BannerSubLabel"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(subtitle_label)
	modulate.a = 0.0


## Shows `title` (translated) with `subtitle` under it; `hold` 0 keeps it up.
func show_area(title: String, subtitle := "", hold := HOLD) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	if _tween != null:
		_tween.kill()
	var instant: bool = GameSettings.get_value("reduce_motion")
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.0 if instant else UiTokens.SLOW)
	if hold > 0.0:
		_tween.tween_interval(hold)
		_tween.tween_property(self, "modulate:a", 0.0, 0.0 if instant else UiTokens.SLOW * 2.0)


func is_showing() -> bool:
	return modulate.a > 0.0
