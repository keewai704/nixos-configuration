{
  impastoPaletteHook,
  pkgs,
  ...
}:
let
  mangohudConfig = pkgs.writers.writePython3Bin "mangohud-config" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    c = {key: value.removeprefix("#") for key, value in json.load(sys.stdin).items()}
    load = f"{c['green']}, {c['yellow']}, {c['red']}"

    settings = {
        "toggle_hud": "Home",
        "font_size": 16,
        "background_alpha": 1.0,
        "background_color": c["background"],
        "text_color": c["text"],
        "text_outline_color": c["background"],
        "gpu_color": c["green"],
        "cpu_color": c["accentHover"],
        "vram_color": c["blue"],
        "ram_color": c["blue"],
        "engine_color": c["blue"],
        "io_color": c["yellow"],
        "frametime_color": c["green"],
        "media_player_color": c["text"],
        "wine_color": c["blue"],
        "battery_color": c["textMuted"],
        "gpu_load_color": load,
        "cpu_load_color": load,
        "fps_color": load,
    }

    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "MangoHud", "MangoHud.conf")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("".join(f"{key}={value}\n" for key, value in settings.items()))
  '';
in
{
  home-manager.users.keewai = {
    imports = [ (impastoPaletteHook "mangohud" "MangoHud/MangoHud.conf" mangohudConfig) ];

    programs.mangohud.enable = true;
  };
}
