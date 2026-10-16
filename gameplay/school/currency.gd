class_name Currency
extends RefCounted
## The school's currency on the client: amounts in words and the line shown when the
## purse changes. The server owns every balance (nakama/modules/economy.lua, Nakama's
## wallet); the client only shows what OP_WALLET says (NetworkManager.wallet_changed).
## The name is a placeholder ("korony" / "crowns") until the owner picks one: it lives
## only in the CURRENCY_* translation keys.

## Polish plural form for n: "one" (1), "few" (2–4, 22–24…, not 12–14) or "many".
static func polish_form(n: int) -> String:
	n = absi(n)
	if n == 1:
		return "one"
	var tens := n % 100
	if n % 10 >= 2 and n % 10 <= 4 and (tens < 12 or tens > 14):
		return "few"
	return "many"


## "1 korona", "3 korony", "5 koron" / "1 crown", "5 crowns" in the current language.
static func format(amount: int) -> String:
	var form := "many"
	if TranslationServer.get_locale().begins_with("pl"):
		form = polish_form(amount)
	elif absi(amount) == 1:
		form = "one"
	return _t("CURRENCY_" + form.to_upper()) % absi(amount)


## The notification for a change of the purse (or "" for none): "+10 koron: lekcja Zaklęć".
static func change_line(delta: int, source: String, detail: String) -> String:
	if delta == 0:
		return ""
	var amount := ("+" if delta > 0 else "−") + format(delta)
	match source:
		"lesson":
			var subject := SubjectRegistry.load_definition(detail)
			return _t("WALLET_FROM_LESSON") % [amount, _t(subject.display_name) if subject != null else detail]
		"mystery":
			return _t("WALLET_FROM_MYSTERY") % amount
		"shop":
			return _t("WALLET_FROM_SHOP") % amount
	return _t("WALLET_FROM_ADMIN") % amount


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
