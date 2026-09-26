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

## Emitted by UI when it takes over keyboard input (chat open) and releases it.
signal ui_input_capture_changed(captured: bool)

## The level's end trigger was reached.
signal level_completed()
