class_name SubjectDefinition
extends Resource
## One school subject (resources/school/subjects/<id>.tres): where it is taught
## and which spells it teaches. Exported to the server (generated/subjects.lua)
## so lesson sessions only grant a subject's own spells in its own classrooms.
## Display names are the owner's final subject names; ids stay as they were.

## Stable identifier, equal to the resource file name.
@export var id: StringName = &""
## Translation keys (localization/translations.csv).
@export var display_name: String = ""
@export var description: String = ""
## Area ids of the rooms where the subject is taught (AreaZone kind "classroom").
@export var classrooms: PackedStringArray = []
## Spell ids taught per school year; index 0 = first year.
@export var spells_by_year: Array[PackedStringArray] = []
@export var color: Color = Color(0.8, 0.75, 0.6)


## Every spell of the subject, all years, in order.
func spells() -> PackedStringArray:
	var out := PackedStringArray()
	for year in spells_by_year:
		out.append_array(year)
	return out
