{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  displayOutput = "Virtual-1";
  hyprlandConfig = pkgs.writeText "hyprland.lua" (
    "local display_output = ${builtins.toJSON displayOutput}\n" + builtins.readFile ./hyprland.lua
  );

  hyprlandSession = "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland";
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
    ./browser.nix
    ./codex.nix
    ./desktop.nix
    ./hardware-configuration.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.keewai = {
      home.stateVersion = "26.05";
      xdg.configFile."hypr/hyprland.lua".source = hyprlandConfig;
      systemd.user.tmpfiles.rules = [ "f %h/.config/hypr/hyprland-gui.lua 0644 - - -" ];
    };
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
    cursor = {
      package = pkgs.colloid-cursors;
      name = "Colloid-dark-cursors";
      size = 24;
    };
    fonts.sizes = {
      applications = 10;
      desktop = 10;
      popups = 10;
      terminal = 11;
    };
    icons = {
      enable = true;
      package = pkgs.colloid-icon-theme;
      dark = "Colloid-Dark";
      light = "Colloid-Dark";
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
      addons = [ pkgs.fcitx5-tokyonight ];
      waylandFrontend = true;

      settings = {
        addons.classicui.globalSection = {
          DarkTheme = "Tokyonight-Storm";
          Font = "Noto Sans CJK JP 10";
          MenuFont = "Noto Sans CJK JP 11";
          Theme = "Tokyonight-Storm";
          TrayFont = "Noto Sans CJK JP Bold 10";
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
            + " --theme 'border=blue;title=magenta;text=white;time=cyan;container=black;greet=white;prompt=blue;input=white;action=blue;button=magenta'"
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
