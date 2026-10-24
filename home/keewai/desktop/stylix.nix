{
  config,
  pkgs,
  ...
}:
let
  qtctSettings = version: {
    Appearance = {
      color_scheme_path = "${config.xdg.configHome}/qt${version}ct/colors/noctalia.conf";
      custom_palette = true;
      icon_theme = config.gtk.iconTheme.name;
      standard_dialogs = "xdgdesktopportal";
      style = "Fusion";
    };
    Fonts = with config.stylix.fonts; {
      fixed = ''"${monospace.name},${toString sizes.applications}"'';
      general = ''"${sansSerif.name},${toString sizes.applications}"'';
    };
  };
in
{
  stylix.targets = {
    font-packages.enable = true;
    gtk = {
      enable = true;
      colors.enable = false;
    };
    kitty.colors.enable = false;
    fcitx5.colors.enable = false;
  };

  home.packages = [
    pkgs.adw-gtk3
    pkgs.noto-fonts
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts.sansSerif = [ config.stylix.fonts.sansSerif.name ];
  };

  gtk.gtk2.enable = false;

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "Fusion";
    qt5ctSettings = qtctSettings "5";
    qt6ctSettings = qtctSettings "6";
  };
}
