"""What every style shares: the palettes, colour blending, smooth curves, the
grain that stops gradients banding, and a minimal PNG writer for styles that
compute their colours per pixel. Standard library only."""

import math
import struct
import zlib

# Five stops each, darkest first. Named for the look, not copied from anyone.
PALETTES = {
    "sunset": ["#1b1340", "#4b2a7b", "#c2408a", "#f2765b", "#ffc387"],
    "ember": ["#1a0b06", "#7a1f0a", "#d9480f", "#f59f00", "#ffe8a3"],
    "dawn": ["#0b1a3a", "#1f4fa3", "#7a5cff", "#ff6fb5", "#ffd1e8"],
    "dusk": ["#120a2a", "#3a1c71", "#6b3fa0", "#4fa3ff", "#a6e3ff"],
    "aubergine": ["#2c001e", "#5e2750", "#77216f", "#e95420", "#f6a27a"],
    "ocean": ["#03141f", "#0b3954", "#087e8b", "#4fd1c5", "#c2f5ec"],
    "forest": ["#0b1a12", "#1d4027", "#3f7d4e", "#9ccf6d", "#e9f5c9"],
    "angkor": ["#1a1033", "#3c2a5e", "#b4532a", "#e8a33d", "#f7dfa5"],
    "mekong": ["#062a2a", "#0f5257", "#2a9d8f", "#e9c46a", "#f4a261"],
    "graphite": ["#0f1115", "#2a2f3a", "#4c5566", "#8a96a8", "#d9e0ea"],
    "rose": ["#2a0f1f", "#6d1f4b", "#d44d7c", "#f59ab5", "#ffe1ea"],
    "citrus": ["#14210a", "#2f5d1a", "#8cbf26", "#f2c94c", "#fff3b0"],
    "glacier": ["#0a1626", "#1c3d5e", "#4a7fb0", "#9cc7e8", "#eef7ff"],
    "nebula": ["#0d0221", "#261447", "#6b2fa3", "#ff3864", "#ffd166"],
}


def rgb(c):
    """#rrggbb as an (r, g, b) tuple of ints."""
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, t):
    """Blend two #rrggbb colours, t=0 gives a."""
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


def ramp(palette, t):
    """A colour at t in [0, 1] along the palette's stops."""
    t = min(max(t, 0.0), 1.0) * (len(palette) - 1)
    i = min(int(t), len(palette) - 2)
    return mix(palette[i], palette[i + 1], t - i)


def smooth_path(points):
    """Catmull-Rom through the points, as cubic Beziers: a curve with no corners."""
    d = [f"M{points[0][0]:.1f},{points[0][1]:.1f}"]
    for i in range(len(points) - 1):
        p0 = points[max(i - 1, 0)]
        p1, p2 = points[i], points[i + 1]
        p3 = points[min(i + 2, len(points) - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    return " ".join(d)


def wave_points(rng, w, base, amp, n=28):
    """Points of a gentle curve across the width: two sines of unrelated phase."""
    f1, f2 = rng.uniform(0.6, 1.4), rng.uniform(1.6, 3.2)
    p1, p2 = rng.uniform(0, math.tau), rng.uniform(0, math.tau)
    a2 = rng.uniform(0.15, 0.4)
    pts = []
    for i in range(n + 1):
        x = -0.05 * w + i * 1.1 * w / n
        u = x / w
        y = base + amp * (math.sin(math.tau * f1 * u + p1) + a2 * math.sin(math.tau * f2 * u + p2))
        pts.append((x, y))
    return pts


def grain(w, h, strength=0.07):
    """Film grain over everything: it is what keeps a wide gradient from banding."""
    return (
        f'<filter id="grain" x="0" y="0" width="100%" height="100%">'
        f'<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" stitchTiles="stitch"/>'
        f'<feColorMatrix type="saturate" values="0"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{strength}"/></feComponentTransfer>'
        f'</filter><rect width="{w}" height="{h}" filter="url(#grain)"/>'
    )


def png_rgb(width, height, rows):
    """A minimal 8-bit RGB PNG from rows of (r, g, b) tuples, standard library only."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def closed_smooth_path(points):
    """Catmull-Rom through the points and back to the first: a closed blob."""
    n = len(points)
    d = [f"M{points[0][0]:.1f},{points[0][1]:.1f}"]
    for i in range(n):
        p0, p1, p2, p3 = (points[(i + k) % n] for k in (-1, 0, 1, 2))
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    return " ".join(d) + " Z"
