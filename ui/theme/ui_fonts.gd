class_name UiFonts
extends RefCounted
## The game's three typefaces (owner's choice, 2026-10-20): Cormorant SC for display
## (titles, area banners, house and spell names), EB Garamond for reading text on
## parchment (journal, books, lectures, quizzes), Fira Sans for the interface (HUD,
## buttons, chat, settings; also the project's default font). All OFL, licences beside
## the files in assets/fonts/; Noto Sans Symbols fills in symbols. Code asks for a role here, never for a font file.
## The .tres resources are written by tools/build_ui_theme.gd.

const DISPLAY := "res://ui/theme/fonts/display.tres"
const DISPLAY_BOLD := "res://ui/theme/fonts/display_bold.tres"
const TEXT := "res://ui/theme/fonts/text.tres"
const TEXT_ITALIC := "res://ui/theme/fonts/text_italic.tres"
const TEXT_BOLD := "res://ui/theme/fonts/text_bold.tres"
const UI := "res://ui/theme/fonts/ui.tres"
const UI_ITALIC := "res://ui/theme/fonts/ui_italic.tres"
const UI_MEDIUM := "res://ui/theme/fonts/ui_medium.tres"
const UI_BOLD := "res://ui/theme/fonts/ui_bold.tres"

## Drawn when a face lacks a glyph (bullets, arrows, stars, ticks), so symbols look the
## same on every platform instead of coming from whatever system font is installed.
const SYMBOL_FALLBACKS := ["res://assets/fonts/noto_symbols/UiSymbols2.ttf",
	"res://assets/fonts/noto_symbols/UiSymbols.ttf"]

## Role → [source file, weight axis value or 0 for a static file].
const SOURCES := {
	DISPLAY: ["res://assets/fonts/cormorant_sc/CormorantSC-SemiBold.ttf", 0],
	DISPLAY_BOLD: ["res://assets/fonts/cormorant_sc/CormorantSC-Bold.ttf", 0],
	TEXT: ["res://assets/fonts/eb_garamond/EBGaramond-Variable.ttf", 400],
	TEXT_ITALIC: ["res://assets/fonts/eb_garamond/EBGaramond-Italic-Variable.ttf", 400],
	TEXT_BOLD: ["res://assets/fonts/eb_garamond/EBGaramond-Variable.ttf", 700],
	UI: ["res://assets/fonts/fira_sans/FiraSans-Regular.ttf", 0],
	UI_ITALIC: ["res://assets/fonts/fira_sans/FiraSans-Italic.ttf", 0],
	UI_MEDIUM: ["res://assets/fonts/fira_sans/FiraSans-Medium.ttf", 0],
	UI_BOLD: ["res://assets/fonts/fira_sans/FiraSans-Bold.ttf", 0],
}


static func display(bold: bool = false) -> Font:
	return load(DISPLAY_BOLD if bold else DISPLAY)


static func text(italic: bool = false, bold: bool = false) -> Font:
	return load(TEXT_BOLD if bold else (TEXT_ITALIC if italic else TEXT))


static func ui(weight: String = "regular") -> Font:
	return load({"italic": UI_ITALIC, "medium": UI_MEDIUM, "bold": UI_BOLD}.get(weight, UI))
