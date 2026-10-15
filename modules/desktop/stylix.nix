{ inputs, theme, ... }:
{
  imports = [ inputs.stylix.nixosModules.stylix ];

  stylix = theme.stylix // {
    homeManagerIntegration.autoImport = false;
    targets = {
      console.enable = true;
      font-packages.enable = false;
      fontconfig.enable = true;
      gtk.enable = true;
      qt.enable = false;
    };
  };
}
