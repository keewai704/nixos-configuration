{
  config,
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
    for name in btop cava gtk-3.0 gtk-4.0 hypr kitty neofetch nwg-look quickshell rofi waybar wlogout xed; do
      cp -R "${dotfiles43pr}/.config/$name" "$out/"
    done
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
    ln -s ${pkgs.papirus-icon-theme}/share/icons/* "$out/share/icons/"
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
      choice="$(printf '100%%\n90%%\n80%%\n70%%\n60%%\n50%%\n40%%\n' | rofi -dmenu -p "")" || exit 0
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
      hyprctl eval "apply_43pr_opacity($opacity)"
      install -d -m 700 "$state_dir"
      printf '%s\n' "$opacity" > "$state_dir/43pr-opacity"
    '';
  };
  displayControl = pkgs.writeShellApplication {
    name = "43pr-display";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      case "''${1:-}" in
        night)
          if [[ "$(hyprctl hyprsunset temperature)" == 3000 ]]; then
            # identity does not reset the remembered temperature used by this toggle.
            hyprctl hyprsunset temperature 6500
            hyprctl hyprsunset identity
          else
            hyprctl hyprsunset temperature 3000
          fi
          ;;
        up|down)
          gamma="$(hyprctl hyprsunset gamma)"
          [[ "$gamma" =~ ^[0-9]+([.][0-9]+)?$ ]]
          gamma="''${gamma%.*}"
          if [[ "$1" == up ]]; then gamma=$((gamma + 5)); else gamma=$((gamma - 5)); fi
          if ((gamma < 20)); then gamma=20; fi
          if ((gamma > 100)); then gamma=100; fi
          hyprctl hyprsunset gamma "$gamma"
          ;;
        *) printf 'Usage: 43pr-display night|up|down\n' >&2; exit 2 ;;
      esac
    '';
  };
  screenRecorder = pkgs.writeShellApplication {
    name = "43pr-recorder";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if systemctl --user --quiet is-active 43pr-recorder.service; then
        systemctl --user stop 43pr-recorder.service
      else
        systemctl --user start 43pr-recorder.service
      fi
    '';
  };
  recordScreen = pkgs.writeShellApplication {
    name = "43pr-record-screen";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.jq
      pkgs.libnotify
      pkgs.pulseaudio
      pkgs.wf-recorder
    ];
    text = ''
      output="$(hyprctl -j monitors | jq -er 'first(.[] | select(.focused)).name // .[0].name')"
      audio=()
      sink="$(pactl get-default-sink || true)"
      if pactl --format=json list sources | jq -e --arg source "$sink.monitor" 'any(.[]; .name == $source)' >/dev/null; then
        audio=("--audio=$sink.monitor")
      else
        notify-send 'Screen recording' 'No output monitor found; recording video without audio.'
      fi
      install -d "$HOME/Videos"
      exec wf-recorder "''${audio[@]}" -r 30 --output "$output" \
        --file "$HOME/Videos/$(date +%Y-%m-%d_%H-%M-%S_%N).mp4"
    '';
  };
  spotify43pr = pkgs.spotify.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.spicetify-cli ];
    postInstall = (old.postInstall or "") + ''
      export SPICETIFY_CONFIG="$TMPDIR/spicetify"
      export XDG_STATE_HOME="$TMPDIR/spicetify-state"
      mkdir -p "$SPICETIFY_CONFIG"
      cp -R ${dotfiles43pr}/.config/spicetify/{Themes,CustomApps,config-xpui.ini} "$SPICETIFY_CONFIG/"
      chmod -R u+w "$SPICETIFY_CONFIG" "$out/share/spotify/Apps"
      printf 'app.last-launched-version="%s"\n' '${pkgs.spotify.version}' > "$TMPDIR/spotify-prefs"
      substituteInPlace "$SPICETIFY_CONFIG/config-xpui.ini" \
        --replace-fail '/opt/spotify/' "$out/share/spotify/" \
        --replace-fail '/home/rp34/.config/spotify/prefs' "$TMPDIR/spotify-prefs" \
        --replace-fail 'check_spicetify_update = 1' 'check_spicetify_update = 0'
      spicetify --no-restart backup apply
      test -s "$out/share/spotify/Apps/xpui/user.css"
      test -s "$out/share/spotify/Apps/xpui/spicetify-routes-marketplace.js"
    '';
  });
in
{
  nixpkgs.config.allowUnfreePredicate =
    package:
    builtins.elem (lib.getName package) [
      "chatgpt-desktop"
      "cuda_nvml_dev"
      "nvidia-x11"
      "nvidia-settings"
      "spotify"
    ];

  stylix = {
    image = "${dotfiles43pr}/Wallpapers/$.jpg";
    icons = {
      enable = true;
      package = papirus43pr;
      dark = "Papirus-43PR";
      light = "Papirus-43PR";
    };
  };

  system.build.desktop43prCheck =
    pkgs.runCommandLocal "43pr-desktop-check"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.python3
          pkgs.lua
        ];
      }
      ''
            python3 ${./check-desktop.py} ${./hyprland.lua} \
              ${lib.getExe displayControl} ${lib.getExe opacityPicker} \
              ${lib.getExe screenRecorder} ${lib.getExe recordScreen}
        mkdir -m 700 runtime
        mkdir -p config/hypr
        ln -s ${
          config.home-manager.users.keewai.xdg.configFile."hypr/hyprland.lua".source
        } config/hypr/hyprland.lua
        touch config/hypr/hyprland-gui.lua
        XDG_RUNTIME_DIR="$PWD/runtime" XDG_CONFIG_HOME="$PWD/config" \
          ${pkgs.hyprland}/bin/Hyprland --verify-config
        # Parse the deployed idle config without connecting to or locking a desktop.
        ln -s ${
          config.home-manager.users.keewai.xdg.configFile."hypr/hypridle.conf".source
        } config/hypr/hypridle.conf
        if XDG_RUNTIME_DIR="$PWD/runtime" XDG_CONFIG_HOME="$PWD/config" WAYLAND_DISPLAY=missing \
          ${lib.getExe pkgs.hypridle} >hypridle.log 2>&1; then
          exit 1
        fi
        cat hypridle.log
        if grep -Fq 'Config has errors' hypridle.log; then
          exit 1
        fi
        grep -Fq "Couldn't connect to a wayland compositor" hypridle.log
        # The white-folder overlay must retain the parent theme's application icons.
        test -r ${papirus43pr}/share/icons/Papirus-43PR/32x32/places/folder.svg
        test -r ${papirus43pr}/share/icons/Papirus-Dark/32x32/apps/firefox.svg
            touch "$out"
      '';

  environment.systemPackages = [
    chatgptDesktop
    pkgs.ddcutil
    pkgs.xarchiver
  ];

  home-manager.users.keewai = { lib, ... }: {
    imports = [ inputs.nixcord.homeModules.nixcord ];

    dconf.settings."org/gnome/desktop/interface" = {
      gtk-theme = "Adwaita";
      icon-theme = config.stylix.icons.dark;
      font-name = "${config.stylix.fonts.sansSerif.name} ${toString config.stylix.fonts.sizes.applications}";
      cursor-theme = config.stylix.cursor.name;
      cursor-size = config.stylix.cursor.size;
      color-scheme = "prefer-dark";
    };

    home = {
      file."Pictures/Wallpapers/43PR".source = "${dotfiles43pr}/Wallpapers";
      pointerCursor.x11.enable = true;
      packages = [
        config.stylix.icons.package
        displayControl
        opacityPicker
        screenRecorder
        spotify43pr
        pkgs.btop
        pkgs.cava
        pkgs.ffmpegthumbnailer
        pkgs.grim
        pkgs.hyfetch
        pkgs.hyprmod
        pkgs.imagemagick
        pkgs.jq
        pkgs.kitty
        pkgs.lua
        pkgs.mpv
        pkgs.nvtopPackages.full
        pkgs.nwg-look
        pkgs.playerctl
        pkgs.pavucontrol
        pkgs.quickshell
        pkgs.rofi
        pkgs.slurp
        pkgs.spicetify-cli
        pkgs.wl-clipboard
        pkgs.wlogout
        pkgs.xed-editor
      ];

      activation.initialize43prEditableSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        for name in gtk-3.0/settings.ini gtk-4.0/settings.ini nwg-look/config xed/accels; do
          if [ ! -e "$HOME/.config/$name" ]; then
            run install -Dm644 "${desktop43pr}/$name" "$HOME/.config/$name"
          fi
        done
      '';
    };

    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      configFile = {
        "git/config".text = ''
          [user]
            name = KY
            email = 249657796+keewai704@users.noreply.github.com
        '';
        "btop/btop.conf".source = "${desktop43pr}/btop/btop.conf";
        "cava".source = "${desktop43pr}/cava";
        "gtk-3.0/gtk.css".source = "${desktop43pr}/gtk-3.0/gtk.css";
        "gtk-4.0/gtk.css".source = "${desktop43pr}/gtk-4.0/gtk.css";
        "hypr/hyprlock.conf".source = "${desktop43pr}/hypr/hyprlock.conf";
        "hypr/scripts/now-playing.sh".source = "${desktop43pr}/hypr/scripts/now-playing.sh";
        "hypr/scripts/password-cursor.sh".source = "${desktop43pr}/hypr/scripts/password-cursor.sh";
        "kitty/kitty.conf".source = "${desktop43pr}/kitty/kitty.conf";
        "neofetch".source = "${desktop43pr}/neofetch";
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
          exec = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits";
          format = "GPU {}%";
          interval = 1;
          tooltip = true;
          tooltip-format = "NVIDIA GeForce RTX 5070 Ti utilization";
        };
        memory = {
          interval = 1;
          format = "RAM {percentage}%";
          tooltip-format = "{used} / {total}GiB";
        };
        "custom/temperature" = {
          exec = "${lib.getExe pkgs.lm_sensors} -j | ${lib.getExe pkgs.jq} -r '[to_entries[] | select(.key | startswith(\"k10temp-\")) | .value.Tctl.temp1_input][0] | if . == null then \"--\" else round end'";
          format = " {}°C";
          interval = 5;
          tooltip = true;
          tooltip-format = "AMD Ryzen 7 9800X3D temperature";
          on-click = "${lib.getExe displayControl} night";
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
      dunst = {
        enable = true;
        settings.global = {
          enable_recursive_icon_lookup = true;
          icon_theme = config.stylix.icons.dark;
        };
      };
      hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "${pkgs.procps}/bin/pidof hyprlock || ${lib.getExe config.programs.hyprlock.package}";
            before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
            after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({action = \"on\"})'";
          };
          listener = [
            {
              timeout = 600;
              on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
            }
          ];
        };
      };
      hyprpolkitagent.enable = true;
      hyprsunset = {
        enable = true;
        extraArgs = [ "--identity" ];
      };
      network-manager-applet.enable = true;
    };

    systemd.user.services = {
      dunst.Install.WantedBy = [ "graphical-session.target" ];

      "43pr-recorder" = {
        Unit = {
          Description = "43PR screen and output-audio recorder";
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "exec";
          ExecStart = lib.getExe recordScreen;
          KillSignal = "SIGINT";
          TimeoutStopSec = 10;
        };
      };

      awww-43pr-wallpaper = {
        Unit = {
          Description = "Set the initial 43PR wallpaper";
          After = [
            "graphical-session.target"
            "awww.service"
          ];
          Requires = [ "awww.service" ];
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "oneshot";
          ExecCondition = "${pkgs.coreutils}/bin/test ! -e %h/.cache/awww/43pr-initialized-5354e7d";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.cache/awww";
          ExecStart = "${lib.getExe pkgs.awww} img ${config.stylix.image} --transition-type none";
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
      dunst.enable = true;
      # Keep the explicit Fcitx5 panel and the upstream browser/43PR styling.
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
    # Home Manager owns hypridle's per-user configuration and service.
    hypridle.enable = lib.mkForce false;
    gnome.at-spi2-core.enable = true;
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };

  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";
}
