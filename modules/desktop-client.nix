{
  lib,
  pkgs,
  ...
}:

let
  chatgptDesktop = pkgs.callPackage ../pkgs/chatgpt-desktop { };
  gtkTheme = pkgs.catppuccin-gtk.override {
    accents = [ "blue" ];
    size = "standard";
    tweaks = [ "rimless" ];
    variant = "mocha";
  };
  iconTheme = pkgs.colloid-icon-theme.override {
    schemeVariants = [ "catppuccin" ];
  };
  cursorTheme = pkgs.colloid-cursors;

  gtkThemeName = "catppuccin-mocha-blue-standard+rimless";
  iconThemeName = "Colloid-Catppuccin-Dark";
  cursorThemeName = "Colloid-dark-cursors";
in
{
  imports = [ ./chatgpt-desktop-extensions.nix ];

  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "chatgpt-desktop";

  environment = {
    systemPackages = [
      chatgptDesktop
      pkgs.xarchiver
    ];

    sessionVariables = {
      XCURSOR_SIZE = "24";
      XCURSOR_THEME = cursorThemeName;
    };
  };

  home-manager.users.keewai = {
    gtk = {
      enable = true;
      colorScheme = "dark";
      gtk2.enable = false;

      theme = {
        package = gtkTheme;
        name = gtkThemeName;
      };

      gtk4.theme = {
        package = gtkTheme;
        name = gtkThemeName;
      };

      iconTheme = {
        package = iconTheme;
        name = iconThemeName;
      };
    };

    home.pointerCursor = {
      enable = true;
      package = cursorTheme;
      name = cursorThemeName;
      size = 24;
      gtk.enable = true;
      hyprcursor.enable = false;
    };

    programs.kitty = {
      enable = true;
      themeFile = "Catppuccin-Mocha";
    };
  };

  programs = {
    dconf.enable = true;

    thunar = {
      enable = true;
      plugins = [
        pkgs.thunar-archive-plugin
        pkgs.thunar-volman
      ];
    };
  };

  services = {
    gnome.at-spi2-core.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };

  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";
}
