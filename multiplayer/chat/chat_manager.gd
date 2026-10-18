class_name ChatManager
extends Node
## Chat through the world match. The server decides who hears a line
## (nakama/modules/chat.lua): say and whisper stay near the speaker and inside their
## room, a shout carries further, a direct message reaches one player or waits in
## their mailbox. This node only sends requests and turns the answers into signals.

## Every say line (compat: the speaker's name, the text, whether it is our own).
signal message_received(sender_name: String, text: String, is_self: bool)
## Every chat or DM line: {kind: "chat" | "dm", mode, sid, name, text, self, to_name, mail}.
signal line_received(line: Dictionary)
signal system_message(text: String)

var session: WorldSession
var _self_name: String = ""
## Who last sent us a DM (for /r).
var last_dm_from: String = ""


func bind(p_session: WorldSession) -> void:
	session = p_session
	session.message_received.connect(_on_message)


## Called on join: our own name tells our lines apart.
func join(self_name: String) -> void:
	_self_name = self_name


func leave() -> void:
	last_dm_from = ""


func send(text: String, mode: String = NetworkProtocol.CHAT_SAY) -> bool:
	var clean := NetworkProtocol.sanitize_chat(text)
	if clean.is_empty() or session == null or not session.is_active():
		return false
	session.send(NetworkProtocol.OP_CHAT, {"text": clean, "mode": mode})
	return true


func send_dm(to_name: String, text: String) -> bool:
	var clean := NetworkProtocol.sanitize_chat(text)
	if clean.is_empty() or to_name.strip_edges().is_empty() or session == null or not session.is_active():
		return false
	session.send(NetworkProtocol.OP_DM, {"to": to_name.strip_edges(), "text": clean})
	return true


func _on_message(op_code: int, payload: Dictionary) -> void:
	match op_code:
		NetworkProtocol.OP_CHAT_LINE:
			var text := NetworkProtocol.sanitize_chat(str(payload.get("text", "")))
			if text.is_empty():
				return
			var sid := str(payload.get("sid", ""))
			var is_self := sid == session.self_session_id
			var line := {"kind": "chat", "mode": str(payload.get("mode", NetworkProtocol.CHAT_SAY)), "sid": sid,
				"name": str(payload.get("name", "?")), "text": text, "self": is_self}
			line_received.emit(line)
			if line.mode == NetworkProtocol.CHAT_SAY:
				message_received.emit(line.name, text, is_self)
		NetworkProtocol.OP_DM_LINE:
			var text := NetworkProtocol.sanitize_chat(str(payload.get("text", "")))
			if text.is_empty():
				return
			var line := {"kind": "dm", "mode": "dm", "sid": "", "name": str(payload.get("from_name", "?")), "text": text,
				"self": payload.get("self", false) == true, "to_name": str(payload.get("to_name", "")), "mail": payload.get("mail", false) == true}
			if not line.self:
				last_dm_from = line.name
			line_received.emit(line)
		NetworkProtocol.OP_CHAT_RESULT:
			if payload.get("ok", false) == true:
				if payload.get("mailed", false) == true:
					system_message.emit(tr("CHAT_DM_MAILED") % str(payload.get("to_name", "")))
				return
			system_message.emit(result_text(str(payload.get("reason", "")), payload))


## The chat line for a refused message.
static func result_text(reason: String, payload: Dictionary = {}) -> String:
	match reason:
		"too_soon":
			if payload.get("mode", "") == NetworkProtocol.CHAT_SHOUT:
				return TranslationServer.translate("CHAT_SHOUT_TOO_SOON") % int(payload.get("wait", 1))
			return TranslationServer.translate("CHAT_TOO_SOON")
		"no_such_player":
			return TranslationServer.translate("CHAT_DM_NO_PLAYER") % str(payload.get("to_name", ""))
		"mailbox_full":
			return TranslationServer.translate("CHAT_DM_MAILBOX_FULL") % str(payload.get("to_name", ""))
		"muted":
			return TranslationServer.translate("CHAT_MUTED")
		"blocked":
			return TranslationServer.translate("CHAT_BLOCKED") % str(payload.get("to_name", ""))
	# Refusals from the server's feature modules (a quieted classroom…) have their own lines.
	var key := "REFUSED_" + reason.to_upper()
	if TranslationServer.translate(key) != key:
		return TranslationServer.translate(key)
	return TranslationServer.translate("CHAT_REFUSED") % reason
