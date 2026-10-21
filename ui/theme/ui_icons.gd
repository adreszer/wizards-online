class_name UiIcons
extends RefCounted
## The icon registry (docs/ui.md, "Iconography"): code asks for an icon by id, never
## for a file. Icons are white single-colour vectors (DPITexture, sharp at any scale)
## in assets/ui/icons/<id>.tres, tinted where they are drawn (brass on chrome, ink on
## paper). Today they are game-icons.net placeholders (tools/make_ui_icons.py, credits in
## assets/ui/icons/CREDITS.md); the final set replaces the files under the same ids.

const DIR := "res://assets/ui/icons/"
## The size the sources are drawn for (their own viewBox is 512).
const SOURCE := 512.0

static var _cache: Dictionary = {}


static func has(id: String) -> bool:
	return ResourceLoader.exists(DIR + id + ".tres")


## Icon `id` drawn at `px` pixels (at interface scale 1), or null if there is none.
static func icon(id: String, px: int = 32) -> Texture2D:
	var key := "%s@%d" % [id, px]
	if _cache.has(key):
		return _cache[key]
	if not has(id):
		push_warning("UiIcons: no icon '%s'" % id)
		return null
	var tex := (load(DIR + id + ".tres") as DPITexture).duplicate() as DPITexture
	tex.base_scale = px / SOURCE
	_cache[key] = tex
	return tex


## Every id in the set (the gallery, tests).
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			out.append(f.trim_suffix(".tres"))
	out.sort()
	return out
