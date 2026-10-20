extends Node3D
## The castle world. Geometry comes from tools/generate_castle.py; this script
## only wires generic reactions (secrets, checkpoints) and adds the
## WorldObjectSync that keeps objects in step with the server and the
## DayNightCycle that lights the world from the school clock, and the
## SchoolBells that ring the timetable, and the MusicDirector that plays day or
## night music. Rooms are
## AreaZones (see gameplay/world/area_zone.gd) that other systems key off.

var world_object_sync: WorldObjectSync
var day_night: DayNightCycle
var bells: SchoolBells
var music: MusicDirector


func _ready() -> void:
	var batch := get_node_or_null("StaticBatch") as StaticBatch
	if batch != null:
		batch.flush()
	world_object_sync = WorldObjectSync.new()
	world_object_sync.name = "WorldObjectSync"
	add_child(world_object_sync)
	day_night = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	add_child(day_night)
	bells = SchoolBells.new()
	bells.name = "SchoolBells"
	add_child(bells)
	music = MusicDirector.new()
	music.name = "MusicDirector"
	music.cycle = day_night
	add_child(music)
	var boards := ClassroomBoards.new()
	boards.name = "ClassroomBoards"
	add_child(boards)
	var portraits := TalkingPortraits.new()
	portraits.name = "TalkingPortraits"
	add_child(portraits)
	var live_portraits := LivePortraits.new()
	live_portraits.name = "LivePortraits"
	add_child(live_portraits)
	var warden := NightWarden.new()
	warden.name = "NightWarden"
	add_child(warden)
	var cup := HouseCupDisplay.new()
	cup.name = "HouseCupDisplay"
	add_child(cup)
	var corners := DormitoryCorners.new()
	corners.name = "DormitoryCorners"
	add_child(corners)
	var echoes := EchoResidents.new()
	echoes.name = "EchoResidents"
	add_child(echoes)
	var garden := GardenBeds.new()
	garden.name = "GardenBeds"
	add_child(garden)
	var grounds_life := GroundsLife.new()
	grounds_life.name = "GroundsLife"
	add_child(grounds_life)
	var seasons := Seasons.new()
	seasons.name = "Seasons"
	add_child(seasons)
	var schedule := CastleSchedule.new()
	schedule.name = "CastleSchedule"
	add_child(schedule)
	var guardians := GuardianSync.new()
	guardians.name = "GuardianSync"
	add_child(guardians)
	var chase := LanternChase.new()
	chase.name = "LanternChase"
	add_child(chase)
	var detention := DetentionTasks.new()
	detention.name = "DetentionTasks"
	add_child(detention)
	var meals := FeastMeals.new()
	meals.name = "FeastMeals"
	add_child(meals)
	for wall in get_tree().get_nodes_in_group("secret_walls"):
		if wall is SecretWall:
			(wall as SecretWall).revealed.connect(func() -> void: GameEvents.notification_requested.emit(tr("NOTIFY_SECRET_PASSAGE"), 4.0))
	GameEvents.checkpoint_activated.connect(func(_c: Node) -> void: GameEvents.notification_requested.emit(tr("NOTIFY_CHECKPOINT"), 2.0))


## All named areas of the castle, for tests, tooling and future server-side maps.
func get_zones() -> Array[AreaZone]:
	var out: Array[AreaZone] = []
	for child in $Zones.get_children():
		if child is AreaZone:
			out.append(child)
	return out
