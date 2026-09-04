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
  chatgptDesktop = pkgs.callPackage ../../pkgs/chatgpt-desktop { };
  dotfiles43pr = pkgs.fetchFromGitHub {
    owner = "43PR";
    repo = "dotfiles";
    rev = "5354e7d42cc3d76e63ba749cbc878f3f989939d5";
    hash = "sha256-k087ANymgeVmwoA6eilSIx4xzs4KfhSSZE4go27w6AU=";
  };
  wlogoutConfig = pkgs.runCommandLocal "43pr-wlogout-config" { } ''
    cp -R ${dotfiles43pr}/.config/wlogout "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/layout" \
      --replace-fail "hyprctl dispatch 'hl.dsp.exit()'" "${lib.getExe pkgs.uwsm} stop"
    substituteInPlace "$out/style.css" \
      --replace-fail "/home/rp34/.config/wlogout/icons" "$out/icons"
    grep -Fq "${lib.getExe pkgs.uwsm} stop" "$out/layout"
    grep -Fq "$out/icons/shutdown.png" "$out/style.css"
  '';
in
{
  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "chatgpt-desktop";

  environment.systemPackages = [
    chatgptDesktop
    pkgs.ddcutil
    pkgs.xarchiver
  ];

  home-manager.users.keewai = {
    imports = [ inputs.nixcord.homeModules.nixcord ];

    home = {
      file."Pictures/Wallpapers/tokyo-night.png".source = theme.wallpaper;
      packages = [
        pkgs.imagemagick
        pkgs.jq
        pkgs.playerctl
        pkgs.pavucontrol
        pkgs.quickshell
        pkgs.rofi
        pkgs.wl-clipboard
        pkgs.wlogout
      ];
    };

    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      configFile = {
        "hypr/hyprlock.conf".source = "${dotfiles43pr}/.config/hypr/hyprlock.conf";
        "hypr/scripts/now-playing.sh".source = "${dotfiles43pr}/.config/hypr/scripts/now-playing.sh";
        "hypr/scripts/password-cursor.sh".source =
          "${dotfiles43pr}/.config/hypr/scripts/password-cursor.sh";
        "quickshell".source = "${dotfiles43pr}/.config/quickshell";
        "rofi".source = "${dotfiles43pr}/.config/rofi";
        "user-dirs.dirs".force = true;
        "wlogout".source = wlogoutConfig;
      };
    };

    programs.kitty.enable = true;

    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings.mainBar = {
        layer = "top";
        position = "top";
        exclusive = true;
        spacing = 0;
        modules-left = [
          "cpu"
          "memory"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "custom/mpris-marquee"
          "pulseaudio"
          "custom/power"
        ];
        cpu = {
          interval = 1;
          format = "CPU {usage}%";
        };
        memory = {
          interval = 1;
          format = "RAM {percentage}%";
          tooltip-format = "{used} / {total}GiB";
        };
        clock = {
          format = "{:%H:%M}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "month";
            format.today = "<b><u>{}</u></b>";
          };
        };
        "custom/mpris-marquee" = {
          exec = "${dotfiles43pr}/.config/waybar/scripts/mpris-marquee.sh";
          return-type = "json";
          format = "{}";
          on-click = "${lib.getExe pkgs.playerctl} play-pause";
          on-scroll-up = "${lib.getExe pkgs.playerctl} next";
          on-scroll-down = "${lib.getExe pkgs.playerctl} previous";
        };
        pulseaudio = {
          format = "{icon}  {volume}%";
          format-muted = "Muted";
          format-icons.default = [
            ""
            ""
            ""
          ];
          tooltip = false;
          on-click = lib.getExe pkgs.pavucontrol;
          on-click-right = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };
        "custom/power" = {
          format = "⏻";
          tooltip = false;
          on-click =
            "${pkgs.procps}/bin/pgrep -x wlogout >/dev/null"
            + " || ${lib.getExe pkgs.wlogout} -b 1 -c 20 -r 20 -L 1700 -R 1700 -T 325 -B 325";
        };
      };
      style = builtins.readFile "${dotfiles43pr}/.config/waybar/style.css";
    };

    programs.nixcord = {
      enable = true;
      discord.enable = false;
      legcord = {
        enable = true;
        equicord.enable = true;
      };
    };

    services = {
      awww.enable = true;
      cliphist.enable = true;
      dunst.enable = true;
      hyprpolkitagent.enable = true;
    };

    systemd.user.services = {
      dunst.Install.WantedBy = [ "graphical-session.target" ];

      quickshell-volume-osd = {
        Unit = {
          Description = "43PR Quickshell volume OSD";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
          X-Restart-Triggers = [ "${dotfiles43pr}/.config/quickshell/volume-osd" ];
        };
        Service = {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.quickshell)
            "--config"
            "volume-osd"
          ];
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };

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

    steam = {
      enable = true;
      package = inputs.millennium.packages.${pkgs.stdenv.hostPlatform.system}.millennium-steam;
      extraCompatPackages = [ inputs.proton-cachyos.packages.${pkgs.stdenv.hostPlatform.system}.default ];
    };

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
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };

  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";
}
