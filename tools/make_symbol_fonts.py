"""Builds the UI's symbol fallback fonts from Noto Sans Symbols (OFL).

Godot measures a line over the whole fallback chain, and the Noto symbol fonts are
much taller than Fira Sans, so used as they are they spread every label's lines apart.
This keeps only the symbol blocks, fixes the weight of the variable font at Regular and
gives both files Fira Sans's vertical metrics. Run after changing the blocks, then
re-run tools/build_ui_theme.gd:

    pip install fonttools
    python3 tools/make_symbol_fonts.py
"""
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "assets" / "fonts" / "noto_symbols"
METRICS_FROM = ROOT / "assets" / "fonts" / "fira_sans" / "FiraSans-Regular.ttf"
# Arrows, misc technical, geometric shapes, misc symbols, dingbats, misc symbols and arrows.
BLOCKS = [(0x2190, 0x21FF), (0x2300, 0x23FF), (0x25A0, 0x25FF), (0x2600, 0x26FF), (0x2700, 0x27BF), (0x2B00, 0x2BFF)]
FONTS = {"NotoSansSymbols2-Regular.ttf": "UiSymbols2.ttf", "NotoSansSymbols-Variable.ttf": "UiSymbols.ttf"}


def main() -> None:
    ref = TTFont(METRICS_FROM)
    scale_ref = ref["head"].unitsPerEm
    unicodes = [c for lo, hi in BLOCKS for c in range(lo, hi + 1)]
    for src, out in FONTS.items():
        font = TTFont(DIR / "source" / src)
        if "fvar" in font:
            font = instancer.instantiateVariableFont(font, {"wght": 400})
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.notdef_outline = True
        sub = subset.Subsetter(options)
        sub.populate(unicodes=unicodes)
        sub.subset(font)
        k = font["head"].unitsPerEm / scale_ref
        asc, desc = round(ref["hhea"].ascent * k), round(ref["hhea"].descent * k)
        font["hhea"].ascent, font["hhea"].descent, font["hhea"].lineGap = asc, desc, 0
        os2 = font["OS/2"]
        os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = asc, desc, 0
        os2.usWinAscent, os2.usWinDescent = asc, -desc
        font.save(DIR / out)
        print("wrote", DIR / out, len(font.getBestCmap()), "glyphs")


if __name__ == "__main__":
    main()
