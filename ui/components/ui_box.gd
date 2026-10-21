class_name UiBox
extends RefCounted
## Boxes for screens built in code, spaced from the token scale (UiTokens.SPACE_*), so a
## screen never sets its own separation. They let the mouse through, as HUD and layout
## boxes should; a box that takes clicks sets its own mouse_filter.


static func h(separation: int = UiTokens.SPACE_2, align := BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var box := HBoxContainer.new()
	_setup(box, separation, align)
	return box


static func v(separation: int = UiTokens.SPACE_2, align := BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var box := VBoxContainer.new()
	_setup(box, separation, align)
	return box


static func _setup(box: BoxContainer, separation: int, align: BoxContainer.AlignmentMode) -> void:
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = align
	box.add_theme_constant_override("separation", separation)
