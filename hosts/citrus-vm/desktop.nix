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

  home-manager.users.keewai = { config, ... }: {
    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      configFile."user-dirs.dirs".force = true;
      configFile."k4/theme.json".text = builtins.toJSON theme.quickShell;
      configFile."qt5ct/colors/${theme.qt.colorSchemeName}.conf".text = theme.qt.colorScheme;
      configFile."qt6ct/colors/${theme.qt.colorSchemeName}.conf".text = theme.qt.colorScheme;
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
      style.name = theme.qt.styleName;

      qt5ctSettings.Appearance = {
        color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/${theme.qt.colorSchemeName}.conf";
        custom_palette = true;
        icon_theme = theme.icon.name;
        standard_dialogs = "xdgdesktopportal";
        style = theme.qt.styleName;
      };
      qt6ctSettings.Appearance = {
        color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/${theme.qt.colorSchemeName}.conf";
        custom_palette = true;
        icon_theme = theme.icon.name;
        standard_dialogs = "xdgdesktopportal";
        style = theme.qt.styleName;
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
