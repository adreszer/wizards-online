class_name Nameplate
extends Label3D
## Display name floating above a character. Billboarded, hidden for the local
## player. Staff get a title line and a distinct colour so a professor is
## recognisable across a classroom. The name is set in the display face (UiFonts),
## the house line carries the house symbol beside its name, colours are UiTokens.

const STUDENT_COLOR := UiTokens.NAME_STUDENT
const PROFESSOR_COLOR := UiTokens.NAME_PROFESSOR
const ADMIN_COLOR := UiTokens.NAME_ADMIN

var _display_name: String = ""
var _role: String = CharacterProfile.ROLE_STUDENT
var _house: int = 0


func _ready() -> void:
	UiFonts.world_label(self, UiFonts.display(true), outline_size)


func set_display_name(display_name: String) -> void:
	_display_name = display_name
	_refresh()


func set_role(role: String) -> void:
	_role = CharacterProfile.sanitize_role(role)
	_refresh()


func set_house(house: int) -> void:
	_house = CharacterProfile.sanitize_house(house)
	_refresh()


func _refresh() -> void:
	var title_key := CharacterProfile.title_key(_role)
	text = _display_name if title_key.is_empty() else "%s %s" % [tr(title_key), _display_name]
	if _house != 0:
		text += "\n%s %s" % [GameSettings.HOUSE_SYMBOLS[_house], CharacterProfile.house_name(_house)]
	match _role:
		CharacterProfile.ROLE_PROFESSOR:
			modulate = PROFESSOR_COLOR
		CharacterProfile.ROLE_ADMIN:
			modulate = ADMIN_COLOR
		_:
			modulate = STUDENT_COLOR


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
