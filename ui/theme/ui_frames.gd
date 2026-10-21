class_name UiFrames
extends RefCounted
## The UI art kit (assets/ui/frames/, made by tools/make_ui_frames.py): nine-slice
## frames, buttons, fields, tabs, ribbons, slot rings, separators and the wax seal, each
## at 1x (name.png) and 2x (name@2x.png). The themes use the 1x pieces; when the
## interface is drawn larger than 1:1 (interface scale, a big or high-density window)
## use_density() swaps the 2x copies into every textured style of both themes, shown at
## the 1x size, so frames stay sharp. Components that draw a piece themselves ask
## texture() for it.

const DIR := "res://assets/ui/frames/"
## Above this drawing scale the 2x pieces are used.
const HIDPI_FROM := 1.15

static var hidpi := false
static var _cache: Dictionary = {}


static func path(piece: String, double := false) -> String:
	return DIR + piece + ("@2x" if double else "") + ".png"


## The piece at the current density (a 2x copy reports the 1x size).
static func texture(piece: String) -> Texture2D:
	return _texture(piece, hidpi)


## Picks the density for a drawing scale (interface scale times the window's stretch).
static func use_density(draw_scale: float) -> void:
	var want := draw_scale > HIDPI_FROM
	if want == hidpi:
		return
	hidpi = want
	for theme: Theme in [ThemeDB.get_project_theme(), load(UiTokens.PARCHMENT_THEME)]:
		if theme == null:
			continue
		for type in theme.get_stylebox_type_list():
			for item in theme.get_stylebox_list(type):
				var sb := theme.get_stylebox(item, type) as StyleBoxTexture
				if sb != null and sb.has_meta(&"frame"):
					sb.texture = _texture(str(sb.get_meta(&"frame")), hidpi)


## The drawing scale of the root window: interface scale times how far the canvas is
## stretched from the base size (1600x900).
static func draw_scale(root: Window, ui_scale: float) -> float:
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1600),
		ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	var win := Vector2(root.size)
	return ui_scale * minf(win.x / base.x, win.y / base.y)


static func _texture(piece: String, double: bool) -> Texture2D:
	var key := piece + ("@2x" if double else "")
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = load(path(piece))
	if double and ResourceLoader.exists(path(piece, true)):
		var img := (load(path(piece, true)) as Texture2D).get_image()
		if img != null:
			var big := ImageTexture.create_from_image(img)
			big.set_size_override(img.get_size() / 2)
			tex = big
	_cache[key] = tex
	return tex
