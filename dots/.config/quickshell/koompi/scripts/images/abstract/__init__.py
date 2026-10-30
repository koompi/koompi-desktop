"""Abstract wallpaper styles. Each module maps style names to functions
`(rng, width, height, palette) -> [svg fragments]`; STYLES gathers them in a
fixed order, since a seed must keep drawing the same picture."""

from . import classic, graphic, soft

STYLES = {}
for _module in (classic, soft, graphic):
    STYLES.update(_module.STYLES)
