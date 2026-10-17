class_name SpellMastery
extends RefCounted
## How well a character knows each spell. The server counts mastery points for real
## use (a validated spell on a world object, more for practice-target hits; one award
## per spell every few seconds) and keeps them in the profile (`mastery`); levels are
## read from the points here. Mastery is polish, never power over other players: a
## shorter cooldown and a bigger, brighter cast.

## Points needed for each level: novice, adept, skilled, master.
const THRESHOLDS: Array[int] = [0, 20, 60, 150]
const LEVEL_KEYS: Array[String] = ["MASTERY_NOVICE", "MASTERY_ADEPT", "MASTERY_SKILLED", "MASTERY_MASTER"]


static func level_of(points: int) -> int:
	var level := 0
	for i in THRESHOLDS.size():
		if points >= THRESHOLDS[i]:
			level = i
	return level


static func level_key(points: int) -> String:
	return LEVEL_KEYS[level_of(points)]


## Points still needed for the next level (0 at the top).
static func to_next(points: int) -> int:
	var level := level_of(points)
	return 0 if level >= THRESHOLDS.size() - 1 else THRESHOLDS[level + 1] - points


## Cooldown multiplier: 10 % shorter per level.
static func cooldown_factor(level: int) -> float:
	return 1.0 - 0.1 * clampi(level, 0, THRESHOLDS.size() - 1)


## Size of the cast's projectile and burst: 15 % bigger per level.
static func visual_scale(level: int) -> float:
	return 1.0 + 0.15 * clampi(level, 0, THRESHOLDS.size() - 1)
