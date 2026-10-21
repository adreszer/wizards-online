class_name ToastStack
extends VBoxContainer
## Stacked notifications (docs/ui.md, "Components"): each toast is a small oak card with
## an icon in its kind's colour and the text; new ones join the bottom of the stack,
## each fades after a while (longer for longer text), at most MAX_SHOWN at once (the
## oldest goes first). The owner places the stack (top centre on the HUD).

enum Kind { INFO, REWARD, LEARNED, DISCOVERY, WARNING }

const ICONS := {Kind.INFO: "info", Kind.REWARD: "coins", Kind.LEARNED: "learned", Kind.DISCOVERY: "discovery", Kind.WARNING: "warning"}
const ACCENTS := {Kind.INFO: UiTokens.CANDLE_SOFT, Kind.REWARD: UiTokens.BRASS_BRIGHT, Kind.LEARNED: Color("c9b2f0"),
	Kind.DISCOVERY: UiTokens.SUCCESS, Kind.WARNING: UiTokens.DANGER}
const MAX_SHOWN := 4
const WIDTH := 440
## Seconds a toast stays, plus a little per character so long lines can be read.
const HOLD := 3.5
const HOLD_PER_CHAR := 0.035
const HOLD_MAX := 9.0


func _init() -> void:
	name = "ToastStack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", UiTokens.SPACE_2)


## How long a toast with `text` stays by default.
static func hold_for(text: String) -> float:
	return minf(HOLD + text.length() * HOLD_PER_CHAR, HOLD_MAX)


## Shows `text` (already translated); `icon_id` overrides the kind's icon. `hold` 0
## keeps the toast until it is dismissed (the gallery). Returns the toast.
func push(text: String, kind: Kind = Kind.INFO, icon_id := "", hold := -1.0) -> PanelContainer:
	while get_child_count() >= MAX_SHOWN:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var toast := PanelContainer.new()
	toast.theme_type_variation = &"Toast"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.set_meta(&"kind", kind)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.SPACE_3)
	toast.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiIcons.icon(icon_id if icon_id != "" else ICONS[kind], 28)
	icon.modulate = ACCENTS[kind]
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	add_child(toast)
	var instant: bool = GameSettings.get_value("reduce_motion")
	var stay := hold if hold >= 0.0 else hold_for(text)
	var tween := toast.create_tween()
	if not instant:
		toast.modulate.a = 0.0
		tween.tween_property(toast, "modulate:a", 1.0, UiTokens.NORMAL)
	if stay > 0.0:
		tween.tween_interval(stay)
		tween.tween_property(toast, "modulate:a", 0.0, 0.0 if instant else UiTokens.SLOW)
		tween.tween_callback(toast.queue_free)
	return toast


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
