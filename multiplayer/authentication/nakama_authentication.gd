class_name NakamaAuthentication
extends Node
## Device authentication against Nakama.
##
## Choice: device auth (see docs/architecture.md). The device id is generated
## once and persisted by the Nakama addon in `user://nakama_device_id`.
## `--instance=N` appends a suffix so two clients on one machine get two
## Nakama accounts.
##
## Account recovery: a player can add an email and password to their account
## (protect_with_email); on another computer (or after a reinstall)
## recover_with_email signs in with them and moves this device's id onto that
## account, so the plain device login from then on lands on the old character.

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
		return _describe(ex, tr("NET_AUTH_FAILED"))
	session = result
	user_id = session.user_id
	return ""


## Adds an email and password to the signed-in account. "" on success.
func protect_with_email(email: String, password: String) -> String:
	if client == null or session == null:
		return tr("ACCOUNT_NEEDS_ONLINE")
	var result: NakamaAsyncResult = await client.link_email_async(session, email, password)
	if result.is_exception():
		return _describe_account(result.get_exception())
	return ""


## The email on the signed-in account ("" when none, or offline).
func account_email() -> String:
	if client == null or session == null:
		return ""
	var account = await client.get_account_async(session)
	if account == null or account.is_exception():
		return ""
	return str(account.email)


## Signs in with an email and password and links this device to that account, so
## the next device login is the recovered character. "" on success. The client must
## exist (create_client). A device already tied to another account (a fresh one made
## on this computer) is moved over.
func recover_with_email(email: String, password: String) -> String:
	var recovered: NakamaSession = await client.authenticate_email_async(email, password, null, false)
	if recovered.is_exception():
		return _describe_account(recovered.get_exception())
	var device_id := _get_device_id()
	var linked: NakamaAsyncResult = await client.link_device_async(recovered, device_id)
	if linked.is_exception():
		# The device belongs to another account: sign in as that one and let go of it.
		var other: NakamaSession = await client.authenticate_device_async(device_id, null, false)
		if other.is_exception():
			return _describe_account(linked.get_exception())
		if other.user_id != recovered.user_id:
			# Nakama keeps every account reachable by something: give the one left behind a
			# throwaway custom id before taking the device away from it.
			var keep: NakamaAsyncResult = await client.link_custom_async(other, "released-%s-%d" % [device_id.sha256_text().substr(0, 24), Time.get_unix_time_from_system()])
			if keep.is_exception():
				return _describe_account(keep.get_exception())
			var released: NakamaAsyncResult = await client.unlink_device_async(other, device_id)
			if released.is_exception():
				return _describe_account(released.get_exception())
			linked = await client.link_device_async(recovered, device_id)
			if linked.is_exception():
				return _describe_account(linked.get_exception())
	session = recovered
	user_id = recovered.user_id
	return ""


## Deletes the signed-in account and everything stored under it (character, spells,
## inventory, purse, progress). "" on success.
func delete_account() -> String:
	if client == null or session == null:
		return tr("ACCOUNT_NEEDS_ONLINE")
	var result: NakamaAsyncResult = await client.delete_account_async(session)
	if result.is_exception():
		return _describe_account(result.get_exception())
	session = null
	user_id = ""
	return ""


## Validation the server applies to emails and passwords, checked first for a clear message.
static func check_credentials(email: String, password: String) -> String:
	if not email.contains("@") or email.length() < 5 or email.length() > 255:
		return TranslationServer.translate("ACCOUNT_BAD_EMAIL")
	if password.length() < 8:
		return TranslationServer.translate("ACCOUNT_SHORT_PASSWORD")
	return ""


static func _describe_account(ex: NakamaException) -> String:
	if ex != null:
		match ex.status_code:
			401, 404, 16, 5:
				return TranslationServer.translate("ACCOUNT_WRONG_LOGIN")
			409, 6:
				return TranslationServer.translate("ACCOUNT_EMAIL_TAKEN")
	return _describe(ex, TranslationServer.translate("ACCOUNT_FAILED"))


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
		return TranslationServer.translate("NET_SERVER_UNREACHABLE") % prefix
	return TranslationServer.translate("NET_ERROR_WITH_CODE") % [prefix, ex.message, ex.status_code]
