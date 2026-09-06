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
  hyprlandSession = "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland";
in
{
  nixpkgs.overlays = [
    (_final: _previous: {
      hyprland =
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.overrideAttrs
          (old: {
            # Upstream reads VERSION while evaluating and builds hyprtester.
            src = inputs.hyprland;
            patches = (old.patches or [ ]) ++ [ ./hyprland-ime-modifiers.patch ];
          });
    })
  ];

  nix = {
    # Leave room for the physical desktop during builds.
    settings = {
      max-jobs = 2;
      cores = 6;
    };
    daemonIOSchedClass = "idle";
  };
  systemd.services.nix-daemon.serviceConfig.Nice = 10;

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce false;
      limine = {
        enable = true;
        maxGenerations = 10;
        style = {
          # Dell AW3926QW; Limine falls back if UEFI lacks this mode.
          interface.resolution = "5120x2160";
          graphicalTerminal.font.scale = "2x2";
          wallpapers = [
            (pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/CachyOS/cachyos-wallpapers/91875ae10c410e7e2b81f8af0ef44e7f7aea114d/usr/share/wallpapers/cachyos-wallpapers/limine-splash.png";
              hash = "sha256-+S8J+XKbIpfNKbN76/yBEpbYx3FUiXQ5Ut5LmBeFAt8=";
            })
          ];
        };
      };
    };
    kernelPackages = pkgs.linuxPackages_cachyos;
    initrd.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
  };

  hardware.nvidia = {
    # Keep the driver cached for the physical workstation's CachyOS kernel.
    package = pkgs.nvidia_cachyos;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
  };
  hardware.bluetooth = {
    enable = true;
    settings.General = {
      Experimental = true;
      # LE Audio requires the kernel's ISO sockets.
      KernelExperimental = "6fbaf188-05e0-496a-9885-d6ddfdb4e03e";
    };
  };

  imports = [
    ./browser.nix
    ./codex.nix
    ./desktop.nix
    ./dynamic-island.nix
    ./fingerprint.nix
    ./hardware-configuration.nix
    ./ipad.nix
    ./shell.nix
  ];

  networking.hostName = "citrus";
  home-manager.users.keewai.imports = [ ../../home/keewai/citrus ];

  stylix = {
    enable = true;
    autoEnable = false;
    image = theme.wallpaper;
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
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.noto-fonts-cjk-sans;
        name = "Noto Sans CJK JP";
      };
      sizes = {
        applications = 10;
        desktop = 10;
        popups = 10;
        terminal = 11;
      };
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
      font-packages.enable = false;
      fontconfig.enable = true;
      gtk.enable = true;
      # Personal Qt tools and themes are provided by Home Manager.
      qt.enable = false;
    };
  };

  users.users.keewai.extraGroups = [
    "audio"
    "i2c"
    "video"
  ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  services = {
    xserver.videoDrivers = [ "nvidia" ];
    udev.extraRules = ''
      # Keep the discrete GPU path stable across DRM device enumeration changes.
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia"
    '';
    blueman.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.extraConfig."51-inzone-le-audio" = {
        "monitor.bluez.rules" = [
          {
            matches = [ { "device.name" = "bluez_card.88_92_CC_D0_86_D2"; } ];
            # Keep duplex LC3 at 48 kHz with aligned frames for the MT7925 receiver.
            actions.update-props."bluez5.bap.preset" = "48_4_1";
          }
        ];
      };
    };

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

  environment = {
    sessionVariables = {
      AQ_DRM_DEVICES = "/dev/dri/nvidia";
      LIBVA_DRIVER_NAME = "nvidia";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NIXOS_OZONE_WL = "1";
    };
  };

  system.stateVersion = "26.05";
}
