class_name Lamplighter
extends RefCounted
## The castle's lamplighting rule. Torches and chandeliers in rooms that daylight
## reaches (the generator marks them `daylit`: the room has a window) are put out
## after dawn and lit again at dusk; rooms without windows, the dungeons and the
## stairwells burn day and night. Each light has its own small delay so the castle
## goes dark and lights up room by room, as if someone walked round with a taper.
## A pure function of the school hour, so every client agrees without the server
## sending anything; a torch's own lit state (spells, the server) still applies on top.
## DayNightCycle calls apply() from its refresh.

const GROUP := &"lamplit"
## Daylight lights are snuffed from this school hour (plus their delay)…
const SNUFF_FROM := 7.0
## …and lit again from this one (dusk starts at 19:00).
const LIGHT_FROM := 19.0
## Largest per-light delay in school hours.
const STAGGER_HOURS := 0.75


## The delay (hours) of the light called `key`: the same on every client.
static func stagger_for(key: String) -> float:
	return float(absi(hash(key)) % 1000) / 1000.0 * STAGGER_HOURS


## Whether a daylit light with `stagger` burns at `hours`.
static func burns_at(hours: float, stagger: float) -> bool:
	var h := fposmod(hours, 24.0)
	return not (h >= SNUFF_FROM + stagger and h < LIGHT_FROM + stagger)


## Lights or snuffs every daylit light in the tree for `hours`.
static func apply(tree: SceneTree, hours: float) -> void:
	for light in tree.get_nodes_in_group(GROUP):
		light.call("set_lamp", burns_at(hours, float(light.get("lamp_stagger"))))
