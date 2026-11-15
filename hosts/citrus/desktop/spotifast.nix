{
  impastoPaletteHook,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "impasto.json";

  writeTheme = pkgs.writers.writePython3Bin "spotifast-theme" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    c = json.load(sys.stdin)

    data = {
        "base": "dark",
        "colors": {
            "window": c["background"],
            "panel": c["surface"],
            "surface": c["surface"],
            "surface_hover": c["surfaceHover"],
            "surface_active": c["border"],
            "outline": c["surfaceHover"],
            "text": c["text"],
            "secondary": c["textMuted"],
            "dim": c["textMuted"],
            "accent": c["accent"],
            "accent_hover": c["accentHover"],
            "on_accent": c["accentText"],
            "danger": c["red"],
            "warning": c["yellow"],
        },
    }

    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "spotifast", "themes", "${theme}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
  '';
in
{
  networking.firewall.allowedUDPPorts = [ 5353 ];

  home-manager.users.keewai = {
    imports = [ (impastoPaletteHook "spotifast" "spotifast/themes/${theme}" writeTheme) ];

    home.packages = [ pkgs.spotifast ];

    home.activation.spotifastTheme = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings="''${XDG_CONFIG_HOME:-$HOME/.config}/spotifast/settings.json"
      run mkdir -p "$(dirname "$settings")"
      [ -s "$settings" ] || echo '{}' > "$settings"
      merged="$(mktemp "$settings.XXXXXX")"
      ${lib.getExe pkgs.jq} --arg theme ${theme} '.custom_theme = $theme' "$settings" > "$merged"
      run mv "$merged" "$settings"
    '';
  };
}
