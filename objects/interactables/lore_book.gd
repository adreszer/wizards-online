class_name LoreBook
extends StaticBody3D
## A book open on a reading stand: interact to read it in the BookPanel, page by page.
## [member book] names its text: BOOK_<book>_TITLE and BOOK_<book>_P1… in the
## translations. Books carry the school's original lore, and some answer quiz and
## homework questions or hint at secrets; reading one is reported to the server, so a
## mystery can ask for it.

const WORLD_KIND := "lore_book"
const MAX_PAGES := 8

## Stable id ("<area>/<name>") set by the castle generator.
@export var object_id: String = ""
@export var book: String = "FOUNDING"

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)


## The translation keys of the pages that exist.
func page_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(1, MAX_PAGES + 1):
		var key := "BOOK_%s_P%d" % [book, i]
		if tr(key) == key:
			break
		out.append(key)
	return out


func _on_interacted(_interactor: Node) -> void:
	GameEvents.book_requested.emit("BOOK_%s_TITLE" % book, page_keys())
	WorldObjectSync.report(self, "interact")
