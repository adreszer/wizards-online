class_name HouseSorting
extends RefCounted
## The sorting ceremony's questionnaire. Each answer favours one house; the
## house with most votes wins. Online the server tallies (and breaks ties
## toward the emptiest house); offline [method sort_offline] applies the same
## rule with equal counts. The questions are data (resources/school/sorting.tres);
## tools/export_server_content.gd exports the answer→house mapping to the
## server, so both sides always sort the same way.

const QUESTIONNAIRE_PATH := "res://resources/school/sorting.tres"

static var _questions: Array[Dictionary] = []


## Per question: translation key + answers (translation key, house 1–4).
static func questions() -> Array[Dictionary]:
	if _questions.is_empty():
		var res := load(QUESTIONNAIRE_PATH) as SortingQuestionnaire
		if res != null:
			_questions = res.questions
	return _questions


static func question_count() -> int:
	return questions().size()


## True when `answers` holds one 1-based answer index per question.
static func valid(answers: Array) -> bool:
	if answers.size() != questions().size():
		return false
	for q in questions().size():
		var a := int(answers[q])
		if a < 1 or a > questions()[q]["answers"].size():
			return false
	return true


## Votes per house, index 1–4 (index 0 unused). Empty when invalid.
static func tally(answers: Array) -> PackedInt32Array:
	if not valid(answers):
		return PackedInt32Array()
	var scores := PackedInt32Array([0, 0, 0, 0, 0])
	for q in questions().size():
		var house: int = questions()[q]["answers"][int(answers[q]) - 1]["house"]
		scores[house] += 1
	return scores


## Highest score wins; ties go to the house with the fewest members.
static func pick(scores: PackedInt32Array, counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])) -> int:
	if scores.size() < CharacterProfile.MAX_HOUSE + 1:
		return 0
	var best := 1
	for h in range(2, CharacterProfile.MAX_HOUSE + 1):
		if scores[h] > scores[best] or (scores[h] == scores[best] and counts[h] < counts[best]):
			best = h
	return best


## Offline ceremony: same rule, nobody else to balance against.
static func sort_offline(answers: Array) -> int:
	var scores := tally(answers)
	return pick(scores) if not scores.is_empty() else 0
