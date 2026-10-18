class_name RequestText
extends RefCounted
## What a feature request's answer says in the chat log: requests that return
## something to read (house numbers, the ladder, a profile…) get a line built from
## their data; the rest say "OK_<KIND>" or the refusal (NetworkManager.result_text).


static func describe(kind: String, r: Dictionary) -> String:
	if not r.get("ok", false):
		return NetworkManager.refusal_text(str(r.get("reason", "")))
	var d: Dictionary = r.get("data", {})
	match kind:
		"house_stats":
			var parts := PackedStringArray()
			var by: Variant = d.get("by_source", {})
			if by is Dictionary:
				for src: String in by:
					parts.append("%s %+d" % [src, int(by[src])])
			return tr_("HOUSE_STATS_LINE") % [CharacterProfile.house_name(int(d.get("house", 0))), int(d.get("total", 0)), int(d.get("members", 0)),
				int(d.get("online", 0)), ", ".join(parts) if not parts.is_empty() else "-"]
		"ladder_view":
			return ladder_text(d)
		"wing_state", "wing_contribute":
			return tr_("WING_STATE_LINE") % [int(d.get("opened", 0)), int(d.get("doors", 0)), int(d.get("points", 0)), int(d.get("next", 0))]
	return NetworkManager.result_text(kind, r)


static func ladder_text(d: Dictionary) -> String:
	var lines := PackedStringArray([tr_("LADDER_HEADER")])
	var top: Variant = d.get("top", [])
	if top is Array:
		var i := 0
		for p: Dictionary in top:
			i += 1
			lines.append("%d. %s  %d (%d–%d)" % [i, str(p.get("name", "")), int(p.get("rating", 0)), int(p.get("wins", 0)), int(p.get("losses", 0))])
	if lines.size() == 1:
		lines.append(tr_("LADDER_EMPTY"))
	return "\n".join(lines)


static func tr_(key: String) -> String:
	return TranslationServer.translate(key)
