"""Write assets/icon/zigz.svg, the gallery's icon, as flat polygons for mkico.py.

    python3 tools/icon/gen.py && python3 tools/icon/mkico.py assets/icon/zigz.svg --iconset
    iconutil -c icns assets/icon/zigz.iconset -o assets/icon/zigz.icns && rm -r assets/icon/zigz.iconset

ZigGit's look (../ziggit/tools/icon/gen.py): a mark in safety orange (#FF5F00,
zigtui's 202) on a black rounded tile, Apple's icon grid of an 824 px rounded
square centred in 1024. The mark is a gallery's picture: a frame hung from a
nail on a wire, holding a landscape (a sun over two mountains). mkico.py paints
only straight-edged <path>s with solid fills, merging every path of one color
and painting the colors in the order they first appear, so circles and rounded
corners are polygons, the frame's opening is a near-black of its own (#010101)
painted over the frame, and the landscape a near-orange (#FF5F01) painted over
that. Re-run after editing; the outputs are committed.
"""
import math, os

SIZE = 1024
TILE = '000000'
ORANGE = 'ff5f00'
OPENING = '010101'  # reads as the tile; a color of its own so it paints after the frame
PICTURE = 'ff5f01'  # reads as the frame; a color of its own so it paints after the opening

def rounded_rect(x, y, w, h, r, steps=24):
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def circle(cx, cy, r, steps=72):
    return [(cx + r * math.cos(2 * math.pi * k / steps), cy + r * math.sin(2 * math.pi * k / steps)) for k in range(steps)]

def stroke(ax, ay, bx, by, width):
    dx, dy = bx - ax, by - ay
    n = math.hypot(dx, dy)
    ox, oy = -dy / n * width / 2, dx / n * width / 2
    return [(ax + ox, ay + oy), (bx + ox, by + oy), (bx - ox, by - oy), (ax - ox, ay - oy)]

def path(pts, fill):
    d = 'M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts) + ' Z'
    return f'  <path fill="#{fill}" d="{d}"/>'

tile = rounded_rect(100, 100, 824, 824, 185)
# The frame: landscape, its top a little below the centre to leave the wire room.
left, top, width, height, border = 212, 300, 600, 470, 56
frame = rounded_rect(left, top, width, height, 28)
inner_left, inner_top = left + border, top + border
inner_right, inner_bottom = left + width - border, top + height - border
opening = rounded_rect(inner_left, inner_top, inner_right - inner_left, inner_bottom - inner_top, 6, steps=6)
# The wire, from the frame's top to the nail.
nail = (512, 200)
wire = [stroke(400, top + 8, *nail, 18), stroke(*nail, 624, top + 8, 18), circle(*nail, 22)]
# The landscape, its mountains standing on the opening's foot (a little past it, so no seam shows).
foot = inner_bottom + 4
landscape = [
    circle(388, 438, 46),
    [(inner_left - 4, foot), (480, 470), (650, foot)],
    [(540, foot), (660, 540), (inner_right + 4, foot)],
]

out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">', path(tile, TILE)]
out += [path(p, ORANGE) for p in [frame] + wire]
out.append(path(opening, OPENING))
out += [path(p, PICTURE) for p in landscape]
out.append('</svg>')
dest = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'icon', 'zigz.svg')
open(dest, 'w').write('\n'.join(out) + '\n')
print(f'wrote {os.path.normpath(dest)}')
