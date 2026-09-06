{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.stylix) colors;
  stylixTheme = import ./theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  islandTheme = {
    surface = "#${stylixTheme.semantic.surface}";
    hover = "#${stylixTheme.semantic.surfaceHigh}";
    border = "#${stylixTheme.semantic.border}";
    text = "#${stylixTheme.semantic.text}";
    muted = "#${stylixTheme.semantic.muted}";
    accent = "#${stylixTheme.semantic.accent}";
    onAccent = "#${stylixTheme.semantic.desktopBackground}";
    fontFamily = config.stylix.fonts.sansSerif.name;
    fontSize = config.stylix.fonts.sizes.desktop * 96.0 / 72.0;
  };
  rgb = color: "rgb(${color})";
  rgba = color: alpha: "rgba(${color}${alpha})";

  islandAction = pkgs.writeShellApplication {
    name = "island-action";
    runtimeInputs = with pkgs; [
      brightnessctl
      blueman
      cliphist
      ddcutil
      grimblast
      hyprland
      hyprlock
      hyprpaper
      hyprsunset
      networkmanagerapplet
      pavucontrol
      power-profiles-daemon
      python3
      wl-clipboard
    ];
    text = ''
      export ISLAND_DEFAULT_WALLPAPER=${lib.escapeShellArg (toString config.stylix.image)}
      exec python3 ${./dynamic-island/actions.py} "$@"
    '';
  };
in
{
  home-manager.users.keewai = {
    programs.quickshell = {
      enable = true;
      activeConfig = "dynamic-island";
      configs.dynamic-island = ./dynamic-island;
      systemd.enable = true;
    };

    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          hide_cursor = true;
          ignore_empty_input = true;
        };
        background = [
          {
            monitor = "";
            path = config.stylix.image;
            blur_passes = 3;
            blur_size = 8;
            noise = 0.0117;
            contrast = 0.8916;
            brightness = 0.8172;
            vibrancy = 0.1696;
            vibrancy_darkness = 0.0;
          }
        ];
        label = [
          {
            monitor = "";
            text = "cmd[update:1000] LC_ALL=C date +'%A, %B %d'";
            color = rgb colors.base05;
            font_family = config.stylix.fonts.sansSerif.name;
            font_size = 28;
            position = "0, 190";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "cmd[update:1000] LC_ALL=C date +'%H:%M'";
            color = rgb colors.base05;
            font_family = config.stylix.fonts.sansSerif.name;
            font_size = 96;
            position = "0, 55";
            halign = "center";
            valign = "center";
          }
        ];
        input-field = [
          {
            monitor = "";
            size = "320, 64";
            outline_thickness = 3;
            dots_size = 0.25;
            dots_spacing = 0.2;
            dots_center = true;
            outer_color = rgb colors.base0D;
            inner_color = rgba colors.base01 "cc";
            font_color = rgb colors.base05;
            fade_on_empty = false;
            placeholder_text = "<i>Enter password</i>";
            hide_input = false;
            position = "0, -80";
            halign = "center";
            valign = "center";
            shadow_passes = 2;
            shadow_size = 4;
          }
        ];
      };
    };

    services = {
      cliphist = {
        enable = true;
        allowImages = true;
      };
      hypridle = {
        enable = true;
        settings = {
          general = {
            inhibit_sleep = 3;
            lock_cmd = "${lib.getExe islandAction} lock";
            before_sleep_cmd = "${lib.getExe islandAction} lock";
            after_sleep_cmd = "hyprctl dispatch dpms on";
            ignore_dbus_inhibit = false;
          };
          listener = [
            {
              timeout = 600;
              on-timeout = "${lib.getExe islandAction} lock";
            }
            {
              timeout = 660;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ];
        };
      };
      hyprpaper = {
        enable = true;
        settings = {
          ipc = true;
          splash = false;
          wallpaper = [
            {
              monitor = "";
              path = config.stylix.image;
            }
          ];
        };
      };
      hyprpolkitagent.enable = true;
      network-manager-applet.enable = true;
      hyprsunset = {
        enable = true;
        extraArgs = [ "--identity" ];
      };
    };

    systemd.user.services.quickshell = {
      Unit = {
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Environment = [
          "ISLAND_ACTION=${lib.getExe islandAction}"
          "ISLAND_DEFAULT_WALLPAPER=${toString config.stylix.image}"
          (builtins.toJSON "ISLAND_THEME=${builtins.toJSON islandTheme}")
        ];
        RestartSec = 2;
      };
    };

    systemd.user.services.island-wallpaper-restore = {
      Unit = {
        Description = "Restore the selected Dynamic Island wallpaper";
        After = [ "hyprpaper.service" ];
        Wants = [ "hyprpaper.service" ];
        PartOf = [
          "graphical-session.target"
          "hyprpaper.service"
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe islandAction} wallpaper-restore";
        RemainAfterExit = true;
        # Hyprpaper's simple service starts before its IPC socket is ready.
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    home.packages = [
      islandAction
      (pkgs.writeShellApplication {
        name = "islandctl";
        runtimeInputs = [ pkgs.quickshell ];
        text = ''
          exec qs -c dynamic-island ipc call island "''${@:-toggle}"
        '';
      })
    ];
  };
}
