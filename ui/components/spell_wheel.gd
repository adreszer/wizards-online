class_name SpellWheel
extends Control
## The gamepad's spell wheel (docs/ui.md, Milestone 72): hold the wheel button (LB),
## point a stick at a slot, let go to equip it. The slots are the hotbar's SpellSlot
## roundels in a ring, slot 1 at the top, clockwise; the stick's direction lights one
## up, and releasing with the stick centred keeps the current spell. Display and choice
## only: the pick goes to PlayerInput like a number key (spell_slot_pressed).

signal picked(index: int)

const RADIUS := 150.0
## How far the stick must lean before it points at a slot.
const DEADZONE := 0.4

var is_open := false
## The slot the stick points at, -1 for none.
var highlighted := -1
var slots: Array[SpellSlot] = []
var _name_label: Label
## Spell names per slot ("" for an empty one), filled by set_spells().
var _names: PackedStringArray = []
var _tween: Tween


func _init() -> void:
	name = "SpellWheel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_name_label = Label.new()
	_name_label.theme_type_variation = &"HudLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name_label.set_anchors_preset(Control.PRESET_CENTER)
	_name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_name_label)


func _ready() -> void:
	resized.connect(_layout)


## Builds `count` roundels (the hotbar's slot count).
func build(count: int) -> void:
	for s in slots:
		s.queue_free()
	slots.clear()
	for i in count:
		var slot := SpellSlot.new()
		slot.key_chip.key_text = str((i + 1) % 10)
		add_child(slot)
		slots.append(slot)
	_names.resize(count)
	_layout()


## Fills the roundels from the caster's quick slots (null = empty) and the equipped one.
func set_spells(defs: Array, equipped: int) -> void:
	for i in slots.size():
		var def: SpellDefinition = defs[i] if i < defs.size() else null
		slots[i].set_spell(def)
		slots[i].selected = i == equipped and def != null
		_names[i] = tr(def.display_name) if def != null else ""
	_show_name()


## The slot a stick direction points at: slot 0 straight up, the rest clockwise in
## equal sectors; -1 inside the deadzone.
static func slot_at(dir: Vector2, count: int, deadzone := DEADZONE) -> int:
	if count <= 0 or dir.length() < deadzone:
		return -1
	# Up is -y on a stick; measure clockwise from up.
	var angle := fposmod(atan2(dir.x, -dir.y), TAU)
	var sector := TAU / count
	return int(floor(fposmod(angle + sector / 2.0, TAU) / sector)) % count


## The centre of slot `i` relative to the wheel's centre.
static func slot_offset(i: int, count: int, radius := RADIUS) -> Vector2:
	var a := TAU * i / maxi(count, 1)
	return Vector2(sin(a), -cos(a)) * radius


func open() -> void:
	if is_open:
		return
	is_open = true
	highlighted = -1
	_show_name()
	UiSounds.play(&"panel_open")
	if _tween != null:
		_tween.kill()
	_tween = UiMotion.pop_in(self, UiTokens.FAST)
	UiRouter.opened(self, false)


## Closes the wheel; the highlighted slot (if it holds a spell) is picked.
func close() -> void:
	if not is_open:
		return
	is_open = false
	var choice := highlighted
	if _tween != null:
		_tween.kill()
	_tween = UiMotion.pop_out(self, UiTokens.FAST)
	UiRouter.closed(self)
	if choice >= 0 and choice < slots.size() and not slots[choice].empty:
		UiSounds.play(&"spell_select")
		picked.emit(choice)
	else:
		UiSounds.play(&"panel_close")


## Points the wheel at a stick direction (tests drive this directly).
func point(dir: Vector2) -> void:
	var i := slot_at(dir, slots.size())
	if i >= 0 and slots[i].empty:
		i = -1
	if i == highlighted:
		return
	highlighted = i
	if i >= 0:
		UiSounds.play(&"hover")
	for s in slots.size():
		UiMotion.hover(slots[s], s == highlighted)
		slots[s].scale = Vector2.ONE * (1.12 if s == highlighted else 1.0)
	_show_name()


func _process(_delta: float) -> void:
	if not is_open:
		return
	if not Input.is_action_pressed("spell_wheel"):
		close()
		return
	# Either stick points; the one leaning further wins.
	var right := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var left := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var dir := right if right.length() >= left.length() else left
	if dir.length() >= DEADZONE:
		point(dir)


func _show_name() -> void:
	var i := highlighted
	if i < 0:
		for s in slots.size():
			if slots[s].selected:
				i = s
	_name_label.text = _names[i] if i >= 0 and i < _names.size() else ""


func _layout() -> void:
	var c := size / 2.0
	for i in slots.size():
		var s := slots[i]
		s.size = s.custom_minimum_size
		s.pivot_offset = s.size / 2.0
		s.position = c + slot_offset(i, slots.size()) - s.size / 2.0
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	# A dark disc behind the ring so the roundels read over any wall.
	draw_circle(c, RADIUS + SpellSlot.SIZE * 0.75, Color(UiTokens.OAK_SOLID, 0.72), true, -1.0, true)
	draw_arc(c, RADIUS + SpellSlot.SIZE * 0.75, 0.0, TAU, 96, Color(UiTokens.BRASS, 0.8), 2.0, true)
	draw_arc(c, RADIUS * 0.45, 0.0, TAU, 64, Color(UiTokens.BRASS_DIM, 0.8), 1.5, true)
	if highlighted >= 0 and slots.size() > 0:
		var a := TAU * highlighted / slots.size() - PI / 2.0
		var half := PI / slots.size()
		draw_arc(c, RADIUS * 0.45, a - half, a + half, 24, UiTokens.BRASS_BRIGHT, 4.0, true)
