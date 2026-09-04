{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  theme = import ./theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  displayOutput = "Virtual-1";
  hyprlandConfig = pkgs.writeText "hyprland.lua" (
    "local display_output = ${builtins.toJSON displayOutput}\n" + builtins.readFile ./hyprland.lua
  );

  hyprlandSession =
    "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland"
    + " -- -- --config ${hyprlandConfig}";
in
{
  boot.kernelPackages = pkgs.linuxPackages_cachyos.extend (
    _: _: {
      inherit (pkgs.linuxPackages_latest) hyperv-daemons;
    }
  );

  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-hazkey.nixosModules.hazkey
    ./browser
    ./codex.nix
    ./desktop.nix
    ./hardware-configuration.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.keewai.home.stateVersion = "26.05";
  };

  networking.hostName = "citrus-vm";

  stylix = {
    enable = true;
    autoEnable = false;
    base16Scheme = {
      scheme = "Tokyo Night";
      slug = "tokyo-night";
      author = "folke";
      base00 = "1a1b26";
      base01 = "292e42";
      base02 = "3b4261";
      base03 = "565f89";
      base04 = "a9b1d6";
      base05 = "c0caf5";
      base06 = "89ddff";
      base07 = "b4f9f8";
      base08 = "f7768e";
      base09 = "ff9e64";
      base0A = "e0af68";
      base0B = "9ece6a";
      base0C = "7dcfff";
      base0D = "7aa2f7";
      base0E = "bb9af7";
      base0F = "db4b4b";
    };
    polarity = "dark";
    inherit (theme) cursor;
    fonts.sizes = {
      applications = 10;
      desktop = 10;
      popups = 10;
      terminal = 11;
    };
    icons = {
      enable = true;
      inherit (theme.icon) package;
      dark = theme.icon.name;
      light = theme.icon.name;
    };
    targets = {
      chromium.enable = true;
      console.enable = true;
      font-packages.enable = true;
      fontconfig.enable = true;
      gtk.enable = true;
      qt.enable = true;
    };
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      addons = [ theme.fcitx5.addon ];
      waylandFrontend = true;

      settings = {
        addons.classicui.globalSection = {
          DarkTheme = theme.fcitx5.themeName;
          Font = theme.fcitx5.font;
          MenuFont = theme.fcitx5.menuFont;
          Theme = theme.fcitx5.themeName;
          TrayFont = theme.fcitx5.trayFont;
          UseAccentColor = false;
          UseDarkTheme = false;
        };

        inputMethod = {
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "hazkey";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-us";
            Layout = "";
          };
          "Groups/0/Items/1" = {
            Name = "hazkey";
            Layout = "";
          };
          GroupOrder."0" = "Default";
        };
      };
    };
  };

  users.users.keewai.extraGroups = [
    "audio"
    "video"
  ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  programs.hyprlock.enable = true;

  services = {
    hazkey.enable = true;

    greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = hyprlandSession;
          user = "keewai";
        };

        default_session = {
          command =
            "${lib.getExe pkgs.tuigreet} --time --remember --remember-user-session"
            + " --theme ${lib.escapeShellArg theme.tuigreetTheme}"
            + " --cmd ${lib.escapeShellArg hyprlandSession}";
        };
      };
    };
  };

  security.rtkit.enable = true;

  fonts.packages = [
    pkgs.adwaita-fonts
    pkgs.iosevka
    pkgs.nerd-fonts.caskaydia-cove
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.symbols-only
    pkgs.noto-fonts
  ];

  environment = {
    systemPackages = [ pkgs.gws ];

    sessionVariables = {
      AQ_DRM_DEVICES = "/dev/dri/card1";
      LIBGL_ALWAYS_SOFTWARE = "1";
      NIXOS_OZONE_WL = "1";
    };
  };

  system.stateVersion = "26.05";
}
