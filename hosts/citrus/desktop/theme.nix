{
  impastoSeed,
  lib,
  pkgs,
  ...
}:
let
  hex = lib.removePrefix "#";

  ansi = with impastoSeed; [
    background
    red
    green
    yellow
    blue
    accent
    accentHover
    text
    border
    red
    green
    yellow
    blue
    accent
    accentHover
    text
  ];
in
{
  fonts = {
    packages = [
      pkgs.nerd-fonts.jetbrains-mono
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-cjk-serif
      pkgs.udev-gothic
      pkgs.noto-fonts-color-emoji
    ];
    fontconfig.defaultFonts = {
      sansSerif = [
        "Hiragino Sans"
        "Noto Sans CJK JP"
      ];
      serif = [
        "Hiragino Mincho ProN"
        "Noto Serif CJK JP"
      ];
      monospace = [ "UDEV Gothic" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  programs.dconf.enable = true;

  console.colors = map hex ansi;

  boot.loader.limine.style = {
    backdrop = hex impastoSeed.background;
    graphicalTerminal = {
      background = hex impastoSeed.background;
      foreground = hex impastoSeed.text;
      brightBackground = hex impastoSeed.border;
      brightForeground = hex impastoSeed.text;
      palette = lib.concatMapStringsSep ";" hex (lib.take 8 ansi);
      brightPalette = lib.concatMapStringsSep ";" hex (lib.drop 8 ansi);
    };
  };

  programs.chromium.extraOpts.BrowserThemeColor = impastoSeed.background;

  home-manager.users.keewai = {
    home.pointerCursor = {
      enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };

    gtk = {
      enable = true;
      font = {
        name = "Hiragino Sans";
        size = 12;
      };
      iconTheme = {
        package = pkgs.papirus-icon-theme;
        name = "Papirus-Dark";
      };
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = 1;
        gtk-im-module = "fcitx";
      };
      gtk4.extraConfig.gtk-im-module = "fcitx";
    };

    dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

    programs.kitty.font = {
      package = pkgs.udev-gothic;
      name = "UDEV Gothic";
      size = 12;
    };

    programs.bat.config.theme = "ansi";
  };
}
