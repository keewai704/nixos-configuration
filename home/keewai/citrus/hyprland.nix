{
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  theme = import ../../../hosts/citrus/theme.nix {
    inherit pkgs;
    colors = osConfig.lib.stylix.colors;
  };
  hyprlandConfig = pkgs.writeTextFile {
    name = "hyprland.lua";
    text =
      "local theme = ${lib.generators.toLua { } theme.hyprland}\n"
      + builtins.readFile ../../../hosts/citrus/hyprland.lua;
    checkPhase = ''
      cp "$target" "$TMPDIR/check.lua"
      echo 'assert(hl.get_config("decoration:blur:variant") == 8, "acrylic blur must be enabled")' >> "$TMPDIR/check.lua"
      HOME="$TMPDIR" XDG_RUNTIME_DIR="$TMPDIR" ${lib.getExe pkgs.hyprland} --verify-config -c "$TMPDIR/check.lua"
    '';
  };

in
{
  xdg.configFile."hypr/hyprland.lua".source = hyprlandConfig;

}
