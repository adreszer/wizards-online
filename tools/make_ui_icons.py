"""Fetches the placeholder icon set (docs/ui.md, Milestone 66) from game-icons.net
(https://game-icons.net, CC BY 3.0; the SVG sources on GitHub, game-icons/icons) and
writes one DPITexture per icon into assets/ui/icons/<id>.tres: the white glyph alone
(the black square behind it removed), 64 px at 1x, drawn sharp at any scale and tinted
in the engine. assets/ui/icons/CREDITS.md lists each icon's author for the credits.

  python3 tools/make_ui_icons.py

Code asks UiIcons for an id, never for a file, so the final Recraft set (Milestone 72)
replaces these by writing the same ids.
"""
import os
import re
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "icons")
BASE = "https://raw.githubusercontent.com/game-icons/icons/master/"
SIZE = 64

# id -> game-icons path (author/name).
ICONS = {
    # HUD and windows
    "health": "lorc/heart-bottle",
    "coins": "delapouite/coins",
    "fragment": "lorc/crystal-growth",
    "day": "lorc/sun",
    "night": "lorc/moon",
    "time": "lorc/sundial",
    "map": "lorc/treasure-map",
    "satchel": "lorc/knapsack",
    "journal": "lorc/open-book",
    "book": "delapouite/book-cover",
    "timetable": "delapouite/calendar",
    "settings": "lorc/cog",
    "cooldown": "lorc/hourglass",
    "spell": "lorc/magic-swirl",
    "wand": "lorc/fairy-wand",
    "broom": "delapouite/broom",
    "house_points": "delapouite/trophy-cup",
    "bell": "lorc/ringing-bell",
    "exit": "delapouite/exit-door",
    "person": "delapouite/person",
    "professor": "lorc/pointy-hat",
    "shop": "delapouite/chest",
    "cauldron": "lorc/cauldron",
    "castle": "lorc/castle",
    "compass": "lorc/compass",
    "candle": "lorc/candle-light",
    "lantern": "lorc/lantern",
    # Toasts
    "info": "delapouite/info",
    "warning": "lorc/hazard-sign",
    "check": "delapouite/check-mark",
    "learned": "delapouite/sparkles",
    "discovery": "lorc/magnifying-glass",
    "quest": "lorc/scroll-unfurled",
    "homework": "delapouite/scroll-quill",
    "secret": "lorc/key",
    "locked": "lorc/padlock",
    # Chat channels
    "chat": "delapouite/chat-bubble",
    "chat_say": "lorc/conversation",
    "chat_whisper": "lorc/lips",
    "chat_shout": "delapouite/megaphone",
    "chat_house": "delapouite/family-house",
    "chat_dm": "lorc/envelope",
    # Subjects
    "subject_charms": "lorc/magic-palm",
    "subject_transfiguration": "lorc/star-swirl",
    "subject_potions": "lorc/potion-ball",
    "subject_defence": "lorc/checked-shield",
    "subject_herbology": "delapouite/plant-roots",
    "subject_astronomy": "delapouite/telescope",
    "subject_history": "lorc/tied-scroll",
    "subject_flying": "lorc/feather",
    "subject_creatures": "lorc/owl",
    "subject_divination": "lorc/crystal-ball",
    "subject_arithmancy": "delapouite/abacus",
    "subject_runes": "lorc/rune-stone",
    # Spells, by effect (SpellSlot picks "spell_<effect_type>")
    "spell_force": "lorc/energy-arrow",
    "spell_fire": "lorc/burning-embers",
    "spell_frost": "lorc/snowflake-1",
    "spell_light": "lorc/sun-radiations",
    "spell_wind": "lorc/whirlwind",
    "spell_water": "sbed/water-drop",
    "spell_growth": "lorc/sprout",
    "spell_mend": "delapouite/healing",
    "spell_unlock": "delapouite/padlock-open",
    "spell_levitate": "lorc/lift",
    "spell_dark": "lorc/evil-moon",
}

AUTHORS = {"lorc": "Lorc", "delapouite": "Delapouite", "sbed": "Sbed"}


def fetch(path):
    req = urllib.request.Request(BASE + path + ".svg", headers={"User-Agent": "arcane-academy-tools/1.0"})
    with urllib.request.urlopen(req) as r:
        return r.read().decode("utf-8")


def clean(svg):
    # Drop the full-square background path; keep the glyph in white.
    svg = re.sub(r'<path d="M0 0h512v512H0z"\s*/>', "", svg, count=1)
    return svg.strip()


def tres(svg):
    escaped = svg.replace("\\", "\\\\").replace('"', '\\"')
    return ('[gd_resource type="DPITexture" format=3]\n\n[resource]\n_source = "%s"\nbase_scale = %s\n'
            % (escaped, SIZE / 512))


def main():
    os.makedirs(OUT, exist_ok=True)
    credits = ["# Placeholder icons", "",
               "From game-icons.net (https://game-icons.net), licensed CC BY 3.0 "
               "(https://creativecommons.org/licenses/by/3.0/). The black backgrounds were removed; "
               "the glyphs are tinted in the engine. Written by `tools/make_ui_icons.py`.", "",
               "| Id | Icon | Author |", "|---|---|---|"]
    for icon_id, path in sorted(ICONS.items()):
        svg = clean(fetch(path))
        with open(os.path.join(OUT, icon_id + ".tres"), "w") as f:
            f.write(tres(svg))
        author = AUTHORS.get(path.split("/")[0], path.split("/")[0])
        credits.append("| %s | %s | %s |" % (icon_id, path.split("/")[1], author))
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("\n".join(credits) + "\n")
    print("wrote %d icons to %s" % (len(ICONS), OUT))


if __name__ == "__main__":
    main()
