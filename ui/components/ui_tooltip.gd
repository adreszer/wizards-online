class_name UiTooltip
extends VBoxContainer
## A rich tooltip (docs/ui.md, "Components"): a title, a body and an optional key hint
## ("[E] use"), drawn inside the theme's TooltipPanel. A control shows one by returning
## UiTooltip.from_text(for_text) from _make_custom_tooltip; its tooltip_text is the
## title, then a new line and the body.

const WIDTH := 300


static func make(title: String, body := "", action: StringName = &"", verb := "") -> UiTooltip:
	var t := UiTooltip.new()
	t.add_theme_constant_override("separation", UiTokens.SPACE_1)
	var head := Label.new()
	head.text = title
	head.add_theme_font_override("font", load(UiFonts.UI_BOLD))
	head.add_theme_color_override("font_color", UiTokens.BRASS_BRIGHT)
	t.add_child(head)
	if body != "":
		var text := Label.new()
		text.text = body
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = WIDTH
		text.add_theme_font_size_override("font_size", UiTokens.SIZE_HINT)
		t.add_child(text)
	if action != &"":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTokens.SPACE_2)
		row.add_child(KeyChip.new(action))
		var hint := Label.new()
		hint.text = verb
		hint.theme_type_variation = &"HintLabel"
		row.add_child(hint)
		t.add_child(row)
	return t


## Fades in over FAST like every other surface (at once under reduced motion).
func _ready() -> void:
	if not UiMotion.reduced():
		modulate.a = 0.0
		UiMotion.fade(self, 1.0, UiTokens.FAST)


## Splits "Title\nBody" (translating each part) into a tooltip.
static func from_text(for_text: String) -> UiTooltip:
	var parts := for_text.split("\n", true, 1)
	var body: String = TranslationServer.translate(parts[1]) if parts.size() > 1 else ""
	return make(TranslationServer.translate(parts[0]), body)
