{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  stylixTheme = import ../../../themes/tokyo-night-black {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  islandTheme = {
    surface = "#${stylixTheme.semantic.surface}";
    hover = "#${stylixTheme.semantic.surfaceHigh}";
    border = "#${stylixTheme.semantic.border}";
    text = "#${stylixTheme.semantic.text}";
    muted = "#${stylixTheme.semantic.muted}";
    accent = "#${stylixTheme.semantic.accent}";
    onAccent = "#${stylixTheme.semantic.desktopBackground}";
    fontFamily = config.stylix.fonts.sansSerif.name;
    fontSize = config.stylix.fonts.sizes.desktop * 96.0 / 72.0;
  };

in
{
  imports = [ inputs.dynamic-island.homeManagerModules.default ];
  programs.dynamic-island = {
    enable = true;
    package = lib.mkDefault (
      pkgs.callPackage "${inputs.dynamic-island}/package.nix" {
        quickshell = pkgs.callPackage ../../../pkgs/quickshell { };
      }
    );
    theme = islandTheme;
    defaultWallpaper = config.stylix.image;
    settings = {
      notch = true;
      hover = true;
      dnd = false;
      reducedMotion = false;
    };
  };
}
