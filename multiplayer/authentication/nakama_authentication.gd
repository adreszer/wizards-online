class_name NakamaAuthentication
extends Node
## Device authentication against Nakama.
##
## Choice: device auth (see docs/architecture.md). The device id is generated
## once and persisted by the Nakama addon in `user://nakama_device_id`.
## `--instance=N` appends a suffix so two clients on one machine get two
## Nakama accounts.

var client: NakamaClient
var session: NakamaSession
var user_id: String = ""


func create_client(host: String, port: int, scheme: String, server_key: String, timeout_seconds: int) -> void:
	client = Nakama.create_client(server_key, host, port, scheme, timeout_seconds, NakamaLogger.LOG_LEVEL.WARNING)


## Returns an empty string on success or a human-readable error.
func authenticate(display_name: String) -> String:
	var device_id := _get_device_id()
	var vars := {"display_name": display_name}
	var result: NakamaSession = await client.authenticate_device_async(device_id, null, true, vars)
	if result.is_exception():
		var ex := result.get_exception()
		return _describe(ex, "Authentication failed")
	session = result
	user_id = session.user_id
	return ""


func _get_device_id() -> String:
	var base: String = Nakama.get_device_id()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--instance="):
			return "%s-%s" % [base, arg.trim_prefix("--instance=")]
	return base


static func _describe(ex: NakamaException, prefix: String) -> String:
	if ex == null:
		return prefix
	if ex.status_code < 100 or ex.message.is_empty() or ex.message.begins_with("HTTPRequest failed"):
		return "%s: server unreachable" % prefix
	return "%s: %s (%d)" % [prefix, ex.message, ex.status_code]
