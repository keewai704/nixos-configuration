import json
import sys

scripts, image = sys.argv[1:3]
sys.path.insert(0, scripts)

import theme_manager

palette = theme_manager.build_palette(image)


def darken(value, amount):
    red, green, blue = theme_manager.hex_to_rgb(value)
    return theme_manager.rgb_to_hex(*(channel * (1 - amount) for channel in (red, green, blue)))


palette |= {
    "background": "#000000",
    "surface": darken(palette["surface"], 0.6),
    "surfaceHover": darken(palette["surfaceHover"], 0.4),
    "border": darken(palette["border"], 0.25),
}

json.dump(palette, sys.stdout)
