{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hyprlandConfig = ./hyprland.lua;
  wallpaper = ./assets/videoframe_150744_10240x4320_clean-faithful.png;

  hyprlandSession =
    "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland"
    + " -- -- --config ${hyprlandConfig}";
in
{
  imports = [
    inputs.nix-hazkey.nixosModules.hazkey
    ../../modules/browser-environment.nix
    ../../modules/desktop-client.nix
    ../../modules/networkmanager.nix
    ../../modules/tailnet-admin.nix
    ../../modules/uefi-systemd-boot.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "citrus-vm";

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      waylandFrontend = true;

      settings.inputMethod = {
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

  users.users.keewai.extraGroups = [
    "audio"
    "video"
  ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  home-manager.users.keewai.systemd.user.services.citrus-wallpaper = {
    Unit = {
      Description = "Citrus desktop wallpaper";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.swaybg} --output Virtual-1" + " --image ${wallpaper} --mode fill";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

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
            + " --cmd ${lib.escapeShellArg hyprlandSession}";
        };
      };
    };
  };

  security.rtkit.enable = true;

  fonts.packages = [ pkgs.noto-fonts ];

  environment = {
    systemPackages = [
      pkgs.kitty
    ];

    sessionVariables = {
      AQ_DRM_DEVICES = "/dev/dri/card1";
      LIBGL_ALWAYS_SOFTWARE = "1";
      NIXOS_OZONE_WL = "1";
    };
  };

  system.stateVersion = "26.05";
}
