"""Soft styles in the manner of macOS: silk folds, an aurora over hills,
glassy bokeh and a desert of sharp-crested dunes, all light and gradient.
Shapes that repeat set fill-opacity rather than opacity: librsvg composites
every element carrying opacity through a layer of its own, which is slow."""

import math

from .common import mix, ramp, smooth_path

TAU = math.tau


def _curve(rng, x0, x1, base, amp, n=24, freq=(0.5, 1.1)):
    """Points of a slow two-sine curve from x0 to x1."""
    f1, f2 = rng.uniform(*freq), rng.uniform(1.4, 2.6)
    p1, p2 = rng.uniform(0, TAU), rng.uniform(0, TAU)
    a2 = rng.uniform(0.1, 0.3)
    span = x1 - x0
    return [(x0 + span * i / n,
             base + amp * (math.sin(TAU * f1 * i / n + p1) + a2 * math.sin(TAU * f2 * i / n + p2)))
            for i in range(n + 1)]


# ---------------------------------------------------------------- folds

def style_folds(rng, w, h, pal):
    """Silk sheets: wide curved bands on a slant, each shading from a lit
    crest down into its fold, laid one over the next with a soft shadow."""
    d = math.hypot(w, h) * 1.1
    n = rng.randint(5, 8)
    gap = d / n
    angle = rng.uniform(30, 55) * rng.choice((-1, 1))
    # one sweep shared by every band keeps them flowing together like cloth;
    # each band's own amplitude and drift make them pinch and open
    f, ph = rng.uniform(0.45, 0.9), rng.uniform(0, TAU)
    amp = gap * rng.uniform(0.9, 1.5)
    flip = rng.random() < 0.5
    defs = []
    shapes = []
    for i in range(n):
        t = i / (n - 1)
        c = ramp(pal, 0.2 + 0.75 * (1 - t if flip else t))
        c2 = ramp(pal, 0.2 + 0.75 * (1 - t if flip else t) + rng.uniform(-0.25, 0.25))
        base = -d / 2 + gap * (i + 0.3 + rng.uniform(-0.15, 0.15))
        a, drift = amp * rng.uniform(0.6, 1.3), rng.uniform(-0.6, 0.6)
        f2, p2 = rng.uniform(1.8, 2.7), rng.uniform(0, TAU)
        pts = []
        for k in range(33):
            u = k / 32
            x = -0.75 * d + 1.5 * d * u
            y = base + a * math.sin(TAU * f * u + ph + drift) + gap * 0.15 * math.sin(TAU * f2 * u + p2)
            pts.append((x, y))
        crest = smooth_path(pts)
        body = crest + f" L{0.75 * d:.1f},{d:.1f} L{-0.75 * d:.1f},{d:.1f} Z"
        # the shadow's filter region is set in user space around its crest: a
        # nearly straight crest has a thin bounding box, and a percentage
        # region would clip the blur to a hard edge
        top, span = base - a - gap * 0.85, 2 * a + gap * 1.2
        defs.append(
            f'<filter id="foldshade{i}" filterUnits="userSpaceOnUse" x="{-0.75 * d:.0f}" y="{top:.0f}" '
            f'width="{1.5 * d:.0f}" height="{span:.0f}"><feGaussianBlur stdDeviation="{gap * 0.1:.1f}"/></filter>'
            f'<linearGradient id="fold{i}" gradientUnits="userSpaceOnUse" '
            f'x1="0" y1="{base - a:.1f}" x2="0" y2="{base + a + gap * 1.2:.1f}">'
            f'<stop offset="0" stop-color="{mix(c, pal[4], 0.3)}"/><stop offset="0.45" stop-color="{c}"/>'
            f'<stop offset="1" stop-color="{mix(c, pal[0], 0.45)}"/></linearGradient>'
            f'<linearGradient id="foldx{i}" gradientUnits="userSpaceOnUse" x1="{-d / 2:.0f}" y1="0" x2="{d / 2:.0f}" y2="0">'
            f'<stop offset="0" stop-color="{c2}" stop-opacity="0.7"/><stop offset="0.5" stop-color="{c2}" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="{mix(c2, pal[4], 0.3)}" stop-opacity="0.5"/></linearGradient>')
        shapes.append(f'<path d="{crest}" fill="none" stroke="#000" stroke-width="{gap * 0.5:.1f}" stroke-opacity="0.28" '
                      f'filter="url(#foldshade{i})" transform="translate(0,{-gap * 0.08:.1f})"/>')
        shapes.append(f'<path d="{body}" fill="url(#fold{i})"/><path d="{body}" fill="url(#foldx{i})"/>')
        # the sheen sits just inside the crest, so the edge reads as a lit fold, not an outline
        shapes.append(f'<g fill="none" stroke="{pal[4]}" transform="translate(0,{gap * 0.02:.1f})">'
                      f'<path d="{crest}" stroke-width="{gap * 0.04:.1f}" stroke-opacity="0.08"/>'
                      f'<path d="{crest}" stroke-width="{gap * 0.012:.1f}" stroke-opacity="0.14"/></g>')
    return [
        f'<defs>{"".join(defs)}</defs>',
        f'<rect width="{w}" height="{h}" fill="{ramp(pal, 0.2 + 0.75 * (1 if flip else 0))}"/>',
        f'<g transform="translate({w / 2:.1f},{h / 2:.1f}) rotate({angle:.1f})">{"".join(shapes)}</g>',
    ]


# ---------------------------------------------------------------- aurora

def _stars(rng, w, h, top):
    """Fine stars, dense high up and thinning toward the horizon."""
    s = h / 1440
    out = []
    for _ in range(int(w * h / 6000)):
        x, y = rng.uniform(0, w), rng.uniform(0, top) * rng.random() ** 0.3
        op = (0.2 + 0.8 * rng.random() ** 3) * (1 - 0.7 * y / top)
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{s * (0.6 + 1.2 * rng.random() ** 4):.1f}" fill-opacity="{op:.2f}"/>')
    return f'<g fill="#fff">{"".join(out)}</g>'


def _at(pts, u):
    """The y of an evenly spaced curve at u in [0, 1], linearly interpolated."""
    idx = u * (len(pts) - 1)
    i = min(int(idx), len(pts) - 2)
    return pts[i][1] + (pts[i + 1][1] - pts[i][1]) * (idx - i)


def _curtain(rng, w, h, k, pal, base, tall, strength):
    """One aurora curtain as thin vertical strips: a bright lower edge, light
    rising in streaks and fading out above."""
    span = w * rng.uniform(0.6, 1.1)
    x0 = rng.uniform(-0.15 * w, w * 1.05 - span)
    edge = _curve(rng, x0, x0 + span, base, h * rng.uniform(0.03, 0.07), n=40, freq=(0.4, 1.0))
    top = _curve(rng, x0, x0 + span, tall, tall * 0.25, n=40)
    sw = h * 0.004
    steps = int(span / sw)
    f1, f2, f3 = rng.uniform(6, 11), rng.uniform(19, 31), rng.uniform(47, 71)
    p1, p2, p3 = (rng.uniform(0, TAU) for _ in range(3))
    strips = []
    for j in range(steps):
        u = j / steps
        streak = (0.5 + 0.22 * math.sin(TAU * f1 * u + p1) + 0.16 * math.sin(TAU * f2 * u + p2)
                  + 0.12 * math.sin(TAU * f3 * u + p3)) * rng.uniform(0.8, 1.1)
        env = math.sin(math.pi * u) ** 2
        y0, ht = _at(edge, u), _at(top, u) * (0.7 + 0.6 * streak)
        strips.append(f'<rect x="{x0 + j * sw:.1f}" y="{y0 - ht:.1f}" width="{sw * 1.8:.1f}" height="{ht + h * 0.012:.1f}" '
                      f'fill-opacity="{strength * env * (0.2 + 0.8 * streak):.2f}"/>')
    grad = (f'<linearGradient id="aur{k}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{pal[2]}" stop-opacity="0"/>'
            f'<stop offset="0.45" stop-color="{pal[2]}" stop-opacity="0.25"/>'
            f'<stop offset="0.85" stop-color="{pal[3]}" stop-opacity="0.7"/>'
            f'<stop offset="0.95" stop-color="{pal[4]}" stop-opacity="0.95"/>'
            f'<stop offset="1" stop-color="{pal[3]}" stop-opacity="0"/></linearGradient>'
            f'<radialGradient id="aurglow{k}"><stop offset="0" stop-color="{pal[3]}" stop-opacity="{0.22 * strength:.2f}"/>'
            f'<stop offset="1" stop-color="{pal[3]}" stop-opacity="0"/></radialGradient>')
    glow = (f'<ellipse cx="{x0 + span / 2:.1f}" cy="{base - tall * 0.3:.1f}" rx="{span * 0.6:.1f}" ry="{tall * 0.9:.1f}" '
            f'fill="url(#aurglow{k})"/>')
    return grad, glow + f'<g fill="url(#aur{k})" filter="url(#aurblur)">{"".join(strips)}</g>'


def style_aurora(rng, w, h, pal):
    """A night sky of fine stars, two to four aurora curtains, and the dark
    line of hills underneath."""
    night = mix(pal[0], "#000000", 0.35)
    defs = [
        '<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{night}"/><stop offset="0.6" stop-color="{pal[0]}"/>'
        f'<stop offset="1" stop-color="{mix(pal[1], pal[2], 0.25)}"/></linearGradient>',
        f'<filter id="aurblur" x="-5%" y="-5%" width="110%" height="110%">'
        f'<feGaussianBlur stdDeviation="{h * 0.004:.1f} {h * 0.002:.1f}"/></filter>',
    ]
    body = [f'<rect width="{w}" height="{h}" fill="url(#sky)"/>', _stars(rng, w, h, h * 0.8)]
    # far curtains first: higher, shorter and dimmer, so the set has depth
    n = rng.randint(2, 4)
    for k in range(n):
        t = k / (n - 1)
        base = h * (0.33 + 0.25 * t + rng.uniform(-0.03, 0.03))
        grad, g = _curtain(rng, w, h, k, pal, base, h * (0.18 + 0.14 * t), 0.55 + 0.45 * t)
        defs.append(grad)
        body.append(g)
    for i, (base, amp) in enumerate(((0.8, 0.05), (0.88, 0.04))):
        pts = _curve(rng, -0.05 * w, 1.05 * w, h * base, h * amp, freq=(0.7, 1.5))
        fill = mix(pal[0], "#000000", 0.45 + 0.25 * i)
        body.append(f'<path d="{smooth_path(pts)} L{w * 1.05:.1f},{h:.1f} L{-w * 0.05:.1f},{h:.1f} Z" fill="{fill}"/>')
    return [f'<defs>{"".join(defs)}</defs>'] + body


# ---------------------------------------------------------------- orbs

def _orb_grads(pal):
    """Three fills per colour. Far discs are faint with a soft edge; mid and
    near ones brighten toward the rim, as out-of-focus light does."""
    out = []
    for n, c in enumerate(pal[2:]):
        lit = mix(c, "#ffffff", 0.35)
        out.append(f'<radialGradient id="orbf{n}"><stop offset="0" stop-color="{c}" stop-opacity="0.2"/>'
                   f'<stop offset="0.8" stop-color="{c}" stop-opacity="0.16"/>'
                   f'<stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>')
        out.append(f'<radialGradient id="orbm{n}"><stop offset="0" stop-color="{c}" stop-opacity="0.22"/>'
                   f'<stop offset="0.9" stop-color="{lit}" stop-opacity="0.34"/>'
                   f'<stop offset="1" stop-color="{lit}" stop-opacity="0.05"/></radialGradient>')
        out.append(f'<radialGradient id="orbn{n}" fx="0.4" fy="0.35"><stop offset="0" stop-color="{lit}" stop-opacity="0.42"/>'
                   f'<stop offset="0.7" stop-color="{c}" stop-opacity="0.3"/>'
                   f'<stop offset="1" stop-color="{lit}" stop-opacity="0.5"/></radialGradient>')
    return out


def _orb_spots(rng, w, h, a, b, count, rad, spread):
    """Disc centres scattered about the line a-b, kept on screen and apart."""
    s = min(w, h)
    spots = []
    for _ in range(count * 8):
        if len(spots) == count:
            break
        t = rng.uniform(0.05, 0.95)
        x = a[0] + (b[0] - a[0]) * t + rng.gauss(0, spread) * s
        y = a[1] + (b[1] - a[1]) * t + rng.gauss(0, spread) * s
        r = s * rng.uniform(*rad)
        if not (-0.3 * r < x < w + 0.3 * r and -0.3 * r < y < h + 0.3 * r):
            continue
        if all(math.hypot(x - u, y - v) > 0.9 * (r + q) for u, v, q in spots):
            spots.append((x, y, r))
    return spots


def style_orbs(rng, w, h, pal):
    """Glassy bokeh: big soft colour clouds behind discs in three depths,
    the far ones wide and faint, the near ones crisp with a light rim."""
    m = max(w, h)
    defs = ['<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{pal[0]}"/><stop offset="0.55" stop-color="{pal[1]}"/>'
            f'<stop offset="1" stop-color="{mix(pal[1], pal[2], 0.5)}"/></linearGradient>']
    body = [f'<rect width="{w}" height="{h}" fill="url(#bg)"/>']
    for k, c in enumerate(rng.sample(pal[2:], rng.randint(2, 3))):
        cx, cy, r = rng.uniform(0, w), rng.uniform(0, h), m * rng.uniform(0.3, 0.55)
        defs.append(f'<radialGradient id="cloud{k}" cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" gradientUnits="userSpaceOnUse">'
                    f'<stop offset="0" stop-color="{c}" stop-opacity="0.7"/><stop offset="0.45" stop-color="{c}" stop-opacity="0.3"/>'
                    f'<stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>')
        body.append(f'<rect width="{w}" height="{h}" fill="url(#cloud{k})"/>')
    defs += _orb_grads(pal)
    # discs gather along one diagonal drift, which leaves calm space around it
    a = (rng.uniform(0, 0.3) * w, rng.uniform(0.7, 1.0) * h)
    b = (rng.uniform(0.7, 1.0) * w, rng.uniform(0, 0.3) * h)
    if rng.random() < 0.5:
        a, b = (a[0], h - a[1]), (b[0], h - b[1])
    rim = max(1.0, min(w, h) * 0.0012)
    layers = (("f", (4, 7), (0.12, 0.22), 0.22), ("m", (5, 9), (0.05, 0.1), 0.16), ("n", (4, 8), (0.02, 0.05), 0.12))
    for layer, count, rad, spread in layers:
        for x, y, r in _orb_spots(rng, w, h, a, b, rng.randint(*count), rad, spread):
            g = rng.choice((0, 1, 1, 2, 2)) if layer == "n" else rng.randrange(3)
            edge = (f' stroke="{mix(pal[g + 2], "#ffffff", 0.6)}" stroke-opacity="0.55" stroke-width="{rim:.1f}"'
                    if layer == "n" else "")
            body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="url(#orb{layer}{g})"{edge}/>')
    return [f'<defs>{"".join(defs)}</defs>'] + body


# ---------------------------------------------------------------- dunes

def _ridge(rng, w, base, amp, period):
    """A dune line as dense points: long windward slopes up to sharp crests,
    each dropping down a short steep slip face. Returns points and crests."""
    pts, crests = [], []
    x = -rng.uniform(0.2, 1.0) * period
    step = w / 400
    while x < w * 1.05:
        span = period * rng.uniform(0.7, 1.4)
        hc = amp * rng.uniform(0.45, 1.0)
        k = rng.uniform(0.55, 0.72)
        n = max(8, int(span / step))
        for j in range(n):
            u = j / n
            if u < k:
                v = u / k
                lift = 0.45 * v + 0.55 * (1 - (1 - v) ** 2)
            else:
                lift = (1 - (u - k) / (1 - k)) ** 1.35
            pts.append((x + span * u, base - hc * lift))
        crests.append((x + span * k, base - hc, x + span, hc))
        x += span
    pts.append((x, base))
    return pts, crests


def style_dunes(rng, w, h, pal):
    """A desert at dusk: a low sun glow on the horizon, dunes with sharp
    crests, each lit on its windward side and dark on its slip face, fading
    into haze with distance."""
    horizon = h * rng.uniform(0.48, 0.6)
    haze = mix(pal[3], pal[4], 0.5)
    sx = w * rng.uniform(0.2, 0.8)
    # heights and spacing from the shorter and longer side, so a portrait
    # screen gets the same dune shapes rather than tall spikes
    tall, wide = min(h, w * 0.9), max(w, h * 0.9)
    defs = [
        '<linearGradient id="sky" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" '
        f'y2="{horizon:.1f}"><stop offset="0" stop-color="{ramp(pal, 0.2)}"/>'
        f'<stop offset="0.6" stop-color="{ramp(pal, 0.55)}"/><stop offset="1" stop-color="{haze}"/></linearGradient>',
        f'<radialGradient id="sun" cx="{sx:.1f}" cy="{horizon:.1f}" r="{wide * 0.45:.1f}" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{pal[4]}" stop-opacity="0.95"/><stop offset="0.25" stop-color="{pal[4]}" stop-opacity="0.35"/>'
        f'<stop offset="1" stop-color="{pal[4]}" stop-opacity="0"/></radialGradient>',
    ]
    body = [f'<rect width="{w}" height="{h}" fill="url(#sky)"/>', f'<rect width="{w}" height="{h}" fill="url(#sun)"/>']
    n = rng.randint(4, 6)
    for i in range(n):
        t = i / (n - 1)
        base = horizon + (h * 1.02 - horizon) * (t ** 1.3) + h * 0.03
        amp = tall * (0.05 + 0.2 * t)
        pts, crests = _ridge(rng, w, base, amp, wide * (0.25 + 0.45 * t))
        fade = 0.75 * (1 - t) ** 1.4
        lit = mix(ramp(pal, 0.85 - 0.35 * t), haze, fade)
        dark = mix(ramp(pal, 0.45 - 0.35 * t), haze, fade)
        line = " ".join(f"L{x:.1f},{y:.1f}" for x, y in pts)
        defs.append(f'<linearGradient id="dl{i}" gradientUnits="userSpaceOnUse" x1="0" y1="{base - amp:.1f}" x2="0" y2="{base + amp:.1f}">'
                    f'<stop offset="0" stop-color="{lit}"/><stop offset="1" stop-color="{mix(lit, dark, 0.5)}"/></linearGradient>')
        body.append(f'<path d="M{pts[0][0]:.1f},{h * 1.2:.1f} {line} L{pts[-1][0]:.1f},{h * 1.2:.1f} Z" fill="url(#dl{i})"/>')
        defs.append(f'<linearGradient id="ds{i}" gradientUnits="userSpaceOnUse" x1="0" y1="{base - amp:.1f}" x2="0" y2="{base:.1f}">'
                    f'<stop offset="0" stop-color="{dark}"/><stop offset="1" stop-color="{mix(dark, lit, 0.35)}"/></linearGradient>')
        faces = []
        for cx, cy, tx, hc in crests:
            seg = " ".join(f"L{x:.1f},{y:.1f}" for x, y in pts if cx <= x <= tx)
            # the slip face spreads from its crest down to the trough, its foot
            # curving back under the crest the way sand pours
            fx, fy = cx - hc * rng.uniform(1.0, 2.2), base + hc * 0.3
            faces.append(f"M{cx:.1f},{cy:.1f} {seg} L{tx:.1f},{base:.1f} "
                         f"Q{(tx + fx) / 2:.1f},{fy + hc * 0.1:.1f} {fx:.1f},{fy:.1f} "
                         f"Q{cx - hc * 0.25:.1f},{cy + hc * 0.75:.1f} {cx:.1f},{cy:.1f} Z")
        body.append(f'<path d="{"".join(faces)}" fill="url(#ds{i})"/>')
    return [f'<defs>{"".join(defs)}</defs>'] + body


STYLES = {"folds": style_folds, "aurora": style_aurora, "orbs": style_orbs, "dunes": style_dunes}
