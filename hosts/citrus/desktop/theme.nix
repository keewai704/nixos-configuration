{
  config,
  lib,
  pkgs,
  ...
}:
let
  iconTheme = "Papirus-Dark";
  cursor = config.home-manager.users.keewai.home.pointerCursor;

  qtctConfig =
    name:
    lib.generators.toINI { } {
      Appearance = {
        color_scheme_path = "${config.users.users.keewai.home}/.config/${name}/colors/noctalia.conf";
        custom_palette = true;
        icon_theme = iconTheme;
        style = "Fusion";
      };
    };
in
{
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  environment.etc = lib.genAttrs [ "xdg/gtk-3.0/settings.ini" "xdg/gtk-4.0/settings.ini" ] (_: {
    text = lib.generators.toINI { } {
      Settings = {
        gtk-icon-theme-name = iconTheme;
        gtk-cursor-theme-name = cursor.name;
        gtk-cursor-theme-size = cursor.size;
        gtk-im-module = "fcitx";
      };
    };
  });

  home-manager.users.keewai = {
    home.packages = [
      pkgs.adw-gtk3
      pkgs.papirus-icon-theme
    ];

    home.pointerCursor = {
      enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    dconf.settings."org/gnome/desktop/interface" = {
      icon-theme = iconTheme;
      cursor-theme = cursor.name;
      cursor-size = cursor.size;
    };

    xdg.configFile = {
      "starship.toml".enable = false;
      "qt5ct/qt5ct.conf".text = qtctConfig "qt5ct";
      "qt6ct/qt6ct.conf".text = qtctConfig "qt6ct";
    };

    programs.nixcord.config.enabledThemes = [ "noctalia.theme.css" ];
  };
}
