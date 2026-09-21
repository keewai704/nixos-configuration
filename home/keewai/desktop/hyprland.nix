{
  config,
  lib,
  pkgs,
  ...
}:
let
  hyprlandConfig = pkgs.writeTextFile {
    name = "hyprland.lua";
    text =
      "local cursor = ${lib.generators.toLua { } { inherit (config.stylix.cursor) name size; }}\n"
      + builtins.readFile ./hyprland.lua;
    checkPhase = ''
      HOME="$TMPDIR" XDG_RUNTIME_DIR="$TMPDIR" ${lib.getExe pkgs.hyprland} --verify-config -c "$target"
    '';
  };

in
{
  xdg.configFile."hypr/hyprland.lua".source = hyprlandConfig;

  stylix.targets.hyprland.enable = false;
}
