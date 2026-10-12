class_name SortingQuestionnaire
extends Resource
## The sorting ceremony's questions as data (resources/school/sorting.tres).
## Read through HouseSorting; exported to the server by
## tools/export_server_content.gd.

## Per question: {"key": translation key, "answers": [{"key": translation key, "house": 1–4}]}.
@export var questions: Array[Dictionary] = []
