class_name HouseSorting
extends RefCounted
## The sorting ceremony's questionnaire. Each answer favours one house; the
## house with most votes wins. Online the server tallies (and breaks ties
## toward the emptiest house); offline [method sort_offline] applies the same
## rule with equal counts. The answer→house mapping mirrors SORTING in
## nakama/modules/character_profile.lua; keep the two in sync.

## Per question: translation key + answers (translation key, house 1–4).
const QUESTIONS: Array[Dictionary] = [
	{"key": "SORT_Q1", "answers": [{"key": "SORT_Q1_A1", "house": 4}, {"key": "SORT_Q1_A2", "house": 2}, {"key": "SORT_Q1_A3", "house": 3}, {"key": "SORT_Q1_A4", "house": 1}]},
	{"key": "SORT_Q2", "answers": [{"key": "SORT_Q2_A1", "house": 3}, {"key": "SORT_Q2_A2", "house": 1}, {"key": "SORT_Q2_A3", "house": 2}, {"key": "SORT_Q2_A4", "house": 4}]},
	{"key": "SORT_Q3", "answers": [{"key": "SORT_Q3_A1", "house": 4}, {"key": "SORT_Q3_A2", "house": 1}, {"key": "SORT_Q3_A3", "house": 3}, {"key": "SORT_Q3_A4", "house": 2}]},
	{"key": "SORT_Q4", "answers": [{"key": "SORT_Q4_A1", "house": 1}, {"key": "SORT_Q4_A2", "house": 2}, {"key": "SORT_Q4_A3", "house": 4}, {"key": "SORT_Q4_A4", "house": 3}]},
]


static func question_count() -> int:
	return QUESTIONS.size()


## True when `answers` holds one 1-based answer index per question.
static func valid(answers: Array) -> bool:
	if answers.size() != QUESTIONS.size():
		return false
	for q in QUESTIONS.size():
		var a := int(answers[q])
		if a < 1 or a > QUESTIONS[q]["answers"].size():
			return false
	return true


## Votes per house, index 1–4 (index 0 unused). Empty when invalid.
static func tally(answers: Array) -> PackedInt32Array:
	if not valid(answers):
		return PackedInt32Array()
	var scores := PackedInt32Array([0, 0, 0, 0, 0])
	for q in QUESTIONS.size():
		var house: int = QUESTIONS[q]["answers"][int(answers[q]) - 1]["house"]
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
