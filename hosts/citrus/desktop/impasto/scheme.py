import json
import sys

scripts, image = sys.argv[1:3]
sys.path.insert(0, scripts)

import theme_manager

palette = theme_manager.build_palette(image)
background = palette["background"]


def readable(key):
    return theme_manager.lift(palette[key], theme_manager.MIN_CONTRAST, background)


def bright(key):
    return theme_manager.brighten(palette[key], background)


slots = {
    "base00": background,
    "base01": palette["surface"],
    "base02": palette["surfaceHover"],
    "base03": palette["border"],
    "base04": palette["textMuted"],
    "base05": palette["text"],
    "base06": palette["text"],
    "base07": palette["text"],
    "base08": readable("red"),
    "base09": readable("accentHover"),
    "base0A": readable("yellow"),
    "base0B": readable("green"),
    "base0C": bright("accent"),
    "base0D": readable("accent"),
    "base0E": readable("blue"),
    "base0F": bright("accentHover"),
}

json.dump(
    {"scheme": "impasto", "author": "impasto"}
    | {slot: value.removeprefix("#") for slot, value in slots.items()},
    sys.stdout,
)
