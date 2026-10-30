"""Graphic, geometric styles in the manner of modern Ubuntu and design-studio
art: a topographic map, low-poly facets, retro colour stripes, a halftone
screen and a synthwave horizon."""

import base64
import math

from .common import closed_smooth_path, mix, png_rgb, ramp, rgb, smooth_path


def _raster(w, h, colour_at, cols=200):
    """A smooth field as a small PNG stretched over the canvas, as style_blobs
    does; colour_at(u, v) takes v in [0, 1] and u in [0, w/h]."""
    gw, gh = cols, max(2, round(cols * h / w))
    aspect = w / h
    rows = [[rgb(colour_at(i / (gw - 1) * aspect, j / (gh - 1))) for i in range(gw)] for j in range(gh)]
    data = base64.b64encode(png_rgb(gw, gh, rows)).decode()
    return f'<image width="{w}" height="{h}" preserveAspectRatio="none" href="data:image/png;base64,{data}"/>'


def _height_field(rng, aspect):
    """Hills and hollows plus a slow swell, over a gently warped plane."""
    hills = [(rng.uniform(-0.1, 1.1) * aspect, rng.uniform(-0.1, 1.1), rng.uniform(0.14, 0.38),
              rng.uniform(0.5, 1.0) * (1 if k < 2 else rng.choice((-1, 1)))) for k in range(rng.randint(4, 6))]
    swell = [(rng.uniform(0.4, 1.3), rng.uniform(0.4, 1.3), rng.uniform(0, math.tau), rng.uniform(0.08, 0.18))
             for _ in range(2)]
    wf, wp, wa = rng.uniform(1.0, 2.0), rng.uniform(0, math.tau), rng.uniform(0.04, 0.09)

    def f(x, y):
        x, y = x + wa * math.sin(wf * y * math.tau + wp), y + wa * math.cos(wf * x * math.tau + wp)
        v = sum(a * math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (2 * s * s)) for cx, cy, s, a in hills)
        return v + sum(a * math.sin(fx * x * math.tau + p) * math.cos(fy * y * math.tau - p) for fx, fy, p, a in swell)
    return f


def _march(grid, level):
    """Marching squares at one level: segments as pairs of edge keys."""
    segs = []
    for j in range(len(grid) - 1):
        top, bot = grid[j], grid[j + 1]
        for i in range(len(top) - 1):
            a, b, c, d = top[i], top[i + 1], bot[i + 1], bot[i]
            if min(a, b, c, d) > level or max(a, b, c, d) < level:
                continue
            ia, ib, ic, id_ = a > level, b > level, c > level, d > level
            # edges in order top, right, bottom, left, keyed so neighbours share them
            edges = [e for e, cut in ((("h", i, j), ia != ib), (("v", i + 1, j), ib != ic),
                                      (("h", i, j + 1), id_ != ic), (("v", i, j), ia != id_)) if cut]
            if len(edges) == 2:
                segs.append(tuple(edges))
            elif len(edges) == 4:
                t, r, btm, lft = edges
                if ((a + b + c + d) / 4 > level) == ia:
                    segs += [(t, r), (btm, lft)]
                else:
                    segs += [(lft, t), (r, btm)]
    return segs


def _chains(segs):
    """Join segments sharing an edge into polylines; returns (keys, closed)."""
    nbr = {}
    for p, q in segs:
        nbr.setdefault(p, []).append(q)
        nbr.setdefault(q, []).append(p)
    seen, out = set(), []
    starts = [k for k, v in nbr.items() if len(v) == 1] + list(nbr)
    for s in starts:
        if s in seen:
            continue
        chain, prev, cur = [s], None, s
        seen.add(s)
        while True:
            nxt = [n for n in nbr[cur] if n != prev and n not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            chain.append(cur)
        closed = len(chain) > 2 and s in nbr[cur] and len(nbr[s]) == 2
        out.append((chain, closed))
    return out


def style_contour(rng, w, h, pal):
    """A topographic map: fine contour lines over a dark, faintly lit relief."""
    aspect = w / h
    field = _height_field(rng, aspect)
    cell = max(w, h) / 120
    cols, rows = math.ceil(w / cell) + 1, math.ceil(h / cell) + 1
    grid = [[field(i * cell / h, j * cell / h) for i in range(cols)] for j in range(rows)]
    lo, hi = min(map(min, grid)), max(map(max, grid))
    grid = [[(v - lo) / (hi - lo) for v in row] for row in grid]
    peak = max(((v, i, j) for j, row in enumerate(grid) for i, v in enumerate(row)))

    def relief(u, v):
        t = (field(u, v) - lo) / (hi - lo)
        return mix(pal[0], pal[1], 0.15 + 0.45 * t * t)
    out = [_raster(w, h, relief, 160)]
    px, py = peak[1] * cell, peak[2] * cell
    out.append(
        f'<defs><radialGradient id="ctglow" cx="{px:.1f}" cy="{py:.1f}" r="{max(w, h) * 0.55:.1f}" '
        'gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{pal[2]}" stop-opacity="0.32"/>'
        f'<stop offset="1" stop-color="{pal[2]}" stop-opacity="0"/></radialGradient>'
        f'<filter id="ctblur" x="-5%" y="-5%" width="110%" height="110%">'
        f'<feGaussianBlur stdDeviation="{h * 0.003:.1f}"/></filter></defs>'
        f'<rect width="{w}" height="{h}" fill="url(#ctglow)"/>')
    n = rng.randint(34, 42)
    unit = h / 1440
    bold = []
    # levels halfway between even heights and even areas, so no stretch of the
    # map is bare while the peaks stay dense
    flat = sorted(v for row in grid for v in row)
    for k in range(n):
        q = (k + 0.5) / n
        level = 0.5 * q + 0.5 * flat[int(q * (len(flat) - 1))] + 1e-7
        d = _level_path(grid, level, cell)
        if not d:
            continue
        t = k / (n - 1)
        strong = k % 5 == 4
        width = (2.0 if strong else 1.0) * unit
        out.append(f'<path d="{d}" fill="none" stroke="{ramp(pal, 0.3 + 0.7 * t)}" '
                   f'stroke-width="{width:.2f}" opacity="{0.9 if strong else 0.45 + 0.4 * t:.2f}"/>')
        if strong:
            bold.append(f'<path d="{d}" stroke="{ramp(pal, 0.4 + 0.6 * t)}"/>')
    out.insert(2, f'<g fill="none" stroke-width="{5 * unit:.1f}" opacity="0.45" filter="url(#ctblur)">{"".join(bold)}</g>')
    return out


def _level_path(grid, level, cell):
    """One contour level as a single path of smooth subpaths."""
    vals = {}

    def point(key):
        if key not in vals:
            kind, i, j = key
            a = grid[j][i]
            b = grid[j][i + 1] if kind == "h" else grid[j + 1][i]
            t = (level - a) / (b - a)
            vals[key] = ((i + t) * cell, j * cell) if kind == "h" else (i * cell, (j + t) * cell)
        return vals[key]
    parts = []
    for chain, closed in _chains(_march(grid, level)):
        pts = [point(k) for k in chain]
        if len(pts) < 5:
            continue
        # every other point: the curve stays smooth and the file small
        pts = pts[::2] if closed else pts[:-1:2] + [pts[-1]]
        parts.append(closed_smooth_path(pts) if closed else smooth_path(pts))
    return " ".join(parts)


def style_prism(rng, w, h, pal):
    """Low-poly facets washing diagonally through the palette."""
    cell = max(w, h) / 14
    cols, rows = max(3, round(w / cell)), max(3, round(h / cell))
    sx, sy = w / cols, h / rows
    # one row and column past each edge, so jitter never bares a corner
    pts = [[((i + rng.uniform(-0.38, 0.38)) * sx, (j + rng.uniform(-0.38, 0.38)) * sy)
            for i in range(-1, cols + 2)] for j in range(-1, rows + 2)]
    ang = rng.choice((0.25, 0.75, 1.25, 1.75)) * math.pi + rng.uniform(-0.15, 0.15)
    dx, dy = math.cos(ang), math.sin(ang)
    span = abs(dx) * w + abs(dy) * h
    off = min(0, dx * w) + min(0, dy * h)
    hx, hy = rng.uniform(0.2, 0.8) * w, rng.uniform(0.2, 0.8) * h
    f, p = rng.uniform(1.0, 2.0), rng.uniform(0, math.tau)

    def colour(x, y):
        t = (x * dx + y * dy - off) / span
        t += 0.06 * math.sin(f * math.tau * (x - y) / span + p)
        t += 0.18 * math.exp(-((x - hx) ** 2 + (y - hy) ** 2) / (2 * (0.25 * max(w, h)) ** 2))
        return ramp(pal, 0.06 + 0.9 * t)
    out = []
    for j in range(len(pts) - 1):
        for i in range(len(pts[0]) - 1):
            a, b, c, d = pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]
            tris = ((a, b, c), (a, c, d)) if rng.random() < 0.5 else ((a, b, d), (b, c, d))
            for tri in tris:
                cx, cy = sum(q[0] for q in tri) / 3, sum(q[1] for q in tri) / 3
                lift = rng.uniform(-0.07, 0.07)
                fill = mix(colour(cx, cy), "#ffffff" if lift > 0 else "#000000", abs(lift))
                d_ = " ".join(f"{x:.1f},{y:.1f}" for x, y in tri)
                out.append(f'<polygon points="{d_}" fill="{fill}" stroke="{fill}" stroke-width="0.6" stroke-linejoin="round"/>')
    return out


def _band_shadow(path, width, unit):
    """A soft shadow cast outward under a band: two faint offset strokes, no blur."""
    return "".join(f'<path d="{path}" fill="none" stroke="#000" stroke-width="{width + grow * unit:.1f}" '
                   f'opacity="{alpha}" transform="translate({dx * unit:.1f},{dy * unit:.1f})"/>'
                   for grow, alpha, dx, dy in ((2, 0.2, 2, 4), (10, 0.08, 4, 9)))


def style_retro(rng, w, h, pal):
    """Bold seventies colour stripes sweeping round a corner, flat and clean."""
    unit = min(w, h) / 1440
    n = rng.randint(5, 7)
    colours = [ramp(pal, 1 - 0.72 * k / (n - 1)) for k in range(n)]
    if rng.random() < 0.5:
        colours.reverse()
    mode = rng.choice(("corner", "arc", "bend"))
    flip = rng.random() < 0.5
    side = min(w, h)
    if mode == "corner":
        outer = side * rng.uniform(0.8, 0.95)
        r0 = outer * rng.uniform(0.32, 0.45)
        cx, cy = (w if flip else 0), h
    elif mode == "arc":
        outer = min(0.46 * w, 0.72 * h) * rng.uniform(0.88, 1.0)
        r0 = outer * rng.uniform(0.2, 0.32)
        cx, cy = w * 0.5 + (w * 0.5 - outer) * rng.uniform(-0.6, 0.6), h * 1.01
    else:
        outer = side * rng.uniform(0.38, 0.5)
        r0 = outer * rng.uniform(0.1, 0.25)
        cx = w * rng.uniform(0.48, 0.6)
        outer = min(outer, 0.85 * (w - cx))
        cy = outer + h * rng.uniform(0.1, 0.22)
    # thin gaps: the bands read as one sweep, the shadows give the depth
    pitch = (outer - r0) / n
    band, gap = pitch * 0.94, pitch * 0.06
    out = [f'<rect width="{w}" height="{h}" fill="{pal[0]}"/>']
    if flip and mode == "bend":
        out.append(f'<g transform="translate({w},0) scale(-1,1)">')
    for k in reversed(range(n)):
        r = r0 + k * (band + gap) + band / 2
        if mode == "bend":
            path = (f"M{-w * 0.05:.1f},{cy - r:.1f} L{cx:.1f},{cy - r:.1f} "
                    f"A{r:.1f},{r:.1f} 0 0 1 {cx + r:.1f},{cy:.1f} L{cx + r:.1f},{h * 1.05:.1f}")
        else:
            path = f"M{cx - r:.1f},{cy:.1f} A{r:.1f},{r:.1f} 0 0 1 {cx + r:.1f},{cy:.1f}" + (
                f" A{r:.1f},{r:.1f} 0 0 1 {cx - r:.1f},{cy:.1f}" if mode == "corner" else "")
        out.append(_band_shadow(path, band, unit))
        out.append(f'<path d="{path}" fill="none" stroke="{colours[k]}" stroke-width="{band:.1f}"/>')
    if flip and mode == "bend":
        out.append("</g>")
    return out


def _ribbon(rng, w, h):
    """A smooth field in [0, 1]: a soft band along a wave, tilted, with a glow."""
    tilt = rng.uniform(-0.35, 0.35)
    base = rng.uniform(0.4, 0.6)
    f1, f2 = rng.uniform(0.5, 1.1), rng.uniform(1.4, 2.4)
    p1, p2 = rng.uniform(0, math.tau), rng.uniform(0, math.tau)
    width = rng.uniform(0.16, 0.24)
    gx, gy = rng.uniform(0.15, 0.85) * w, rng.uniform(0.2, 0.8) * h
    side = min(w, h)

    def field(x, y):
        u = x / max(w, h)
        swing = 0.15 * math.sin(math.tau * f1 * u + p1) + 0.05 * math.sin(math.tau * f2 * u + p2)
        centre = h * (base + tilt * (x / w - 0.5)) + side * swing
        band = math.exp(-((y - centre) / (width * side)) ** 2)
        glow = math.exp(-((x - gx) ** 2 + (y - gy) ** 2) / (2 * (0.3 * max(w, h)) ** 2))
        return min(1.0, band * (0.55 + 0.45 * glow) + 0.18 * glow)
    return field


def style_halftone(rng, w, h, pal):
    """A halftone screen: a hex grid of dots swelling along a soft ribbon."""
    field = _ribbon(rng, w, h)
    s = math.sqrt(w * h / (0.866 * 5200))
    out = [_raster(w, h, lambda u, v: mix(pal[0], pal[1], 0.15 + 0.5 * field(u * h, v * h)), 120)]
    dots = []
    rows = int(h / (s * 0.866)) + 2
    for j in range(rows):
        y = j * s * 0.866
        for i in range(int(w / s) + 2):
            x = (i + 0.5 * (j % 2)) * s
            v = field(x, y)
            r = s * 0.47 * v ** 1.2
            if r < 0.6:
                continue
            c = ramp(pal, 0.3 + 0.55 * v + 0.15 * x / w)
            dots.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{c}"/>')
    return out + dots


def style_horizon(rng, w, h, pal):
    """A synthwave sunset: a striped sun over mountains and a glowing grid."""
    hy = h * rng.uniform(0.6, 0.64)
    r = min(w, h) * rng.uniform(0.2, 0.26)
    cx, cy = w * rng.uniform(0.4, 0.6), hy - r * rng.uniform(0.3, 0.5)
    unit = min(w, h) / 1440
    out = [_horizon_defs(w, h, pal, hy, cx, cy, r, unit),
           f'<rect width="{w}" height="{hy + 1:.1f}" fill="url(#hzsky)"/>',
           _stars(rng, w, hy, pal, unit),
           f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r * 2.4:.1f}" fill="url(#hzhalo)"/>',
           f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="url(#hzsun)" mask="url(#hzcut)"/>']
    for k, (amp, tone) in enumerate(((0.13, mix(pal[1], pal[2], 0.35)), (0.075, mix(pal[0], pal[1], 0.55)))):
        ridge = _ridge(rng, w, hy, h * amp, cx, r)
        body = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in ridge)
        out.append(f'<path d="{body} L{w * 1.02:.1f},{hy + 2:.1f} L{-w * 0.02:.1f},{hy + 2:.1f} Z" fill="{tone}"/>')
        if k == 0:
            out.append(f'<path d="{body}" fill="none" stroke="{pal[3]}" stroke-width="{1.5 * unit:.1f}" opacity="0.35"/>')
    out.append(f'<rect y="{hy:.1f}" width="{w}" height="{h - hy + 1:.1f}" fill="url(#hzground)"/>')
    grid = _grid(w, h, hy, cx)
    out.append(f'<g fill="none" stroke="url(#hzline)" stroke-width="{5 * unit:.1f}" opacity="0.5" '
               f'filter="url(#hzblur)">{grid}</g>')
    out.append(f'<g fill="none" stroke="url(#hzline)" stroke-width="{1.6 * unit:.1f}">{grid}</g>')
    out.append(f'<rect y="{hy - h * 0.04:.1f}" width="{w}" height="{h * 0.08:.1f}" fill="url(#hzhaze)"/>')
    return out


def _horizon_defs(w, h, pal, hy, cx, cy, r, unit):
    bars = []
    y, k = cy - r * 0.2, 0
    while y < cy + r:
        gap = r * (0.014 + 0.012 * k)
        bars.append(f'<rect x="{cx - r - 1:.1f}" y="{y:.1f}" width="{2 * r + 2:.1f}" height="{gap:.1f}" fill="#000"/>')
        y += gap + r * max(0.04, 0.12 - 0.014 * k)
        k += 1
    return (
        f'<defs><linearGradient id="hzsky" x1="0" y1="0" x2="0" y2="{hy:.1f}" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{pal[0]}"/><stop offset="0.55" stop-color="{pal[1]}"/>'
        f'<stop offset="1" stop-color="{pal[2]}"/></linearGradient>'
        f'<linearGradient id="hzsun" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{pal[4]}"/><stop offset="1" stop-color="{pal[3]}"/></linearGradient>'
        f'<radialGradient id="hzhalo"><stop offset="0.3" stop-color="{pal[3]}" stop-opacity="0.45"/>'
        f'<stop offset="1" stop-color="{pal[3]}" stop-opacity="0"/></radialGradient>'
        f'<mask id="hzcut"><rect width="{w}" height="{h}" fill="#fff"/>{"".join(bars)}</mask>'
        f'<linearGradient id="hzground" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{mix(pal[0], pal[1], 0.5)}"/><stop offset="1" stop-color="{pal[0]}"/></linearGradient>'
        f'<linearGradient id="hzline" x1="0" y1="{hy:.1f}" x2="0" y2="{h}" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{pal[3]}" stop-opacity="0"/>'
        f'<stop offset="0.3" stop-color="{pal[3]}" stop-opacity="0.85"/>'
        f'<stop offset="1" stop-color="{pal[3]}" stop-opacity="1"/></linearGradient>'
        f'<linearGradient id="hzhaze" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{pal[3]}" stop-opacity="0"/><stop offset="0.5" stop-color="{pal[3]}" stop-opacity="0.35"/>'
        f'<stop offset="1" stop-color="{pal[3]}" stop-opacity="0"/></linearGradient>'
        f'<filter id="hzblur" x="-5%" y="-5%" width="110%" height="110%">'
        f'<feGaussianBlur stdDeviation="{3 * unit:.1f}"/></filter></defs>')


def _stars(rng, w, hy, pal, unit):
    dots = []
    for _ in range(rng.randint(70, 110)):
        y = hy * rng.random() ** 1.6 * 0.75
        dots.append(f'<circle cx="{rng.uniform(0, w):.1f}" cy="{y:.1f}" r="{rng.uniform(0.6, 1.7) * unit:.1f}" '
                    f'opacity="{rng.uniform(0.2, 0.7) * (1 - y / hy):.2f}"/>')
    return f'<g fill="{pal[4]}">{"".join(dots)}</g>'


def _ridge(rng, w, hy, amp, cx, r):
    """A mountain line by midpoint displacement, lower round the sun."""
    n = 64
    ys = [0.0] * (n + 1)
    ys[0], ys[n] = rng.uniform(0.3, 1), rng.uniform(0.3, 1)
    step, rough = n, 0.6
    while step > 1:
        for i in range(step // 2, n, step):
            ys[i] = (ys[i - step // 2] + ys[i + step // 2]) / 2 + rng.uniform(-rough, rough)
        step //= 2
        rough *= 0.55
    xs = [-0.02 * w + i * 1.04 * w / n for i in range(n + 1)]
    return [(x, hy - amp * max(0.05, 0.5 + v) * (0.3 + 0.7 * min(1.0, abs(x - cx) / (r * 2.2))))
            for x, v in zip(xs, ys)]


def _grid(w, h, hy, vx):
    """Perspective floor lines: rows bunch toward the horizon, columns meet the sun."""
    lines, k, prev = [], 0, h * 2
    while True:
        y = hy + (h - hy) * 1.15 / (1 + 0.42 * k)
        if prev - y < h * 0.004:
            break
        if y <= h:
            lines.append(f"M0,{y:.1f} H{w}")
        prev, k = y, k + 1
    sp = 0.07 * max(w, 0.9 * h)
    for i in range(-60, 61):
        lines.append(f"M{vx:.1f},{hy:.1f} L{vx + i * sp:.1f},{h}")
    return f'<path d="{" ".join(lines)}"/>'


STYLES = {"contour": style_contour, "prism": style_prism, "retro": style_retro,
          "halftone": style_halftone, "horizon": style_horizon}
