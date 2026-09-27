class_name Nameplate
extends Label3D
## Display name floating above a character. Billboarded, hidden for the local
## player. Staff get a title line and a distinct colour so a professor is
## recognisable across a classroom.

const STUDENT_COLOR := Color(1, 1, 1)
const PROFESSOR_COLOR := Color(1, 0.86, 0.5)
const ADMIN_COLOR := Color(0.7, 0.9, 1)

var _display_name: String = ""
var _role: String = CharacterProfile.ROLE_STUDENT


func set_display_name(display_name: String) -> void:
	_display_name = display_name
	_refresh()


func set_role(role: String) -> void:
	_role = CharacterProfile.sanitize_role(role)
	_refresh()


func _refresh() -> void:
	var title_key := CharacterProfile.title_key(_role)
	text = _display_name if title_key.is_empty() else "%s %s" % [tr(title_key), _display_name]
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
