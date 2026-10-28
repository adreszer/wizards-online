class_name UiMotion
extends RefCounted
## The one motion vocabulary of the interface (docs/ui.md, Milestone 72): every window,
## panel, toast, tooltip and hover uses these durations (UiTokens.FAST / NORMAL / SLOW)
## and easings (UiTokens.TRANS, EASE_OPEN, EASE_CLOSE). Under reduced motion
## (GameSettings "reduce_motion") every change is instant. Tweens keep running while the
## game is paused (the pause menu is a window too).


static func reduced() -> bool:
	return bool(GameSettings.get_value("reduce_motion"))


## `d` seconds, or 0 under reduced motion.
static func seconds(d: float) -> float:
	return 0.0 if reduced() else d


## A tween on `node` with the shared easing; `closing` eases in instead of out.
static func tween(node: Node, closing := false, parallel := true) -> Tween:
	var t := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(UiTokens.TRANS)
	t.set_ease(UiTokens.EASE_CLOSE if closing else UiTokens.EASE_OPEN)
	if parallel:
		t.set_parallel()
	return t


## Fades `item` to `alpha` over `d`; instant (and null) under reduced motion or off-tree.
static func fade(item: CanvasItem, alpha: float, d: float = UiTokens.NORMAL) -> Tween:
	if reduced() or not item.is_inside_tree():
		item.modulate.a = alpha
		return null
	var t := tween(item, alpha < item.modulate.a)
	t.tween_property(item, "modulate:a", alpha, d)
	return t


## Shows `c` with a fade and a settle from UiTokens.OPEN_SCALE_FROM.
static func pop_in(c: Control, d: float = UiTokens.NORMAL) -> Tween:
	c.visible = true
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	if reduced() or not c.is_inside_tree():
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
		return null
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * UiTokens.OPEN_SCALE_FROM
	var t := tween(c)
	t.tween_property(c, "modulate:a", 1.0, d)
	t.tween_property(c, "scale", Vector2.ONE, d)
	return t


## Hides `c` with a fade and a shrink, then `visible = false` (at once under reduced motion).
static func pop_out(c: Control, d: float = UiTokens.FAST) -> Tween:
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	if reduced() or not c.is_inside_tree() or not c.visible:
		c.visible = false
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
		return null
	var t := tween(c, true)
	t.tween_property(c, "modulate:a", 0.0, d)
	t.tween_property(c, "scale", Vector2.ONE * UiTokens.OPEN_SCALE_FROM, d)
	t.chain().tween_callback(func() -> void:
		c.visible = false
		c.modulate.a = 1.0
		c.scale = Vector2.ONE)
	return t


## Hover / focus feedback: the control brightens a little (UiTokens.HOVER_TINT).
static func hover(c: CanvasItem, on: bool) -> void:
	var to := UiTokens.HOVER_TINT if on else Color.WHITE
	if reduced() or not c.is_inside_tree():
		c.self_modulate = to
		return
	var t := tween(c, not on, false)
	t.tween_property(c, "self_modulate", to, UiTokens.FAST)
