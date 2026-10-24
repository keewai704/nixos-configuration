{ inputs, theme, ... }:
{
  imports = [ inputs.stylix.nixosModules.stylix ];

  stylix = theme.stylix // {
    targets = {
      console.enable = true;
      font-packages.enable = false;
      fontconfig.enable = true;
      gtk.enable = true;
      qt.enable = false;
    };
  };
}
