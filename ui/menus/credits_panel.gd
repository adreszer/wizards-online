class_name CreditsPanel
extends FeaturePanel
## Credits (main menu → Credits): who made the game and whose work it stands on. Each
## section is a heading (a translation key) and lines that stay as written (names,
## licences). The icon authors come from assets/ui/icons/CREDITS.md, so a new icon
## credits itself. Keep this in step with the provenance files:
## assets/ui/PROVENANCE.md, assets/audio/SOURCES.csv, assets/ui/icons/CREDITS.md.

const ICON_CREDITS := "res://assets/ui/icons/CREDITS.md"
const SECTIONS := [
	["CREDITS_MADE_BY", ["Adam Dreszer"]],
	["CREDITS_ENGINE", ["Godot Engine — godotengine.org (MIT)", "Jolt Physics — Jorrit Rouwe (MIT)",
		"Nakama — Heroic Labs (Apache 2.0)"]],
	["CREDITS_FONTS", ["Cormorant SC — Christian Thalmann (SIL OFL 1.1)", "EB Garamond — Georg Duffner, Octavio Pardo (SIL OFL 1.1)",
		"Fira Sans — Carrois Apostrophe, Mozilla (SIL OFL 1.1)", "Noto Sans Symbols — Google (SIL OFL 1.1)"]],
	["CREDITS_ICONS", []],
	["CREDITS_TEXTURES", ["ambientCG — ambientcg.com (CC0)", "Poly Haven — polyhaven.com (CC0)"]],
	["CREDITS_MODELS", ["Meshy — meshy.ai", "Poly Haven — polyhaven.com (CC0)", "Mixamo — Adobe (animations)"]],
	["CREDITS_SOUND", ["ElevenLabs — sound effects, music and voices"]],
	["CREDITS_ART", ["Recraft — house crests, school emblem and wordmark"]],
]


func _ready() -> void:
	half_size = Vector2(360, 300)
	family = UiWindow.Family.CHROME
	super()
	card.add_key_hint(&"pause", tr("UI_CLOSE"))


func _build() -> void:
	title_label.text = tr("MENU_CREDITS")
	for section: Array in SECTIONS:
		var heading := Label.new()
		heading.text = tr(section[0])
		heading.theme_type_variation = &"TitleLabel"
		body.add_child(heading)
		var lines: Array = section[1]
		if section[0] == "CREDITS_ICONS":
			lines = [icon_line()]
		for line: String in lines:
			var l := Label.new()
			l.text = line
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			body.add_child(l)
		body.add_child(HSeparator.new())
	var thanks := Label.new()
	thanks.text = tr("CREDITS_THANKS")
	thanks.theme_type_variation = &"HintLabel"
	thanks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(thanks)


## "game-icons.net — Lorc, Delapouite, Sbed (CC BY 3.0)": the authors from the icon
## credits table.
static func icon_line() -> String:
	var authors := PackedStringArray()
	for row in FileAccess.get_file_as_string(ICON_CREDITS).split("\n"):
		var cells := row.split("|", false)
		if cells.size() == 3 and not row.contains("---") and cells[0].strip_edges() != "Id":
			var who := cells[2].strip_edges()
			if not authors.has(who):
				authors.append(who)
	return "game-icons.net — %s (CC BY 3.0)" % ", ".join(authors)
