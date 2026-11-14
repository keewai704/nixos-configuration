{
  impastoPaletteHook,
  pkgs,
  ...
}:
let
  quickCss = pkgs.writers.writePython3Bin "equicord-quick-css" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    c = json.load(sys.stdin)


    def shades(name, color):
        steps = (
            f"color-mix(in oklch, {color}, white 20%)",
            f"color-mix(in oklch, {color}, white 10%)",
            color,
            f"color-mix(in oklch, {color}, black 10%)",
            f"color-mix(in oklch, {color}, black 20%)",
        )
        return "".join(f"    --{name}-{index}: {step};\n" for index, step in enumerate(steps, 1))


    css = f""":root:root {{
        --text-0: {c["accentText"]};
        --text-1: {c["text"]};
        --text-2: color-mix(in oklch, {c["text"]}, {c["textMuted"]} 33%);
        --text-3: color-mix(in oklch, {c["text"]}, {c["textMuted"]} 66%);
        --text-4: {c["textMuted"]};
        --text-5: color-mix(in oklch, {c["textMuted"]}, {c["background"]} 40%);

        --bg-1: {c["border"]};
        --bg-2: {c["surfaceHover"]};
        --bg-3: {c["surface"]};
        --bg-4: {c["background"]};
        --hover: color-mix(in srgb, {c["textMuted"]} 10%, transparent);
        --active: color-mix(in srgb, {c["textMuted"]} 20%, transparent);
        --active-2: color-mix(in srgb, {c["textMuted"]} 30%, transparent);

    {shades("purple", c["accent"])}{shades("red", c["red"])}{shades("green", c["green"])}{shades("blue", c["blue"])}{shades("yellow", c["yellow"])}}}
    """

    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "Equicord", "settings", "quickCss.css")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(css)
  '';
in
{
  home-manager.users.keewai = {
    imports = [ (impastoPaletteHook "discord" "Equicord/settings/quickCss.css" quickCss) ];

    stylix.targets.vencord.enable = false;

    home.packages = [ (pkgs.discord.override { withEquicord = true; }) ];
  };
}
