{
  config,
  lib,
  pkgs,
  ...
}:

let
  theme = import ./theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  chatgptDesktop = pkgs.callPackage ../../pkgs/chatgpt-desktop { };
in
{
  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "chatgpt-desktop";

  environment.systemPackages = [
    chatgptDesktop
    pkgs.xarchiver
  ];

  home-manager.users.keewai = {
    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      configFile."user-dirs.dirs".force = true;
      configFile."k4/theme.json".text = builtins.toJSON theme.quickShell;
    };

    programs.kitty.enable = true;

    gtk = {
      colorScheme = "dark";
      gtk2.enable = false;
    };

    stylix.targets = {
      fcitx5.enable = false;
      firefox.enable = false;
      gtk = {
        enable = true;
        flatpakSupport.enable = false;
      };
      hyprland.enable = false;
      kitty.enable = true;
      qt = {
        enable = true;
        standardDialogs = "xdgdesktopportal";
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
