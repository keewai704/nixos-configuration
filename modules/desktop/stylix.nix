{ inputs, pkgs, ... }:
let
  theme = import ../../themes/tokyo-night-black { inherit pkgs; };
in
{
  imports = [ inputs.stylix.nixosModules.stylix ];

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
