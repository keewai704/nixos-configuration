{
  config,
  lib,
  pkgs,
  ...
}:
let
  theme = import ../../../themes/tokyo-night-black {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  hyprlandConfig = pkgs.writeTextFile {
    name = "hyprland.lua";
    text =
      "local theme = ${lib.generators.toLua { } theme.hyprland}\n" + builtins.readFile ./hyprland.lua;
    checkPhase = ''
      HOME="$TMPDIR" XDG_RUNTIME_DIR="$TMPDIR" ${lib.getExe pkgs.hyprland} --verify-config -c "$target"
    '';
  };

in
{
  xdg.configFile."hypr/hyprland.lua".source = hyprlandConfig;

  stylix.targets.hyprland.enable = false;
}
