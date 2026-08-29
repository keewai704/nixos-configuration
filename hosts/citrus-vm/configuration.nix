{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hyprlandConfig = ./hyprland.lua;

  hyprlandSession =
    "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland"
    + " -- -- --config ${hyprlandConfig}";
in
{
  imports = [
    inputs.nix-hazkey.nixosModules.hazkey
    ../../profiles/desktop-client.nix
    ../../profiles/networkmanager.nix
    ../../profiles/tailnet-admin.nix
    ../../profiles/tailnet-web.nix
    ../../profiles/uefi-systemd-boot.nix
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

  services = {
    hazkey.enable = true;
    tailnetWeb.enable = true;

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
          user = "greeter";
        };
      };
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };

  security.rtkit.enable = true;

  hardware.graphics.enable = true;

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];

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

  home-manager.users.keewai.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
