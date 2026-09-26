class_name Nameplate
extends Label3D
## Display name floating above a character. Billboarded, hidden for the local player.


func set_display_name(display_name: String) -> void:
	text = display_name
