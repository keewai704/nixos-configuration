{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hyprlandSession = "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland";
in
{
  nixpkgs.overlays = [
    (_final: prev: {
      hyprland = prev.hyprland.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./hyprland-ime-modifiers.patch ];
      });
    })
  ];

  nix = {
    # 8 cores / 16 threads and 32 GiB RAM: leave room for the desktop during builds.
    settings = {
      max-jobs = 2;
      cores = 6;
    };
    daemonIOSchedClass = "idle";
  };
  systemd.services.nix-daemon.serviceConfig.Nice = 10;

  boot.kernelPackages = pkgs.linuxPackages_cachyos;
  boot.initrd.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  hardware.nvidia = {
    # Use Chaotic's driver built and cached for the CachyOS kernel.
    package = pkgs.nvidia_cachyos;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
  };

  hardware.bluetooth.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];
  services.udev.extraRules = ''
    # Keep the discrete GPU path stable across DRM device enumeration changes.
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia"
  '';

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
      xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;
      systemd.user.tmpfiles.rules = [ "f %h/.config/hypr/hyprland-gui.lua 0644 - - -" ];
    };
  };

  networking.hostName = "citrus";

  stylix = {
    enable = true;
    autoEnable = false;
    base16Scheme = {
      # Match 43PR's black/white surfaces and its Rofi Tokyo Night accents.
      scheme = "43PR Black";
      slug = "43pr-black";
      author = "43PR / folke";
      base00 = "000000";
      base01 = "101010";
      base02 = "242832";
      base03 = "6f6f6f";
      base04 = "8b93a7";
      base05 = "ffffff";
      base06 = "ffffff";
      base07 = "ffffff";
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
    fonts = {
      sansSerif = {
        package = pkgs.adwaita-fonts;
        name = "Adwaita Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sizes = {
        applications = 11;
        desktop = 11;
        popups = 11;
        terminal = 10;
      };
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
    blueman.enable = true;
    hazkey.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
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
            + " --theme 'border=blue;title=magenta;text=white;time=cyan;container=black;greet=white;prompt=blue;input=white;action=blue;button=magenta'"
            + " --cmd ${lib.escapeShellArg hyprlandSession}";
        };
      };
    };
  };

  security.rtkit.enable = true;

  fonts = {
    packages = [
      pkgs.iosevka
      pkgs.nerd-fonts.caskaydia-cove
      pkgs.nerd-fonts.symbols-only
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans CJK JP" ];
      serif = [ "Noto Serif CJK JP" ];
      monospace = [ "Noto Sans Mono CJK JP" ];
    };
  };

  environment = {
    systemPackages = [ pkgs.gws ];

    sessionVariables = {
      AQ_DRM_DEVICES = "/dev/dri/nvidia";
      LIBVA_DRIVER_NAME = "nvidia";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NIXOS_OZONE_WL = "1";
    };
  };

  system.stateVersion = "26.05";
}
