{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  chatgptDesktop = pkgs.callPackage ../../pkgs/chatgpt-desktop { };
  dotfiles43pr = pkgs.fetchFromGitHub {
    owner = "43PR";
    repo = "dotfiles";
    rev = "5354e7d42cc3d76e63ba749cbc878f3f989939d5";
    hash = "sha256-k087ANymgeVmwoA6eilSIx4xzs4KfhSSZE4go27w6AU=";
  };
  desktop43pr = pkgs.runCommandLocal "43pr-desktop-config" { } ''
    mkdir -p "$out"
    for name in btop cava gtk-3.0 gtk-4.0 hypr kitty quickshell rofi waybar wlogout; do
      cp -R "${dotfiles43pr}/.config/$name" "$out/"
    done
    ln -s '${dotfiles43pr}/Wallpapers/$.jpg' "$out/default-wallpaper.jpg"
    chmod -R u+w "$out"

    patchShebangs "$out"
    substituteInPlace "$out/wlogout/layout" \
      --replace-fail "hyprctl dispatch 'hl.dsp.exit()'" "${lib.getExe pkgs.uwsm} stop"
    substituteInPlace "$out/wlogout/style.css" \
      --replace-fail "/home/rp34/.config/wlogout/icons" "$out/wlogout/icons"
    substituteInPlace "$out/quickshell/hyprquickpaper/config.json" \
      --replace-fail '"Pictures/Wallpapers/"' '"Pictures/Wallpapers/43PR/"'
    substituteInPlace "$out/quickshell/hyprquickpaper/cache.sh" \
      --replace-fail 'find "$wallpaper_path" -type f' 'find "$wallpaper_path" -maxdepth 1 -type f'
    substituteInPlace "$out/quickshell/hyprquickpaper/commands.sh" \
      --replace-fail 'awww img "$1"' '${lib.getExe pkgs.awww} img "$1"'
    substituteInPlace "$out/kitty/kitty.conf" \
      --replace-fail 'font_family Consolas' 'font_family JetBrainsMono Nerd Font'
    substituteInPlace "$out/gtk-3.0/settings.ini" \
      --replace-fail 'gtk-icon-theme-name=Papirus-Dark' 'gtk-icon-theme-name=Papirus-43PR'
    substituteInPlace "$out/gtk-4.0/settings.ini" \
      --replace-fail 'gtk-icon-theme-name=Papirus-Dark' 'gtk-icon-theme-name=Papirus-43PR'

    grep -Fq "${lib.getExe pkgs.uwsm} stop" "$out/wlogout/layout"
    grep -Fq 'Pictures/Wallpapers/43PR/' "$out/quickshell/hyprquickpaper/config.json"
    grep -Fq 'JetBrainsMono Nerd Font' "$out/kitty/kitty.conf"
  '';
  papirus43pr = pkgs.runCommandLocal "papirus-43pr" { } ''
    icon_theme="$out/share/icons/Papirus-43PR"
    mkdir -p "$icon_theme"
    cp ${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/index.theme "$icon_theme/index.theme"
    substituteInPlace "$icon_theme/index.theme" \
      --replace-fail 'Name=Papirus-Dark' 'Name=Papirus-43PR' \
      --replace-fail 'Inherits=breeze-dark,hicolor' 'Inherits=Papirus-Dark,breeze-dark,hicolor'

    for size in 22x22 24x24 32x32 48x48 64x64; do
      source_dir=${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/$size/places
      target_dir="$icon_theme/$size/places"
      mkdir -p "$target_dir"
      for source in "$source_dir"/folder-white*.svg "$source_dir"/user-white*.svg; do
        [ -e "$source" ] || continue
        target_name="''${source##*/}"
        target_name="''${target_name/-white/}"
        ln -s "$source" "$target_dir/$target_name"
      done
    done
  '';
  opacityPicker = pkgs.writeShellApplication {
    name = "43pr-opacity";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.rofi
    ];
    text = ''
      choice="$(printf '100%%\n90%%\n80%%\n70%%\n60%%\n50%%\n40%%\n' | rofi -dmenu -p "")"
      case "$choice" in
        100%) opacity=1.0 ;;
        90%) opacity=0.9 ;;
        80%) opacity=0.8 ;;
        70%) opacity=0.7 ;;
        60%) opacity=0.6 ;;
        50%) opacity=0.5 ;;
        40%) opacity=0.4 ;;
        *) exit 0 ;;
      esac

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      install -d -m 700 "$state_dir"
      printf '%s\n' "$opacity" > "$state_dir/43pr-opacity"
      hyprctl reload
    '';
  };
  screenRecorder = pkgs.writeShellApplication {
    name = "43pr-recorder";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.wf-recorder
    ];
    text = ''
      state_file="''${XDG_RUNTIME_DIR:?}/43pr-recorder.pid"
      if [[ -s "$state_file" ]]; then
        recorder_pid="$(<"$state_file")"
        if kill -0 "$recorder_pid" 2>/dev/null; then
          kill -INT "$recorder_pid"
          rm -f "$state_file"
          exit 0
        fi
        rm -f "$state_file"
      fi

      install -d "$HOME/Videos"
      wf-recorder --audio --no-dmabuf --output Virtual-1 \
        --file "$HOME/Videos/$(date +%Y-%m-%d_%H-%M-%S).mp4" &
      printf '%s\n' "$!" > "$state_file"
    '';
  };
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
      file."Pictures/Wallpapers/43PR".source = "${dotfiles43pr}/Wallpapers";
      packages = [
        opacityPicker
        papirus43pr
        screenRecorder
        pkgs.btop
        pkgs.brightnessctl
        pkgs.cava
        pkgs.ffmpegthumbnailer
        pkgs.gammastep
        pkgs.grim
        pkgs.imagemagick
        pkgs.jq
        pkgs.kitty
        pkgs.playerctl
        pkgs.pavucontrol
        pkgs.quickshell
        pkgs.rofi
        pkgs.slurp
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
        "btop/btop.conf".source = "${desktop43pr}/btop/btop.conf";
        "cava".source = "${desktop43pr}/cava";
        "gtk-3.0/gtk.css".source = "${desktop43pr}/gtk-3.0/gtk.css";
        "gtk-3.0/settings.ini".source = "${desktop43pr}/gtk-3.0/settings.ini";
        "gtk-4.0/gtk.css".source = "${desktop43pr}/gtk-4.0/gtk.css";
        "gtk-4.0/settings.ini".source = "${desktop43pr}/gtk-4.0/settings.ini";
        "hypr/hyprlock.conf".source = "${desktop43pr}/hypr/hyprlock.conf";
        "hypr/scripts/now-playing.sh".source = "${desktop43pr}/hypr/scripts/now-playing.sh";
        "hypr/scripts/password-cursor.sh".source = "${desktop43pr}/hypr/scripts/password-cursor.sh";
        "kitty/kitty.conf".source = "${desktop43pr}/kitty/kitty.conf";
        "quickshell".source = "${desktop43pr}/quickshell";
        "rofi".source = "${desktop43pr}/rofi";
        "user-dirs.dirs".force = true;
        "wlogout".source = "${desktop43pr}/wlogout";
      };
    };

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
          "custom/gpu"
          "memory"
          "custom/temperature"
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
        "custom/gpu" = {
          exec = "${pkgs.coreutils}/bin/printf 0";
          format = "GPU {}%";
          interval = 1;
          tooltip = true;
          tooltip-format = "Virtual GPU: unavailable";
        };
        memory = {
          interval = 1;
          format = "RAM {percentage}%";
          tooltip-format = "{used} / {total}GiB";
        };
        "custom/temperature" = {
          exec = "${pkgs.coreutils}/bin/printf -- --";
          format = " {}°C";
          interval = 60;
          tooltip = true;
          tooltip-format = "CPU temperature sensor unavailable";
          on-click = "${desktop43pr}/waybar/scripts/toggle-gammastep";
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
          exec = "${desktop43pr}/waybar/scripts/mpris-marquee.sh";
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
      style = builtins.replaceStrings [ "#temperature" ] [ "#custom-temperature" ] (
        builtins.readFile "${dotfiles43pr}/.config/waybar/style.css"
      );
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

      awww-43pr-wallpaper = {
        Unit = {
          Description = "Set the initial 43PR wallpaper";
          After = [ "awww.service" ];
          Requires = [ "awww.service" ];
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "oneshot";
          ExecCondition = "${pkgs.coreutils}/bin/test ! -e %h/.cache/awww/43pr-initialized-5354e7d";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.cache/awww";
          ExecStart = "${lib.getExe pkgs.awww} img ${desktop43pr}/default-wallpaper.jpg --transition-type none";
          ExecStartPost = "${pkgs.coreutils}/bin/touch %h/.cache/awww/43pr-initialized-5354e7d";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      quickshell-volume-osd = {
        Unit = {
          Description = "43PR Quickshell volume OSD";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
          X-Restart-Triggers = [ "${desktop43pr}/quickshell/volume-osd" ];
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

    stylix.targets = {
      fcitx5.enable = false;
      firefox.enable = false;
      gtk.enable = false;
      hyprland.enable = false;
      kitty.enable = false;
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
