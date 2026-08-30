{
  lib,
  pkgs,
  ...
}:

let
  theme = import ./theme.nix { inherit pkgs; };
  chatgptDesktop = pkgs.callPackage ../../pkgs/chatgpt-desktop { };
in
{
  imports = [ ./codex.nix ];

  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "chatgpt-desktop";

  environment = {
    systemPackages = [
      chatgptDesktop
      pkgs.xarchiver
    ];

    sessionVariables = {
      XCURSOR_SIZE = toString theme.cursor.size;
      XCURSOR_THEME = theme.cursor.name;
    };
  };

  home-manager.users.keewai = {
    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      configFile."user-dirs.dirs".force = true;
    };

    gtk = {
      enable = true;
      colorScheme = theme.scheme;
      gtk2.enable = false;

      iconTheme = theme.icon;
      theme = theme.gtk;
      gtk4.theme = theme.gtk;
    };

    home.pointerCursor = {
      enable = true;
      inherit (theme.cursor) name package size;
      gtk.enable = true;
      hyprcursor.enable = false;
    };

    programs.kitty = {
      enable = true;
      settings = theme.kitty.settings;
    };

    qt = {
      enable = true;
      platformTheme.name = "qtct";
      style.name = "kvantum";

      kvantum = {
        enable = true;
        themes = [ theme.qt.package ];
        settings.General.theme = theme.qt.themeName;
      };

      qt5ctSettings.Appearance = {
        icon_theme = theme.icon.name;
        standard_dialogs = "xdgdesktopportal";
        style = "kvantum";
      };
      qt6ctSettings.Appearance = {
        icon_theme = theme.icon.name;
        standard_dialogs = "xdgdesktopportal";
        style = "kvantum";
      };
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
