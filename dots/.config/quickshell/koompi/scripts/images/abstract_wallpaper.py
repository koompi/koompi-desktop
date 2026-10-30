#!/usr/bin/env python3
"""Draw an abstract wallpaper as SVG: gradient layers, light and line in the
manner of macOS's and Ubuntu's recent defaults, made here rather than
downloaded, since neither vendor's art is ours to ship. Standard library only;
the styles are in abstract/. rsvg-convert, which librsvg puts on every machine
with GTK, renders it at the screen's own size.

    abstract_wallpaper.py --width 2560 --height 1440 [--style S] [--palette P]
                          [--seed N] [--list]

Prints the SVG on stdout, and the chosen style, palette and seed on stderr as
`style=... palette=... seed=...` so the caller can name the file after them.
"""

import argparse
import os
import random
import sys

# Our own package beside this file. -I keeps the caller's directory off the
# path; adding this one back is safe, and no bytecode is left in the dotfiles.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from abstract import STYLES  # noqa: E402
from abstract.common import PALETTES, grain  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--width", type=int, default=2560)
    ap.add_argument("--height", type=int, default=1440)
    ap.add_argument("--style", choices=STYLES)
    ap.add_argument("--palette", choices=sorted(PALETTES))
    ap.add_argument("--seed", type=int)
    ap.add_argument("--list", action="store_true", help="print the styles and palettes, then exit")
    args = ap.parse_args()

    if args.list:
        print("styles:", " ".join(STYLES))
        print("palettes:", " ".join(sorted(PALETTES)))
        return 0

    seed = args.seed if args.seed is not None else random.SystemRandom().randrange(1, 10**9)
    rng = random.Random(seed)
    style = args.style or rng.choice(list(STYLES))
    palette = args.palette or rng.choice(sorted(PALETTES))
    w, h = args.width, args.height

    body = STYLES[style](rng, w, h, PALETTES[palette])
    print(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">')
    print("\n".join(body))
    print(grain(w, h))
    print("</svg>")
    print(f"style={style} palette={palette} seed={seed}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
