{ config, pkgs, ... }:
let
  theme = import ../../themes/tokyo-night-black {
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
