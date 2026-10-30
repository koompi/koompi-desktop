"""The first four styles: layered waves and a mesh gradient in the manner of
macOS, glowing arcs and fine lines in the manner of Ubuntu."""

import base64
import math
import random

from .common import mix, png_rgb, ramp, smooth_path, wave_points


def style_waves(rng, w, h, pal):
    """Rolling layered hills, lit from above, each casting a soft shadow."""
    out = [
        '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{pal[3]}"/><stop offset="1" stop-color="{pal[4]}"/>'
        '</linearGradient>'
        f'<filter id="shadow" x="-10%" y="-30%" width="120%" height="160%">'
        f'<feGaussianBlur stdDeviation="{h * 0.018:.1f}"/></filter></defs>',
        f'<rect width="{w}" height="{h}" fill="url(#sky)"/>',
    ]
    layers = rng.randint(5, 7)
    for i in range(layers):
        t = i / (layers - 1)
        base = h * (0.22 + 0.62 * t)
        pts = wave_points(rng, w, base, h * rng.uniform(0.05, 0.11))
        body = smooth_path(pts) + f" L{w * 1.1:.1f},{h * 1.1:.1f} L{-w * 0.1:.1f},{h * 1.1:.1f} Z"
        top, bottom = ramp(pal, 0.95 - 0.8 * t), ramp(pal, 0.75 - 0.75 * t)
        out.append(
            f'<linearGradient id="w{i}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="0.6" stop-color="{bottom}"/></linearGradient>'
        )
        out.append(f'<path d="{body}" fill="#000" opacity="0.28" filter="url(#shadow)" transform="translate(0,{-h * 0.012:.1f})"/>')
        out.append(f'<path d="{body}" fill="url(#w{i})"/>')
    return out


def style_blobs(rng, w, h, pal):
    """A mesh gradient: a few colour points blended by distance over warped
    coordinates. SVG blur cannot do this; at this radius librsvg's box blur
    leaves rectangles. It is low-frequency, so a small raster scaled up is exact
    enough, and the grain on top hides any step."""
    gw, gh = 240, max(2, round(240 * h / w))
    aspect = w / h
    points = [(rng.uniform(-0.1, 1.1) * aspect, rng.uniform(-0.1, 1.1), pal[1])]
    points += [(rng.uniform(-0.1, 1.1) * aspect, rng.uniform(-0.1, 1.1), rng.choice(pal[2:]))
               for _ in range(rng.randint(4, 6))]
    points = [(x, y, [int(c[i:i + 2], 16) for i in (1, 3, 5)]) for x, y, c in points]
    sigma2 = 2 * rng.uniform(0.18, 0.28) ** 2
    fx, fy = rng.uniform(0.6, 1.6), rng.uniform(0.6, 1.6)
    px, py = rng.uniform(0, math.tau), rng.uniform(0, math.tau)
    warp = rng.uniform(0.08, 0.18)
    rows = []
    for j in range(gh):
        v = j / (gh - 1)
        row = []
        for i in range(gw):
            u = i / (gw - 1) * aspect
            uu = u + warp * math.sin(fy * v * math.tau + py)
            vv = v + warp * math.sin(fx * u / aspect * math.tau + px)
            total, acc = 0.0, [0.0, 0.0, 0.0]
            for x, y, c in points:
                k = math.exp(-((uu - x) ** 2 + (vv - y) ** 2) / sigma2) + 1e-6
                total += k
                acc[0] += k * c[0]
                acc[1] += k * c[1]
                acc[2] += k * c[2]
            row.append(tuple(min(255, round(a / total)) for a in acc))
        rows.append(row)
    data = base64.b64encode(png_rgb(gw, gh, rows)).decode()
    return [f'<image width="{w}" height="{h}" preserveAspectRatio="none" href="data:image/png;base64,{data}"/>']


def style_rings(rng, w, h, pal):
    """A warm glow behind wide concentric arcs, the shape of Ubuntu's recent art."""
    cx, cy = rng.uniform(0.55, 0.85) * w, rng.uniform(0.35, 0.75) * h
    r0 = max(w, h) * rng.uniform(0.18, 0.28)
    out = [
        '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{pal[0]}"/><stop offset="1" stop-color="{pal[1]}"/></linearGradient>'
        f'<radialGradient id="glow" cx="{cx:.1f}" cy="{cy:.1f}" r="{r0 * 2.6:.1f}" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{pal[4]}" stop-opacity="0.95"/>'
        f'<stop offset="0.25" stop-color="{pal[3]}" stop-opacity="0.8"/>'
        f'<stop offset="0.6" stop-color="{pal[2]}" stop-opacity="0.35"/>'
        f'<stop offset="1" stop-color="{pal[1]}" stop-opacity="0"/></radialGradient>'
        f'<filter id="soft" x="-50%" y="-50%" width="200%" height="200%">'
        f'<feGaussianBlur stdDeviation="{w * 0.004:.1f}"/></filter></defs>',
        f'<rect width="{w}" height="{h}" fill="url(#bg)"/>',
        f'<rect width="{w}" height="{h}" fill="url(#glow)"/>',
    ]
    rings = rng.randint(7, 11)
    gap = r0 * rng.uniform(0.22, 0.35)
    for i in range(rings):
        r = r0 + i * gap
        width = gap * rng.uniform(0.08, 0.5)
        color = ramp(pal, 1 - i / rings * 0.7)
        # each ring an open arc, so the set reads as motion rather than a target
        start = rng.uniform(0, math.tau)
        sweep = rng.uniform(0.9, 1.7) * math.pi
        x1, y1 = cx + r * math.cos(start), cy + r * math.sin(start)
        x2, y2 = cx + r * math.cos(start + sweep), cy + r * math.sin(start + sweep)
        large = 1 if sweep > math.pi else 0
        arc = f"M{x1:.1f},{y1:.1f} A{r:.1f},{r:.1f} 0 {large} 1 {x2:.1f},{y2:.1f}"
        out.append(f'<path d="{arc}" fill="none" stroke="{color}" stroke-width="{width * 2.2:.1f}" stroke-linecap="round" opacity="0.18" filter="url(#soft)"/>')
        out.append(f'<path d="{arc}" fill="none" stroke="{color}" stroke-width="{width:.1f}" stroke-linecap="round" opacity="{rng.uniform(0.35, 0.8):.2f}"/>')
    return out


def style_lines(rng, w, h, pal):
    """A ribbon of fine parallel curves drifting across a dark ground."""
    out = [
        '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{pal[0]}"/><stop offset="1" stop-color="{mix(pal[0], pal[1], 0.6)}"/>'
        '</linearGradient>'
        '<linearGradient id="ink" x1="0" y1="0" x2="1" y2="0">'
        f'<stop offset="0" stop-color="{pal[2]}"/><stop offset="0.5" stop-color="{pal[3]}"/>'
        f'<stop offset="1" stop-color="{pal[4]}"/></linearGradient>'
        f'<filter id="glow" x="-10%" y="-50%" width="120%" height="200%">'
        f'<feGaussianBlur stdDeviation="{h * 0.01:.1f}"/></filter></defs>',
        f'<rect width="{w}" height="{h}" fill="url(#bg)"/>',
    ]
    n = rng.randint(40, 70)
    base = h * rng.uniform(0.35, 0.6)
    spread = h * rng.uniform(0.25, 0.45)
    master = random.Random(rng.random())
    shape = wave_points(master, w, 0, h * rng.uniform(0.12, 0.2))
    twist = wave_points(master, w, 0, 1)
    paths = []
    for i in range(n):
        t = i / (n - 1) - 0.5
        pts = [(x, base + y + t * spread * (1 + 0.8 * ty)) for (x, y), (_, ty) in zip(shape, twist)]
        paths.append(smooth_path(pts))
    glow = "".join(f'<path d="{d}"/>' for d in paths[:: max(1, n // 12)])
    out.append(f'<g fill="none" stroke="url(#ink)" stroke-width="{h * 0.006:.1f}" opacity="0.5" filter="url(#glow)">{glow}</g>')
    lines = "".join(f'<path d="{d}"/>' for d in paths)
    out.append(f'<g fill="none" stroke="url(#ink)" stroke-width="{max(1.0, h * 0.0012):.2f}" opacity="0.75">{lines}</g>')
    return out


STYLES = {"waves": style_waves, "blobs": style_blobs, "rings": style_rings, "lines": style_lines}
