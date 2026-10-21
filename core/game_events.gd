extends Node
## Global signal bus. Autoload: `GameEvents`.
##
## Exists so that loosely related systems (HUD, level objects, spawner, network)
## can react to gameplay events without holding references to each other.
## Only broadcast-style events belong here; direct object-to-object
## communication should use the objects' own signals.

## A local player instance entered the tree and is ready (HUD, camera, debug hook in).
signal local_player_spawned(player: Node)
## A local player instance is about to leave the tree.
signal local_player_removed(player: Node)

## Local player picked up a collectible.
signal collectible_collected(definition: Resource, total: int, max_total: int)
## Level reports how many collectibles of each id exist (for HUD "x / N").
signal collectible_total_changed(collectible_id: StringName, max_total: int)

## The local player touched a checkpoint.
signal checkpoint_activated(checkpoint: Node)
## The local player respawned at a transform.
signal player_respawned(player: Node)

## The local player learned a spell (HUD updates the equipped spell).
signal spell_learned(definition: Resource)

## Short informational message for the HUD (e.g. plaque text, "Learned Arcane Pulse").
signal notification_requested(text: String, duration: float)
## A mystery moved on for the local player: "clue" (a step with a hint) or "solved".
signal mystery_cue(cue: String)

## Emitted by UI when it takes over keyboard input (chat open) and releases it.
signal ui_input_capture_changed(captured: bool)

## The local player asked to be sorted (the Choosing Stone was used); the sorting panel opens.
signal sorting_requested()
## The local player's house changed (sorting or server profile); 0 = unsorted.
signal house_changed(house: int)

## The level's end trigger was reached.
signal level_completed()

## The local player walked into / out of a named castle area (see AreaZone).
signal area_entered(area_id: StringName, zone: Node)
signal area_exited(area_id: StringName, zone: Node)

## The school's time of day entered a new phase (SchoolClock.Phase: night, dawn, day,
## dusk). Emitted by the level's DayNightCycle, also once when it starts.
signal time_phase_changed(phase: int)

## Someone asked to see the timetable (a notice board, /plan): the panel opens.
signal timetable_requested()
## The school bell rang for a timetable entry: event "warn" (5 minutes before),
## "start" or "end"; entry as in Timetable.entries.
signal school_bell_rang(event: String, entry: Dictionary)

## Something asked for the character creator (first join, /look).
signal character_creator_requested()

## Someone opened a book: its title key and page keys (BookPanel shows it).
signal book_requested(title_key: String, page_keys: PackedStringArray)

## Something asked for one of the school-life panels by name ("riddle", "profile",
## "friends", "clubs", "shop", "game"…) with its arguments; the panel opens itself.
signal panel_requested(panel: String, args: Dictionary)

## The local player's spell hit another player (only a duel makes that count).
signal spell_hit_player(peer_id: String, spell_id: StringName)
