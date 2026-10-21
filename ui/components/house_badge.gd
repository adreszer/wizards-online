class_name HouseBadge
extends HBoxContainer
## The one way a house is shown (docs/ui.md, "Components"): the crest, and beside it
## the house name in the house colour with its symbol (CharacterProfile.house_name adds
## the symbol when the player asked for symbols beside colours). Small badges use the
## single-colour crest tinted in the house colour; medium and large the painted one.
## The unsorted get the school emblem, dimmed.

enum Size { SMALL = 24, MEDIUM = 48, LARGE = 96 }

const EMBLEM := "res://assets/ui/brand/emblem_512.png"

static var _sized_cache: Dictionary = {}

var crest_rect: TextureRect
var name_label: Label
var house := 0:
	set(value):
		house = value
		_refresh()
var badge_size: Size = Size.MEDIUM:
	set(value):
		badge_size = value
		_refresh()
var show_name := true:
	set(value):
		show_name = value
		_refresh()


func _init(for_house := 0, size_px: Size = Size.MEDIUM, with_name := true) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	crest_rect = TextureRect.new()
	crest_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crest_rect)
	name_label = Label.new()
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(name_label)
	house = for_house
	badge_size = size_px
	show_name = with_name


func _refresh() -> void:
	if crest_rect == null:
		return
	var px := int(badge_size)
	crest_rect.custom_minimum_size = Vector2(px, px)
	var sorted := house >= 1 and house <= CharacterProfile.MAX_HOUSE
	if not sorted:
		crest_rect.texture = sized(load(EMBLEM), px)
		crest_rect.modulate = Color(1, 1, 1, 0.45)
	elif badge_size == Size.SMALL:
		crest_rect.texture = CharacterProfile.crest(house, CharacterProfile.CREST_ICON)
		crest_rect.modulate = CharacterProfile.house_color(house)
	else:
		crest_rect.texture = sized(CharacterProfile.crest(house, CharacterProfile.CREST_CARD if badge_size == Size.MEDIUM else CharacterProfile.CREST_FULL), px)
		crest_rect.modulate = Color.WHITE
	name_label.visible = show_name
	name_label.text = CharacterProfile.house_name(house) if sorted else tr("PROFILE_UNSORTED")
	name_label.theme_type_variation = &"TitleLabel" if badge_size == Size.LARGE else &""
	name_label.add_theme_color_override("font_color", CharacterProfile.house_color(house).lightened(0.2) if sorted else UiTokens.CANDLE_SOFT)
	if badge_size == Size.SMALL:
		name_label.add_theme_font_size_override("font_size", UiTokens.SIZE_HINT)
	else:
		name_label.remove_theme_font_size_override("font_size")


## `texture` shrunk smoothly to twice `px` (shown at `px`): the crests and the emblem
## are far larger than a badge and have no mipmaps, so drawn straight they shimmer.
static func sized(texture: Texture2D, px: int) -> Texture2D:
	if texture == null or texture.get_width() <= px * 2:
		return texture
	var key := "%s@%d" % [texture.resource_path, px]
	if _sized_cache.has(key):
		return _sized_cache[key]
	var img := texture.get_image()
	if img == null:
		return texture
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var h := int(round(px * 2.0 * img.get_height() / img.get_width()))
	img.resize(px * 2, h, Image.INTERPOLATE_LANCZOS)
	var out := ImageTexture.create_from_image(img)
	out.set_size_override(Vector2i(px, int(round(h / 2.0))))
	_sized_cache[key] = out
	return out
