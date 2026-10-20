# Logo and house crests: tool and prompts

Owner decision (2026-10-20): the logo and the four house crests are generated with AI (no commissioned artist). Art direction is "candlelit oak and parchment" (`docs/ui.md`).

## Tool: Recraft

Use **Recraft** (recraft.ai, model V3 or newer), on a paid plan so the outputs are yours to use commercially.

- **It exports real vectors (SVG).** Crests are shown from 24 px (chat, nameplates) to full-screen (sorting reveal, banners); SVG scales cleanly, and single-colour vector art can be recoloured in the engine (brass on oak, ink on parchment, house colour on robes).
- **It can lock a style.** Generate the first crest, pick the best one, then create a custom style from it ("Create style" with that image) and generate the other three in it. That is how four crests end up looking like one set.
- **It renders text well**, which matters for the wordmark.

**Used for the house crests (2026-10-20): ChatGPT image generation**, as PNG. It matched the style well; keep using it for regenerations so the set stays consistent, attaching the approved crests as reference images.

Back-ups: **Ideogram** for the wordmark if Recraft's lettering misbehaves; **Midjourney** (with `--sref` of the approved crest) only for painted, non-vector versions such as a loading screen.

**Recommended for the wordmark:** don't generate the letters. Typeset "Arcane Academy" in Cormorant SC (the game's display face) and generate only the emblem that sits with it. The lettering then matches the UI exactly and never comes out with a misspelt letter. Claude can typeset the wordmark as SVG from the font file.

**Copyright note.** Purely AI-generated images generally can't be protected by copyright, so others could copy them. To strengthen your position, edit the chosen SVGs by hand (simplify, redraw details, fix symmetry) in Recraft's editor, Figma or Inkscape, and register the logo as a **trademark** when you publish: a trademark doesn't depend on copyright.

## How to work

1. Generate the **school emblem** and one crest (start with **Drakoryn**) with the prompts below, 4–8 images each. Pick the best.
2. In Recraft, **create a style** from the chosen crest. Generate Grypheon, Phoenara and Hipporys in that style with the same prompt structure.
3. Ask for **vector / SVG**, square, on a plain background. Download the SVG and a 2048 px PNG.
4. Check each one against the rules below, then put the originals in `assets/ui/brand/source/` (`crest_1_drakoryn.png`, `crest_1_drakoryn_mono.png` … `crest_4_hipporys_mono.png`, `emblem.png`) and run `python3 tools/prep_crests.py` to make the game copies in `assets/ui/brand/` and write a provenance line in `assets/ui/PROVENANCE.md` (tool, model, prompt, date, chosen image). Steam's AI content disclosure needs it.

**Reject any image that:**
- looks like a shield split into four quarters, or any real university, school or film crest;
- contains a lion, eagle, badger, serpent or raven, or uses red + gold, blue + bronze, yellow + black or green + silver as a pairing;
- has letters, mottos or banners with text (we add text ourselves, in our font);
- shows a lightning bolt, wand-and-scar motif, round glasses, a sorting hat or a castle silhouette with a recognisable film shape.

## Shared style block

Paste this at the start of every crest prompt, unchanged, so the set stays consistent:

> Heraldic emblem for an original fantasy school of magic, engraved woodcut line art, fine crosshatching, bold clean silhouette that reads at small size, centred, symmetrical composition inside a circular seal frame with a thin double ring and small ornamental notches, flat vector illustration, limited palette, plain background, no text, no letters, no banner, no shield

House colours (from the game; each crest uses its colour plus aged brass `#C8A35A` and dark ink `#2B1D10`):

| House | Creature | Main colour |
|---|---|---|
| Drakoryn | dragon | emerald green `#33AD61` |
| Grypheon | griffin | amber gold `#EBB840` |
| Phoenara | phoenix | flame orange `#F26B2E` |
| Hipporys | hippocampus (winged sea-horse) | sapphire blue `#478CEB` |

## Crest prompts

**Drakoryn (dragon), house 1**
> [shared style block], a coiled dragon seen in profile, wings half raised, long tail curling around the inner ring, head turned toward the viewer, small flame breath forming a spiral, scales drawn with engraved lines, emerald green #33AD61 and aged brass #C8A35A on dark ink #2B1D10, proud and watchful mood

**Grypheon (griffin), house 2**
> [shared style block], a griffin rearing on its hind legs, eagle-like head and feathered wings spread wide, lion-like body with a tufted tail, one foreclaw raised holding a small key, feathers drawn with fine engraved strokes, amber gold #EBB840 and aged brass #C8A35A on dark ink #2B1D10, brave and noble mood

(The griffin is a hybrid; the eagle and lion parts are part of the creature, which is fine. Reject versions where it reads as a plain eagle or a plain lion.)

**Phoenara (phoenix), house 3**
> [shared style block], a phoenix rising with wings fully spread, long flowing tail feathers that turn into stylised flames curling around the inner ring, head lifted, a small sunburst behind it, engraved feather lines, flame orange #F26B2E and aged brass #C8A35A on dark ink #2B1D10, hopeful and fiery mood

**Hipporys (hippocampus), house 4**
> [shared style block], a hippocampus: the front of a horse with flowing mane and small feathered wings, its body ending in a curled fish tail with fins, rising from stylised waves at the bottom of the ring, engraved wave and scale lines, sapphire blue #478CEB and aged brass #C8A35A on dark ink #2B1D10, calm and wise mood

**Single-colour versions** (for icons, chat, nameplates, wax seals): rerun the chosen crest with
> same design as the reference, single colour only, solid dark ink #2B1D10 on plain white background, no gradients, simplified for 32 pixel size, thicker lines

## School emblem (for the logo)

> Emblem for an original fantasy school of magic called Arcane Academy, engraved woodcut line art, an open book with a small eight-pointed star rising from its pages, surrounded by a circular ring in which four creatures chase each other around the circle: a dragon, a griffin, a phoenix and a winged sea-horse with a fish tail, each creature in its own colour (emerald green #33AD61, amber gold #EBB840, flame orange #F26B2E, sapphire blue #478CEB), aged brass #C8A35A outlines on dark ink #2B1D10, symmetrical, bold silhouette, flat vector illustration, plain background, no text, no letters, no shield, no castle

Simpler alternative if the four creatures get muddy:
> Emblem for an original fantasy school of magic, engraved woodcut line art, an open book with an eight-pointed star rising from it, framed by a ring of laurel-like leaves with four small round medallions at the top, bottom, left and right, aged brass #C8A35A on dark ink #2B1D10, symmetrical, bold silhouette, flat vector illustration, plain background, no text, no letters, no shield

## Wordmark (only if you want the letters generated)

> Logo wordmark reading exactly "ARCANE ACADEMY" in elegant high-contrast classical serif small capitals, wide letter spacing, a thin engraved rule above and below with a tiny eight-pointed star in the centre, aged brass #C8A35A on dark ink #2B1D10, flat vector, plain background, no other text

Check the spelling letter by letter. The recommended route is still to typeset the wordmark in Cormorant SC and pair it with the emblem.
