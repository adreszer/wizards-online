# UI art provenance

Every generated UI image, with where it came from. Steam's AI content disclosure draws on this list.

## House crests (`brand/`)

Generated with AI by the owner on 2026-10-20, from the prompts in `docs/brand-prompts.md`. No human artwork. The as-generated originals are in `brand/source/`. `tools/prep_crests.py` makes the game copies (1024 px, background removed; mono crests as a white glyph on alpha, tinted in the engine).

| File | Generated as | Source name |
|---|---|---|
| crest_1_drakoryn | colour | Zielony smok w heraldycznym medalionie |
| crest_1_drakoryn_mono | single colour | Heraldyczna pieczęć smoka z płomieniem |
| crest_2_grypheon | colour | Złoty gryf z kluczem w herbowym medalionie |
| crest_2_grypheon_mono | single colour | Heraldyczny gryf z kluczem w kręgu |
| crest_3_phoenara | colour | Ornamental feniks w płomieniach |
| crest_3_phoenara_mono | single colour | Symetryczny emblemat feniksa w płomieniach |
| crest_4_hipporys | colour | Złoty hipokamp w heraldycznym medalionie |
| crest_4_hipporys_mono | single colour | Monochromatyczny emblemat hippocampusa w falach |

Tool: ChatGPT (OpenAI image generation), owner account, 2026-10-20.

## House banners (`assets/models/environment/modular/banner_hN.glb`)

Repainted 2026-10-20 by `tools/make_banners.py`: the damask weave from the first banner batch (`brand/source/banner_damask.jpg`, the Hipporys banner of that batch; see the third props batch in `docs/plan.md`), tinted in the house colour, with a brass border and the colour crest above. No new generated art beyond the crests.
