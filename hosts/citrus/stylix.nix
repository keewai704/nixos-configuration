{ config, pkgs, ... }:
let
  theme = import ../../home/keewai/desktop/theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
in
{
  stylix = theme.stylix // {
    homeManagerIntegration.autoImport = false;
    targets = {
      chromium.enable = true;
      console.enable = true;
      font-packages.enable = false;
      fontconfig.enable = true;
      gtk.enable = true;
      qt.enable = false;
    };
  };
}
