{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  theme = import ../../../themes/tokyo-night-black {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
in
{
  config = lib.mkIf osConfig.virtualisation.hypervGuest.enable {
    xdg.configFile."hypr/hyprland.lua".source = lib.mkForce (
      pkgs.writeTextFile {
        name = "citrus-vm-hyprland.lua";
        text =
          "local theme = ${lib.generators.toLua { } theme.hyprland}\n"
          + config.programs.dynamic-island.hyprland.config
          + builtins.readFile ./hyprland.lua
          + ''
            hl.config({
              cursor = { no_hardware_cursors = true },
              render = { cm_auto_hdr = 0 },
              misc = { disable_splash_rendering = true },
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
      }
    );

    services.hyprpaper.enable = lib.mkForce false;
    programs.dynamic-island = {
      defaultWallpaper = lib.mkForce null;
      settings.reducedMotion = lib.mkForce true;
    };
    programs.hyprlock.settings.background = lib.mkForce [
      {
        monitor = "";
        color = "rgb(${config.lib.stylix.colors.base00})";
      }
    ];
  };
}
