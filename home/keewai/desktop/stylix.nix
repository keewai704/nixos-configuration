{
  config,
  inputs,
  pkgs,
  ...
}:
let
  theme = import ../../../themes/tokyo-night-black { inherit pkgs; };
in
{
  imports = [ inputs.stylix.homeModules.stylix ];

  stylix = theme.stylix // {
    overlays.enable = false;
    targets = {
      font-packages.enable = true;
      gtk = {
        enable = true;
        flatpakSupport.enable = false;
      };
      qt = {
        enable = true;
        standardDialogs = "xdgdesktopportal";
      };
    };
  };

  home.packages = [ pkgs.noto-fonts ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts.sansSerif = [ config.stylix.fonts.sansSerif.name ];
  };

  gtk = {
    colorScheme = "dark";
    gtk2.enable = false;
  };
}
