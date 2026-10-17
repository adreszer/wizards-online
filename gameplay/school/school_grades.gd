class_name SchoolGrades
extends RefCounted
## A subject's grade (1–6, the Polish school scale) from the student's record: how
## often they came (lessons, self-study counting half), how many quiz and exam answers
## were right, practicals done and the homework average. Parts without any data drop
## out and the rest is reweighted; with too little data there is no grade yet (0).
## nakama/modules/grades.lua mirrors this for year advancement.

const PASS := 2
const WEIGHTS := {"attendance": 0.25, "quiz": 0.25, "exam": 0.2, "practicals": 0.1, "homework": 0.2}
## Lessons (self-study counts half) that make full marks for attendance.
const FULL_ATTENDANCE := 6.0
const FULL_PRACTICALS := 2.0
## Lessons needed before a grade is given.
const MIN_LESSONS := 1.0


static func score_parts(s: Dictionary) -> Dictionary:
	var parts := {}
	var lessons := float(s.get("attended", 0)) + 0.5 * float(s.get("self_study", 0))
	if lessons > 0.0:
		parts["attendance"] = minf(1.0, lessons / FULL_ATTENDANCE)
	if int(s.get("quiz_total", 0)) > 0:
		parts["quiz"] = float(s.get("quiz_right", 0)) / float(s.quiz_total)
	if int(s.get("exam_total", 0)) > 0:
		parts["exam"] = float(s.get("exam_right", 0)) / float(s.exam_total)
	if int(s.get("practicals", 0)) > 0 or lessons >= FULL_ATTENDANCE:
		parts["practicals"] = minf(1.0, float(s.get("practicals", 0)) / FULL_PRACTICALS)
	if int(s.get("homework_count", 0)) > 0:
		parts["homework"] = (float(s.get("homework_points", 0)) / float(s.homework_count) - 1.0) / 5.0
	return parts


## 1–6, or 0 when there is not enough to grade yet.
static func grade(s: Dictionary) -> int:
	var lessons := float(s.get("attended", 0)) + 0.5 * float(s.get("self_study", 0))
	if lessons < MIN_LESSONS:
		return 0
	var parts := score_parts(s)
	var total := 0.0
	var weight := 0.0
	for k: String in parts:
		total += float(WEIGHTS[k]) * float(parts[k])
		weight += float(WEIGHTS[k])
	if weight <= 0.0:
		return 0
	return clampi(1 + int(round(5.0 * total / weight)), 1, 6)
