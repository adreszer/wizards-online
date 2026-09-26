#!/usr/bin/env python3
"""Generates levels/mvp/mvp_level.tscn (greybox floors + modular wall runs).
Run from the project root:  python3 tools/generate_level.py
The output is a normal scene, fully editable in the Godot editor; re-running
this script overwrites it, so hand edits belong in objects/, not the level.
"""
import math

ext = {}
def ext_id(kind, path):
    key = (kind, path)
    if key not in ext:
        ext[key] = len(ext) + 1
    return ext[key]

nodes = []
def xf(pos, rot_y=0.0):
    c = math.cos(rot_y); s = math.sin(rot_y)
    return f'Transform3D({c:.6f}, 0, {s:.6f}, 0, 1, 0, {-s:.6f}, 0, {c:.6f}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})'

def block(name, center, size, color=(0.55, 0.52, 0.6), parent="Geometry"):
    i = ext_id("PackedScene", "res://objects/greybox/greybox_block.tscn")
    nodes.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{i}")]\n'
                 f'transform = {xf(center)}\n'
                 f'size = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n'
                 f'color = Color({color[0]:.3f}, {color[1]:.3f}, {color[2]:.3f}, 1)\n')

def inst(name, path, pos, parent=".", rot_y=0.0, props=None):
    i = ext_id("PackedScene", path)
    body = f'[node name="{name}" parent="{parent}" instance=ExtResource("{i}")]\ntransform = {xf(pos, rot_y)}\n'
    for k, v in (props or {}).items():
        body += f'{k} = {v}\n'
    nodes.append(body)

def wall_run(name, start, length, rot_y=0.0, rows=None):
    """A modular wall from `start` (floor level, run origin) along the rotated +X for
    `length` metres, stacked in 4 m rows up to WALL_H (castle-height rooms)."""
    if rows is None:
        rows = int(round(WALL_H / MODULE_H))
    for r in range(rows):
        suffix = "" if r == 0 else f"_Row{r + 1}"
        inst(name + suffix, "res://objects/environment/modular/modular_wall_run.tscn",
             (start[0], start[1] + r * MODULE_H, start[2]), parent="Walls", rot_y=rot_y,
             props={"length": f"{length:.3f}"})

def pillar(name, x, z, top):
    inst(name, "res://objects/environment/modular/pillar.tscn", (x, top, z), parent="Pillars")

def room_pillars(name, x0, x1, z0, z1, top, mid=True):
    """Corner pillars plus one every PILLAR_SPACING metres along the side walls."""
    zs = [z1, z0]
    if mid:
        z = z1 - PILLAR_SPACING
        while z > z0 + 2.0:
            zs.append(z)
            z -= PILLAR_SPACING
    for i, z in enumerate(zs):
        pillar(f"{name}_PL{i}", x0, z, top)
        pillar(f"{name}_PR{i}", x1, z, top)

def ceiling(name, x0, x1, z0, z1, y):
    inst(name, "res://objects/environment/modular/modular_floor.tscn", (x0, y, z0), parent="Ceilings",
         props={"size_x": f"{x1 - x0:.3f}", "size_z": f"{z1 - z0:.3f}",
                "module_scene": f'ExtResource("{ext_id("PackedScene", "res://objects/environment/modular/ceiling_tile.tscn")}")'})

FLOOR = (0.42, 0.40, 0.47); WALL = (0.55, 0.52, 0.6); ACCENT = (0.62, 0.55, 0.7); LINTEL = (0.5, 0.46, 0.55)
WALL_H = 8.0; MODULE_H = 4.0; T = 0.35; OPEN_H = 3.6
PILLAR_SPACING = 8.0

# Floor tile variants: wrapper scene -> slab thickness (from the wrapper's collision box).
FLOOR_TILES = {
    "plain": ("res://objects/environment/modular/floor_tile.tscn", 0.46),
    "ornate": ("res://objects/environment/modular/floor_tile_2.tscn", 0.22),
}
def floor(name, x0, x1, z0, z1, top, color=FLOOR, thick=1.0, tile="plain"):
    """Modular floor tiles with their top at `top`, over a greybox sub-floor that
    hides the void under raised areas (ledge faces, pit walls)."""
    scene, tile_thick = FLOOR_TILES[tile]
    props = {"size_x": f"{x1 - x0:.3f}", "size_z": f"{z1 - z0:.3f}"}
    if tile != "plain":
        props["module_scene"] = f'ExtResource("{ext_id("PackedScene", scene)}")'
    inst(name, "res://objects/environment/modular/modular_floor.tscn", (x0, top, z0), parent="Floors", props=props)
    sub_top = top - tile_thick
    sub_thick = max(0.2, thick - tile_thick)
    block(name + "_Sub", ((x0 + x1) / 2, sub_top - sub_thick / 2, (z0 + z1) / 2), (x1 - x0, sub_thick, z1 - z0), color)

# Walls are placed with their centre line on the room boundary (x0 / x1 / z), so a
# wall's inner face sits T/2 inside the boundary. Side walls run along -Z; a run
# rotated +90° about Y points its local +X toward -Z.
def side_walls(name, x0, x1, z0, z1, top):
    wall_run(name + "_WL", (x0, top, z1), z1 - z0, math.radians(90))
    wall_run(name + "_WR", (x1, top, z1), z1 - z0, math.radians(90))

def end_wall(name, x0, x1, z, top, opening=None, open_h=OPEN_H):
    """End wall along X at `z`. With an opening, a 4 m doorway module replaces the
    wall segment centred on the opening (the arch is ~3.8 m wide × 3.8 m tall) and
    the upper wall rows run full width above it."""
    if opening is None:
        wall_run(name, (x0, top, z), x1 - x0, 0.0)
        return
    cx = (opening[0] + opening[1]) / 2
    wall_run(name + "_L", (x0, top, z), (cx - 2.0) - x0, 0.0, rows=1)
    wall_run(name + "_R", (cx + 2.0, top, z), x1 - (cx + 2.0), 0.0, rows=1)
    inst(name + "_Doorway", "res://objects/environment/modular/doorway.tscn", (cx, top, z), parent="Walls")
    upper_rows = int(round(WALL_H / MODULE_H)) - 1
    for r in range(upper_rows):
        wall_run(name + f"_Row{r + 2}", (x0, top + (r + 1) * MODULE_H, z), x1 - x0, 0.0, rows=1)

DOOR = (-1.8, 1.8)
# ---------------- Entrance chamber  z[-18.5, 3]
floor("Entrance_FloorLow", -8, 8, -10, 3, 0.0)
floor("Entrance_FloorHigh", -8, 8, -18.5, -10, 1.2, thick=2.2)
block("Entrance_Step1", (-6.5, 0.2, -8.95), (3, 0.4, 0.7), ACCENT)
block("Entrance_Step2", (-6.5, 0.4, -9.65), (3, 0.8, 0.7), ACCENT)
side_walls("Entrance", -8, 8, -18.5, 3, 0.0)
end_wall("Entrance_Back", -8, 8, 3, 0.0)
end_wall("Entrance_Front", -8, 8, -18.5, 1.2, DOOR)
block("Entrance_FrontLowFill", (0, 0.6, -18.5), (16.5, 1.2, T), WALL)
inst("EntranceDoor", "res://objects/puzzles/magic_door.tscn", (0, 1.2, -18.5))
inst("EntranceLever", "res://objects/interactables/lever.tscn", (5.5, 1.2, -16.5), rot_y=math.radians(90))
inst("EntrancePlaque", "res://objects/interactables/plaque.tscn", (-7.6, 1.6, -2), rot_y=math.radians(90),
     props={"text": '"Welcome, apprentice. The halls reward those who look closely. Purple glimmers answer to magic."'})
room_pillars("Entrance", -8, 8, -18.5, 3, 0.0)
ceiling("Entrance_Ceiling", -8, 8, -18.5, 3, WALL_H)
# ---------------- Corridor z[-45,-18.5], x[-3,3], top 1.2
floor("Corridor_Floor", -3, 3, -45, -18.5, 1.2, thick=2.2)
wall_run("Corridor_WL", (-3, 1.2, -18.5), 26.5, math.radians(90))
wall_run("Corridor_WR_A", (3, 1.2, -18.5), 11.5, math.radians(90))   # z[-30,-18.5]
wall_run("Corridor_WR_B", (3, 1.2, -34), 11.0, math.radians(90))     # z[-45,-34]
block("Corridor_WR_Top", (3, 4.9, -32), (T, 0.6, 4), WALL)           # fills 4.6..5.2 above the 3.4 m secret wall
inst("SecretWall", "res://objects/puzzles/secret_wall.tscn", (3, 1.2, -32), rot_y=math.radians(-90))
inst("CorridorCheckpoint", "res://gameplay/checkpoints/checkpoint.tscn", (0, 1.2, -21))
inst("Fragment_Corridor", "res://gameplay/collectibles/collectible.tscn", (0, 2.0, -40))
block("Corridor_Ledge", (0, 1.6, -40), (2, 0.8, 2), ACCENT)
room_pillars("Corridor", -3, 3, -45, -18.5, 1.2, mid=False)
ceiling("Corridor_Ceiling", -3, 3, -45, -18.5, 1.2 + WALL_H)
# Secret room x[3.5,11.5] z[-36,-28]
floor("Secret_Floor", 3.5, 11.5, -36, -28, 1.2, color=(0.35, 0.3, 0.45), thick=2.2, tile="ornate")
wall_run("Secret_WR", (11.5, 1.2, -28), 8.0, math.radians(90))
wall_run("Secret_WN", (3.5, 1.2, -28), 8.0, 0.0)
wall_run("Secret_WS", (3.5, 1.2, -36), 8.0, 0.0)
for i, (x, z) in enumerate([(6, -30), (9.5, -32), (6, -34)]):
    inst(f"Fragment_Secret{i+1}", "res://gameplay/collectibles/collectible.tscn", (x, 1.2, z))
room_pillars("Secret", 3.5, 11.5, -36, -28, 1.2, mid=False)
ceiling("Secret_Ceiling", 3.5, 11.5, -36, -28, 1.2 + WALL_H)
inst("SecretPlaque", "res://objects/interactables/plaque.tscn", (11.1, 2.4, -32), rot_y=math.radians(-90),
     props={"text": '"Well found. Curiosity is the first lesson."'})
# ---------------- Training room z[-65,-45] x[-8,8]
end_wall("Training_Back", -8, 8, -45, 1.2, (-1.6, 1.6), open_h=OPEN_H)
floor("Training_Floor", -8, 8, -65, -45, 1.2, thick=2.2, tile="ornate")
side_walls("Training", -8, 8, -65, -45, 1.2)
end_wall("Training_Front", -8, 8, -65, 1.2, DOOR)
inst("TrainingCheckpoint", "res://gameplay/checkpoints/checkpoint.tscn", (0, 1.2, -47.5))
inst("SpellTome", "res://objects/interactables/spell_tome.tscn", (0, 1.2, -52))
inst("TrainingPlaque", "res://objects/interactables/plaque.tscn", (-7.6, 2.4, -52), rot_y=math.radians(90),
     props={"text": '"Wake both crystals to pass. Aim through the centre of your sight."'})
inst("TrainingSwitchA", "res://objects/puzzles/magic_switch.tscn", (-5.5, 1.2, -62))
block("Training_Pedestal", (5.5, 2.2, -62), (1.6, 2.0, 1.6), ACCENT)
inst("TrainingSwitchB", "res://objects/puzzles/magic_switch.tscn", (5.5, 3.2, -62))
inst("TrainingDoor", "res://objects/puzzles/magic_door.tscn", (0, 1.2, -65))
inst("Fragment_Training", "res://gameplay/collectibles/collectible.tscn", (-6, 1.2, -56))
room_pillars("Training", -8, 8, -65, -45, 1.2)
ceiling("Training_Ceiling", -8, 8, -65, -45, 1.2 + WALL_H)
# ---------------- Puzzle chamber z[-90,-65]
floor("Puzzle_Floor", -8, 8, -90, -65, 1.2, thick=2.2)
side_walls("Puzzle", -8, 8, -90, -65, 1.2)
end_wall("Puzzle_Mid", -8, 8, -78, 1.2, DOOR)
end_wall("Puzzle_Front", -8, 8, -90, 1.2, DOOR)
inst("PuzzleCheckpoint", "res://gameplay/checkpoints/checkpoint.tscn", (0, 1.2, -67.5))
block("Puzzle_SwitchShelf", (-6.5, 3.4, -76.5), (2.0, 0.4, 2.0), ACCENT)
inst("PuzzleSwitch", "res://objects/puzzles/magic_switch.tscn", (-6.5, 3.6, -76.5))
inst("PuzzlePlaque", "res://objects/interactables/plaque.tscn", (7.6, 2.4, -70), rot_y=math.radians(-90),
     props={"text": '"What is out of reach may still be touched. Weight holds the far door."'})
inst("PuzzleGate", "res://objects/puzzles/magic_door.tscn", (0, 1.2, -78))
inst("PushableBlock", "res://objects/puzzles/pushable_block.tscn", (4, 1.95, -82))
inst("PressurePlate", "res://objects/puzzles/pressure_plate.tscn", (-3.5, 1.2, -86))
inst("PuzzleDoor", "res://objects/puzzles/magic_door.tscn", (0, 1.2, -90))
inst("Fragment_Puzzle", "res://gameplay/collectibles/collectible.tscn", (6, 1.2, -87))
room_pillars("Puzzle", -8, 8, -90, -65, 1.2)
ceiling("Puzzle_Ceiling", -8, 8, -90, -65, 1.2 + WALL_H)
# ---------------- Platforming chamber z[-130,-90]
floor("Plat_Entry", -8, 8, -94, -90, 1.2, thick=2.2)
floor("Plat_Exit", -8, 8, -130, -126, 1.2, thick=2.2)
floor("Plat_PitFloor", -8, 8, -126, -94, -6.0, color=(0.2, 0.15, 0.25))
side_walls("Plat", -8, 8, -130, -90, 1.2)
block("Plat_WL_Low", (-8, -2.5, -110), (T, 7.4, 40.5), WALL); block("Plat_WR_Low", (8, -2.5, -110), (T, 7.4, 40.5), WALL)
end_wall("Plat_Front", -8, 8, -130, 1.2, (-1.8, 1.8))
inst("PlatCheckpoint", "res://gameplay/checkpoints/checkpoint.tscn", (0, 1.2, -91.5))
inst("PitKillZone", "res://gameplay/checkpoints/kill_zone.tscn", (0, -4.5, -110))
plats = [("P1", (-3, 1.2, -98), (3, 1, 3)), ("P2", (1, 1.6, -102), (3, 1, 3)), ("P3", (-2, 2.0, -106), (3, 1, 3)), ("P4", (-2, 2.0, -123), (4, 1, 4))]
for n, c, s in plats:
    block("Plat_" + n, (c[0], c[1] - s[1] / 2, c[2]), s, (0.35, 0.55, 0.65))
inst("MovingPlatform1", "res://objects/platforms/moving_platform.tscn", (2, 1.8, -110),
     props={"points": "Array[Vector3]([Vector3(0, 0, -9)])", "speed": "2.2", "size": "Vector3(3, 0.4, 3)"})
inst("Fragment_Plat1", "res://gameplay/collectibles/collectible.tscn", (1, 1.6, -102))
inst("Fragment_Plat2", "res://gameplay/collectibles/collectible.tscn", (-2, 2.0, -106))
inst("Fragment_Plat3", "res://gameplay/collectibles/collectible.tscn", (0, 0.2, 0), parent="MovingPlatform1")
inst("CursedFloor", "res://gameplay/checkpoints/damage_zone.tscn", (0, 1.2, -128), props={"damage_on_enter": "20", "damage_per_tick": "10"})
room_pillars("Plat", -8, 8, -130, -90, 1.2, mid=False)
ceiling("Plat_Ceiling", -8, 8, -130, -90, 1.2 + WALL_H)
inst("PlatPlaque", "res://objects/interactables/plaque.tscn", (-7.6, 2.4, -92), rot_y=math.radians(90),
     props={"text": '"Mind the drop. The crimson floor bites; leap it."'})
# ---------------- Final puzzle z[-155,-130]
floor("Final_Floor", -8, 8, -155, -130, 1.2, thick=2.2)
side_walls("Final", -8, 8, -155, -130, 1.2)
end_wall("Final_Front", -8, 8, -155, 1.2, DOOR)
inst("FinalCheckpoint", "res://gameplay/checkpoints/checkpoint.tscn", (0, 1.2, -132.5))
for i, (x, z, st) in enumerate([(-4, -140, 1), (0, -142, 2), (4, -140, 3)]):
    inst(f"Statue{i+1}", "res://objects/puzzles/rotating_statue.tscn", (x, 1.2, z), props={"initial_state": str(st)})
inst("FinalPlaque", "res://objects/interactables/plaque.tscn", (-7.6, 2.4, -136), rot_y=math.radians(90),
     props={"text": '"Turn every gaze upon the far door, then pull the lever."'})
inst("FinalLever", "res://objects/interactables/lever.tscn", (6, 1.2, -151), rot_y=math.radians(-90), props={"one_shot": "false"})
inst("FinalDoor", "res://objects/puzzles/magic_door.tscn", (0, 1.2, -155))
inst("Fragment_Final", "res://gameplay/collectibles/collectible.tscn", (0, 1.2, -149))
room_pillars("Final", -8, 8, -155, -130, 1.2)
ceiling("Final_Ceiling", -8, 8, -155, -130, 1.2 + WALL_H)
# ---------------- Reward room z[-170,-155] x[-6,6]
floor("Reward_Floor", -6, 6, -170, -155, 1.2, color=(0.5, 0.42, 0.3), thick=2.2, tile="ornate")
side_walls("Reward", -6, 6, -170, -155, 1.2)
end_wall("Reward_Back", -6, 6, -170, 1.2)
block("Reward_Pedestal", (0, 1.6, -165), (2, 0.8, 2), (0.7, 0.6, 0.35))
inst("Fragment_Reward", "res://gameplay/collectibles/collectible.tscn", (0, 2.0, -165))
room_pillars("Reward", -6, 6, -170, -155, 1.2, mid=False)
ceiling("Reward_Ceiling", -6, 6, -170, -155, 1.2 + WALL_H)
inst("RewardPlaque", "res://objects/interactables/plaque.tscn", (0, 2.4, -169.6),
     props={"text": '"You have reached the end of the vertical slice. Thank you for playing."'})

lights = []
for i, z in enumerate([-4, -14, -24, -40, -32, -50, -60, -70, -85, -96, -108, -120, -135, -148, -162]):
    lights.append(f'[node name="Torch{i}" type="OmniLight3D" parent="Lights"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 4.5, {z})\nlight_color = Color(1, 0.85, 0.65, 1)\nlight_energy = 2.6\nomni_range = 24.0\nshadow_enabled = true\n')
lights.append('[node name="SecretLight" type="OmniLight3D" parent="Lights"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 7.5, 4, -32)\nlight_color = Color(0.7, 0.5, 1, 1)\nlight_energy = 1.4\nomni_range = 12.0\n')

statue_script = ext_id("Script", "res://objects/puzzles/statue_puzzle.gd")
level_script = ext_id("Script", "res://levels/mvp/mvp_level.gd")
end_script = ext_id("Script", "res://levels/mvp/level_end.gd")

exts = ""
for (kind, path), i in sorted(ext.items(), key=lambda kv: kv[1]):
    exts += f'[ext_resource type="{kind}" path="{path}" id="{i}"]\n'
subs = '''
[sub_resource type="Environment" id="Env"]
background_mode = 1
background_color = Color(0.06, 0.05, 0.1, 1)
ambient_light_source = 2
ambient_light_color = Color(0.45, 0.4, 0.6, 1)
ambient_light_energy = 0.9
tonemap_mode = 2
fog_enabled = true
fog_light_color = Color(0.25, 0.2, 0.35, 1)
fog_density = 0.004

[sub_resource type="BoxShape3D" id="EndShape"]
size = Vector3(12, 4, 2)
'''
root = f'''
[node name="MvpLevel" type="Node3D" node_paths=PackedStringArray("entrance_lever", "entrance_door", "training_switch_a", "training_switch_b", "training_door", "puzzle_switch", "puzzle_gate", "puzzle_plate", "puzzle_door", "statue_puzzle", "final_lever", "final_door", "secret_wall")]
script = ExtResource("{level_script}")
entrance_lever = NodePath("EntranceLever")
entrance_door = NodePath("EntranceDoor")
training_switch_a = NodePath("TrainingSwitchA")
training_switch_b = NodePath("TrainingSwitchB")
training_door = NodePath("TrainingDoor")
puzzle_switch = NodePath("PuzzleSwitch")
puzzle_gate = NodePath("PuzzleGate")
puzzle_plate = NodePath("PressurePlate")
puzzle_door = NodePath("PuzzleDoor")
statue_puzzle = NodePath("StatuePuzzle")
final_lever = NodePath("FinalLever")
final_door = NodePath("FinalDoor")
secret_wall = NodePath("SecretWall")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 20, 0)
light_color = Color(0.8, 0.8, 1, 1)
light_energy = 0.15
shadow_enabled = false

[node name="StartPoint" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0.05, 0)

[node name="Geometry" type="Node3D" parent="."]

[node name="Floors" type="Node3D" parent="."]

[node name="Walls" type="Node3D" parent="."]

[node name="Pillars" type="Node3D" parent="."]

[node name="Ceilings" type="Node3D" parent="."]

[node name="Lights" type="Node3D" parent="."]

'''
tail = f'''
[node name="StatuePuzzle" type="Node" parent="." node_paths=PackedStringArray("statues")]
script = ExtResource("{statue_script}")
statues = [NodePath("../Statue1"), NodePath("../Statue2"), NodePath("../Statue3")]
required_states = Array[int]([0, 0, 0])

[node name="LevelEnd" type="Area3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.5, -160)
collision_layer = 0
collision_mask = 2
script = ExtResource("{end_script}")

[node name="Shape" type="CollisionShape3D" parent="LevelEnd"]
shape = SubResource("EndShape")
'''
header = f'[gd_scene load_steps={len(ext) + 3} format=3 uid="uid://mvplevel00001"]\n\n'
out = header + exts + subs + root + "\n".join(nodes) + "\n" + "\n".join(lights) + tail
open("levels/mvp/mvp_level.tscn", "w").write(out)
print("level nodes:", len(nodes))
