class_name ChatManager
extends Node
## Nakama room chat. Sender names come from the server-owned match roster
## (StateSynchronizer) with the message's own "name" field as fallback.

signal message_received(sender_name: String, text: String, is_self: bool)
signal system_message(text: String)

var socket: NakamaSocket
var channel_id: String = ""
var _self_user_id: String = ""
var _self_name: String = ""
var _name_lookup: Callable


## Returns "" on success.
func join(p_socket: NakamaSocket, self_user_id: String, self_name: String, name_lookup: Callable) -> String:
	socket = p_socket
	_self_user_id = self_user_id
	_self_name = self_name
	_name_lookup = name_lookup
	if not socket.received_channel_message.is_connected(_on_channel_message):
		socket.received_channel_message.connect(_on_channel_message)
	var channel: NakamaRTAPI.Channel = await socket.join_chat_async(
		NetworkProtocol.CHAT_ROOM, NakamaRTMessage.ChannelJoin.ChannelType.Room, false, false)
	if channel.is_exception():
		return tr("NET_CHAT_JOIN_FAILED") % channel.get_exception().message
	channel_id = channel.id
	return ""


func leave() -> void:
	channel_id = ""
	socket = null


func send(text: String) -> bool:
	var clean := NetworkProtocol.sanitize_chat(text)
	if clean.is_empty() or socket == null or channel_id.is_empty() or not socket.is_connected_to_host():
		return false
	socket.write_chat_message_async(channel_id, {"text": clean, "name": _self_name})
	return true


func _on_channel_message(message: NakamaAPI.ApiChannelMessage) -> void:
	if message.channel_id != channel_id:
		return
	var content := NetworkProtocol.decode(message.content)
	var text := NetworkProtocol.sanitize_chat(str(content.get("text", "")))
	if text.is_empty():
		return
	var is_self := message.sender_id == _self_user_id
	var sender_name := ""
	if is_self:
		sender_name = _self_name
	elif _name_lookup.is_valid():
		sender_name = str(_name_lookup.call(message.sender_id))
	if sender_name.is_empty():
		sender_name = str(content.get("name", message.username))
	message_received.emit(sender_name, text, is_self)
