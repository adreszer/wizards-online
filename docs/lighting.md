# Lighting

How the castle is lit, why, and how to measure it. Roadmap 5.1; built in the lighting overhaul (plan.md, "Lighting overhaul").

## The setup

- **Global illumination: SDFGI**, as the "Global illumination" setting (on in the high and ultra presets, off in low and medium). The castle's environment asks for it (`tools/castle/build.py`, `SCENE_ENV`); `GameSettings.apply` only turns it on where the level asks for it, so portrait studios and other sub-viewports never pay for it.
- **AgX tonemapping and glow** in the castle environment. Glow picks up candle flames, chandeliers and lit windows (HDR threshold 1.2).
- **Darkness is real.** With GI on, SDFGI replaces the flat ambient light: a room is lit by its candles, torches and windows, and by what players carry. Without GI, `DayNightCycle` cuts the ambient indoors to `INDOOR_AMBIENT` (35 %), by area kind (`OPEN_AIR_KINDS` are outdoors). The dungeon atmosphere halves the ambient again and takes away the daylight fill, so the dungeons are dark at any hour.
- **Daylight indoors.** The `Sun` fill shines straight down, so daylight in a room comes from above and no wall is lit more than the one facing it. With GI on it is five times stronger (`FILL_GI`), and five shadowless "bounce fills" (four horizontal, one up; interiors only, no highlights) stand in for the light walls and ceilings would get from the whole room. Window panes glow brighter by day (`WallWindow.GLASS_DAY_ENERGY_GI`) and feed the GI. The fill lights carry the `GameSettings.NO_SHADOWS` meta, so the shadows setting never gives them shadows (it used to, which blocked the old fill at every ceiling).
- **Daylight outdoors.** The `Moon` light (outdoor layer only) is the sun by day at `SUN_ENERGY` 2.0. By day the sky is brighter (`DAY_SKY_ENERGY`, 1.5× at full daylight): with GI on, the sky is what lights the grounds' shaded sides and what comes in through doors. Without GI, the flat ambient under the open sky is `OUTDOOR_DAY_AMBIENT` (1.9×) stronger by day (`DayNightCycle.outdoor_day_boost`). The overhead `Sun` fill lights interiors only (it washed the terrain out). Outdoors by day the colour saturation rises to `OUTDOOR_DAY_SATURATION` (1.3; AgX bleaches sunlit grass to mint otherwise), the day fog is thinner (0.0008) and the terrain has a low specular (no pale sky sheen at grazing angles). Indoors and at night nothing changes. Before this the grounds were lit by a 1.25 sun and the indoor-strength ambient, which read as dusk or night under AgX. Dusk and night keep their keys (`KEYS`). GI off (low/medium) looks the same as GI on outdoors (checked with `capture_model --no-gi`).
- **Windows and light shafts.** Every glazed `WallWindow` gets a fake light shaft: the four open sides of a prism from the opening into the room, drawn additive and unshaded (`light_shaft.gdshader`): brightest at the window, soft at its edges, faded near the camera. **It follows the sun:** `DayNightCycle` hands the sun's (by night the moon's) light direction to `WallWindow.set_shaft_light`, one uniform on the shared material. In the shader the far end is pushed along that direction (a high sun: short steep shafts; a low sun: long flat ones, `SHAFT_DROP`, `SHAFT_MAX_REACH`), and only windows whose room the light shines into (horizontal light direction · the window's inward normal > 0.2, `shaft_facing`) show one; the others collapse to a point and cost no fill. By day warm, by night a faint blue moonbeam, fading with the body at the horizon. **Cost:** the shafts of a level share one unit mesh and are batched into a MultiMesh per 32 m cell and storey (`build_shaft_batches`, 147 draws in the whole castle), drawn out to 40 m. No real light and no shadow. Measured with `tools/perf_castle.tscn -- --hour=12` (and `--no-shafts`): corridor_w_0 9,601 → 9,610 draw calls, stair_hall_top 3,274 → 3,287 (a first try with 16 m cells cost +369/+379).
- **The light budget (`LightQuality`).** Every omni and spot light fades out from 45 m to 55 m from the camera. Only lights authored with a shadow (wall torches, chandeliers, held torches) cast one, and only out to the preset's shadow distance (medium 12 m, high 20 m, ultra 30 m, fade included; none on low or with shadows off). Particles never cast shadows.

## Rules for content

- **Anything that moves every frame must not cast a shadow** unless it's a character. A moving shadow caster makes every shadowed light around it re-render its shadow (six cube faces) every frame. Bobbing tomes, collectibles, floating candles and spinning practice discs are set to `cast_shadow = 0`. Players, NPCs and creatures keep their shadows: that cost is what the shadow distance bounds.
- New placed lights need nothing special: `LightQuality` configures every light as it enters the tree. Author `shadow_enabled = true` only on lights that should cast shadows when near.
- Directional lights that stand in for sky or bounce light get `set_meta(GameSettings.NO_SHADOWS, true)`.

## The spike (2026-10-20)

Measured with `tools/lighting_spike.tscn` on an M3 Ultra (Metal, Forward+), 1600×900 window, seven views (great hall, entrance hall, west corridor, library, a classroom, the dungeon corridor, the cellars) at midnight and noon.

| Option | Result |
|---|---|
| **LightmapGI** (bake) | Rejected without a bake test. Every torch and chandelier can be put out by spells and the Lamplighter, the day/night cycle moves the sky light, the castle is regenerated often, and `StaticBatch` merges meshes at runtime. A bake would be stale or wrong for most of the day, and it would need lightmap UVs on every imported model. |
| **VoxelGI** per wing | Rejected. A runtime bake of one 72 × 24 × 72 m region took **26 s**, and baking in the editor doesn't work for a generated castle. |
| **SSIL** (screen-space) | Kept as its own ultra setting. It brightens locally but keeps the flat ambient, so dark stays grey. |
| **SDFGI** | **Chosen.** No bake, works with the generator and the day/night cycle, and dynamic lights feed it. On this machine it cost no measurable frame time (the castle is CPU-bound here even at 2× render scale), so its GPU cost on a mid laptop still has to be measured on one. |
| Sun through the windows (shadowed sun on interiors) | Rejected for now. The windows are too small (the great hall is nearly black at noon), and the sun's shadow pass cost ~8,300 draw calls. It belongs to the "windows and light shafts" item. |

**Shadows were the real cost.** Before the overhaul, 85–90 % of all draw calls were shadow passes: 676 shadowed omni lights, many re-rendering every frame because a bobbing prop or sparkle sat in their range. Great hall at night: **6,926 → 1,542 draw calls** (shadow draws 6,044 → 660). Entrance hall: 4,251 → 0 shadow draws (nothing moves there, so shadows stay cached). Rooms where animated characters walk (crystal guardians, the night warden) still re-render the shadows of the few lights near them, as they should.

### Measuring

```
godot --always-on-top --path . tools/lighting_spike.tscn -- --out=/abs/dir --modes=sdfgi --lights=game
godot --always-on-top --path . tools/lighting_spike.tscn -- --out=/abs/dir --modes=base --lights=movers --views=classroom
godot --always-on-top --path . tools/capture_daynight.tscn -- --out=/abs/dir
godot --always-on-top --path . tools/capture_model.tscn -- --scene=res://levels/castle/castle.tscn --out=/abs/dir --eye=28,1.8,46 --target=28,2,10 --frames=60 --hours=12,18.8,0
```

`--lights=movers` lists the shadow casters that animate near a view (the cause of per-frame shadow re-renders). `--always-on-top` matters: macOS throttles a hidden Godot window, and the numbers and pictures go stale. `capture_daynight` runs the real game with a player, so the per-area rules (indoors, the dungeon atmosphere) apply.

## Next

- Measure SDFGI on a mid laptop at 1080p; if it costs more than ~3 ms, consider fewer cascades or half resolution (`rendering/global_illumination/sdfgi/*`) before moving it to ultra only.
- Windows and light shafts, next steps: bigger and stained-glass windows, then a shadowed sun and volumetric fog through them.
- Wall torches could use dual-paraboloid shadows (2 passes instead of 6); the wall behind them hides the seam.
