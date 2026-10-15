"""SVG plans of a castle Plan, one per storey, for reviewing seeds without Godot.

Rooms are filled by kind (house rooms in their house colour), doors are gaps
marked in white, secret walls in magenta, stair flights as arrows from the foot
to the top with their approach and arrival landings outlined, moving pieces in
orange. Output: .godot/castle_preview/storey_<n>.svg plus index.html.
"""
import html
import os

from .geometry import STOREY

OUT_DIR = ".godot/castle_preview"
SCALE = 3.0   # px per metre
KIND_FILL = {
    "hall": "#c9b48a", "corridor": "#b8ad96", "classroom": "#8fb3d9", "library": "#a58fd9",
    "common_room": "#d98f8f", "dormitory": "#d9b38f", "room": "#b0b0a0", "tower": "#9fb39f",
    "outdoor": "#7fae6a", "secret": "#c46ad9", "shaft": "#e0a050",
}
HOUSE_FILL = {1: "#b84a3a", 2: "#c9a640", 3: "#d9733a", 4: "#3a7ab8"}


def bounds(plan):
    xs = [v for r in plan.rooms.values() for v in (r.x0, r.x1)]
    zs = [v for r in plan.rooms.values() for v in (r.z0, r.z1)]
    return min(xs) - 8, max(xs) + 8, min(zs) - 8, max(zs) + 8


def storeys(plan):
    return sorted({s for r in plan.rooms.values() for s in r.storeys()})


def svg_storey(plan, s, extra=None):
    x0, x1, z0, z1 = bounds(plan)
    W, H = (x1 - x0) * SCALE, (z1 - z0) * SCALE
    X = lambda x: (x - x0) * SCALE
    Z = lambda z: (z - z0) * SCALE
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H + 30:.0f}" font-family="sans-serif">',
           f'<rect width="100%" height="100%" fill="#1d1d22"/>',
           f'<text x="6" y="{H + 20:.0f}" fill="#ddd" font-size="14">storey {s} (floor y {s * STOREY:.0f} m)</text>']
    # grid every 16 m
    for gx in range(int(x0 // 16) * 16, int(x1) + 1, 16):
        out.append(f'<line x1="{X(gx):.1f}" y1="0" x2="{X(gx):.1f}" y2="{H:.1f}" stroke="#2a2a30"/>')
    for gz in range(int(z0 // 16) * 16, int(z1) + 1, 16):
        out.append(f'<line x1="0" y1="{Z(gz):.1f}" x2="{W:.1f}" y2="{Z(gz):.1f}" stroke="#2a2a30"/>')
    present = [r for r in plan.rooms.values() if s in r.storeys()]
    present.sort(key=lambda r: (r.inside is not None, r.storey))
    for r in present:
        fill = HOUSE_FILL.get(r.house) if r.house else KIND_FILL.get(r.kind, "#999")
        op = 0.55 if s != r.storey else 0.9
        out.append(f'<rect x="{X(r.x0):.1f}" y="{Z(r.z0):.1f}" width="{r.width * SCALE:.1f}" height="{r.depth * SCALE:.1f}" '
                   f'fill="{fill}" fill-opacity="{op}" stroke="#111" stroke-width="1.5"><title>{html.escape(r.id)} ({r.kind})</title></rect>')
        cx, cz = r.centre()
        label = r.id if s == r.storey else f"({r.id})"
        out.append(f'<text x="{X(cx):.1f}" y="{Z(cz):.1f}" font-size="9" text-anchor="middle" fill="#111">{html.escape(label)}</text>')
    for axis, coord, off, st in plan.doors:
        if st != s:
            continue
        if axis == "x":
            out.append(f'<line x1="{X(off + 0.4):.1f}" y1="{Z(coord):.1f}" x2="{X(off + 3.6):.1f}" y2="{Z(coord):.1f}" stroke="#fff" stroke-width="4"/>')
        else:
            out.append(f'<line x1="{X(coord):.1f}" y1="{Z(off + 0.4):.1f}" x2="{X(coord):.1f}" y2="{Z(off + 3.6):.1f}" stroke="#fff" stroke-width="4"/>')
    for a, b, axis, coord, off, st, _n in plan.secrets:
        if st != s:
            continue
        if axis == "x":
            out.append(f'<line x1="{X(off):.1f}" y1="{Z(coord):.1f}" x2="{X(off + 4):.1f}" y2="{Z(coord):.1f}" stroke="#ff3df5" stroke-width="4"/>')
        else:
            out.append(f'<line x1="{X(coord):.1f}" y1="{Z(off):.1f}" x2="{X(coord):.1f}" y2="{Z(off + 4):.1f}" stroke="#ff3df5" stroke-width="4"/>')
    for st in plan.stairs:
        y = plan.stair_y(st)
        if int(round(y / STOREY)) != s and not (y < s * STOREY < y + st["rise"]):
            continue
        for key, colour in (("approach", "#40d0ff"), ("arrival", "#40ff90")):
            rect = st.get(key)
            if rect:
                out.append(f'<rect x="{X(rect[0]):.1f}" y="{Z(rect[2]):.1f}" width="{(rect[1] - rect[0]) * SCALE:.1f}" '
                           f'height="{(rect[3] - rect[2]) * SCALE:.1f}" fill="none" stroke="{colour}" stroke-dasharray="3,2"/>')
        if st.get("kind") == "spiral":
            out.append(f'<circle cx="{X(st["x"]):.1f}" cy="{Z(st["z"]):.1f}" r="{st["radius"] * SCALE:.1f}" fill="#555" stroke="#ffd34d" stroke-width="2"/>')
            continue
        fx0, fx1, fz0, fz1 = plan.stair_footprint(st)
        colour = "#ff9a3d" if st.get("moving") else "#ffd34d"
        out.append(f'<rect x="{X(fx0):.1f}" y="{Z(fz0):.1f}" width="{(fx1 - fx0) * SCALE:.1f}" height="{(fz1 - fz0) * SCALE:.1f}" '
                   f'fill="#555" stroke="{colour}" stroke-width="2"/>')
        from .geometry import local_to_world
        a = local_to_world(st["x"], st["z"], st["rot"], (0.3, 0)); b = local_to_world(st["x"], st["z"], st["rot"], (st["run"] - 0.3, 0))
        out.append(f'<line x1="{X(a[0]):.1f}" y1="{Z(a[1]):.1f}" x2="{X(b[0]):.1f}" y2="{Z(b[1]):.1f}" stroke="{colour}" stroke-width="2" marker-end="url(#arr)"/>')
    for item in (extra or []):
        out.append(item)
    out.insert(1, '<defs><marker id="arr" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 z" fill="#ffd34d"/></marker></defs>')
    out.append("</svg>")
    return "\n".join(out)


def write_all(plan, out_dir=OUT_DIR):
    os.makedirs(out_dir, exist_ok=True)
    names = []
    for s in storeys(plan):
        name = f"storey_{s}.svg"
        with open(os.path.join(out_dir, name), "w") as f:
            f.write(svg_storey(plan, s))
        names.append(name)
    with open(os.path.join(out_dir, "index.html"), "w") as f:
        f.write("<!doctype html><meta charset=utf-8><title>Castle preview</title><body style='background:#111;color:#ddd'>"
                + "".join(f"<h3>{n}</h3><img src='{n}'>" for n in names) + "</body>")
    return out_dir
