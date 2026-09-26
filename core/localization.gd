class_name Localization
extends RefCounted
## Locale resolution for the game. Polish is the primary (source) language,
## English the secondary. All player-facing text lives in
## `res://localization/translations.csv` (columns: keys, en, pl); scenes and
## scripts only ever use the keys.
##
## Locale choice: an explicit user setting ("pl"/"en") wins, otherwise "auto"
## follows the platform: the Steam client language once Steamworks is
## integrated, else the OS language, else Polish.

const PRIMARY := "pl"
const SUPPORTED: PackedStringArray = ["pl", "en"]
const AUTO := "auto"

## Steam API language names (SteamApps::GetCurrentGameLanguage) → locale.
## Extend together with SUPPORTED and the Steamworks store-page language list.
const STEAM_LANGUAGES := {"polish": "pl", "english": "en"}

## Native names for the in-game language picker (never translated).
const NATIVE_NAMES := {"pl": "Polski", "en": "English"}


## Picks the locale for a setting value ("auto", "pl", "en" or anything else,
## which is treated as auto). Always returns a supported locale.
static func resolve(setting: String) -> String:
	if SUPPORTED.has(setting):
		return setting
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			var forced := arg.trim_prefix("--lang=")
			if SUPPORTED.has(forced):
				return forced
	var steam := steam_language()
	if not steam.is_empty():
		return steam
	var os_language := OS.get_locale_language()
	if SUPPORTED.has(os_language):
		return os_language
	return PRIMARY


## Applies the setting to the TranslationServer and returns the chosen locale.
## Every Control with a translation key refreshes itself on the change.
static func apply(setting: String) -> String:
	var locale := resolve(setting)
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)
	return locale


## Language reported by the Steam client. Empty until Steamworks (GodotSteam)
## is wired in: then return STEAM_LANGUAGES.get(Steam.getCurrentGameLanguage(), "").
## The SteamLanguage env var lets us test that path without the SDK.
static func steam_language() -> String:
	var name := OS.get_environment("SteamLanguage").to_lower()
	return str(STEAM_LANGUAGES.get(name, ""))
