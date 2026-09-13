{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  theme = import ../../../hosts/citrus/theme.nix {
    inherit pkgs;
    colors = osConfig.lib.stylix.colors;
  };
in
{
  imports = [ ./wallpaper.nix ];
  disabledModules = [ ../citrus/hyprland.nix ];
  xdg.configFile."hypr/hyprland.lua".source = pkgs.writeTextFile {
    name = "citrus-vm-hyprland.lua";
    text =
      "local theme = ${lib.generators.toLua { } theme.hyprland}\n"
      + builtins.readFile ../../../hosts/citrus/hyprland.lua
      + ''
        -- Hyper-V provides a synthetic display; use CPU rendering and simple effects.
        hl.config({
          cursor = { no_hardware_cursors = true },
          render = { cm_auto_hdr = 0 },
          decoration = {
            blur = { enabled = false },
            shadow = { enabled = false },
            active_opacity = 1.0,
            inactive_opacity = 1.0,
          },
        })
        hl.animation({ leaf = "global", enabled = false })
      '';
    checkPhase = ''
      HOME="$TMPDIR" XDG_RUNTIME_DIR="$TMPDIR" ${lib.getExe pkgs.hyprland} --verify-config -c "$target"
    '';
  };

  programs.hyprlock.settings.auth.fingerprint.enabled = lib.mkForce false;
  programs.dynamic-island.settings.reducedMotion = lib.mkForce true;
}
