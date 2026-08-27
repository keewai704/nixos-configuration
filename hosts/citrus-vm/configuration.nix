{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hyprlandConfig = pkgs.writeText "citrus-vm-hyprland.conf" ''
    monitor = Virtual-1, 1600x900@60, 0x0, 1

    $mainMod = SUPER
    $terminal = kitty

    exec-once = uwsm app -- fcitx5 --replace

    input {
      kb_layout = us
      follow_mouse = 1
    }

    general {
      border_size = 2
      gaps_in = 5
      gaps_out = 10
      layout = dwindle
    }

    decoration {
      rounding = 8
    }

    bind = $mainMod, Return, exec, uwsm app -- $terminal
    bind = $mainMod, Q, killactive,
    bind = $mainMod SHIFT, E, exit,
    bind = $mainMod, F, fullscreen,
    bind = $mainMod, V, togglefloating,

    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5

    bindm = $mainMod, mouse:272, movewindow
    bindm = $mainMod, mouse:273, resizewindow
  '';

  hyprlandSession =
    "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland"
    + " -- --config ${hyprlandConfig}";
in
{
  imports = [
    inputs.nix-hazkey.nixosModules.hazkey
    ../../profiles/networkmanager.nix
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
