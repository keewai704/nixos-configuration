{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  noctalia = lib.getExe config.programs.noctalia.package;
  shell = command: "spawn:${noctalia} msg ${command}";
  workspaceKeys = lib.listToAttrs (
    lib.concatMap (
      number:
      let
        key = if number == 10 then "0" else toString number;
      in
      [
        (lib.nameValuePair "Mod+${key}" "workspace-switch:${toString number}")
        (lib.nameValuePair "Mod+Shift+${key}" "window-move-to-workspace:${toString number}")
      ]
    ) (lib.range 1 10)
  );
in
{
  imports = [ inputs.umbriel.homeModules.default ];

  programs.umbriel = {
    enable = true;
    settings = {
      environment = {
        XCURSOR_THEME = config.stylix.cursor.name;
        XCURSOR_SIZE = toString config.stylix.cursor.size;
        QT_QPA_PLATFORM = "wayland";
        QT_QPA_PLATFORMTHEME = config.home.sessionVariables.QT_QPA_PLATFORMTHEME;
        QT_STYLE_OVERRIDE = config.qt.style.name;
        MOZ_ENABLE_WAYLAND = "1";
      };
      layout = {
        mode = "master";
        gap = 12;
        master = {
          position = "center";
          default_width_fraction = 0.333;
        };
      };
      appearance = {
        border_width = 2;
        corner_radius = 12;
        opaque_fullscreen = true;
        blur = {
          enabled = true;
          optimized = false;
          passes = 3;
          radius = 8;
          noise = 0.02;
          brightness = 1.0;
          contrast = 1.0;
          saturation = 1.05;
        };
      };
      include.optional.files = [ "noctalia.toml" ];
      input = {
        focus.follows_mouse = true;
        keyboard = {
          layout = "us";
          repeat_rate = 35;
          repeat_delay = 300;
          numlock_toggle = true;
        };
        touchpad.natural_scroll = true;
      };
      keybinds = workspaceKeys // {
        "Mod+Return" = "spawn:${lib.getExe pkgs.kitty}";
        "Mod+E" = "spawn:${lib.getExe pkgs.thunar}";
        "Mod+Q" = "window-close";
        "Mod+F" = "window-toggle-fullscreen";
        "Mod+Shift+F" = "window-toggle-floating";
        "Mod+Space" = shell "panel-toggle launcher";
        "Mod+Comma" = shell "settings-toggle";
        "Mod+V" = shell "panel-toggle clipboard";
        "Mod+Tab" = "overview-toggle";
        "Mod+Escape" = "session-quit";
        "Mod+Left" = "window-focus-left";
        "Mod+Down" = "window-focus-down";
        "Mod+Up" = "window-focus-up";
        "Mod+Right" = "window-focus-right";
        "Mod+Shift+Left" = "column-move-left";
        "Mod+Shift+Down" = "window-move-down";
        "Mod+Shift+Up" = "window-move-up";
        "Mod+Shift+Right" = "column-move-right";
        "Mod+WheelUp" = "workspace-previous";
        "Mod+WheelDown" = "workspace-next";
        "XF86AudioRaiseVolume" = shell "volume-up";
        "XF86AudioLowerVolume" = shell "volume-down";
        "XF86AudioMute" = shell "volume-mute";
        "XF86AudioMicMute" = shell "mic-mute";
        "XF86AudioPlay" = shell "media toggle";
        "XF86AudioNext" = shell "media next";
        "XF86AudioPrev" = shell "media previous";
        "XF86MonBrightnessUp" = shell "brightness-up";
        "XF86MonBrightnessDown" = shell "brightness-down";
        "Print" = shell "screenshot-region";
        "Shift+Print" = shell "screenshot-fullscreen";
        "Ctrl+Print" = shell "screenshot-window";
      };
      window_rule = [
        {
          opacity = 0.9;
          blur = true;
        }
        {
          match.app_id = "^kitty$";
          opacity = 1.0;
        }
        {
          match.content_type = "video";
          opacity = 1.0;
          blur = false;
        }
        {
          match.content_type = "game";
          opacity = 1.0;
          blur = false;
        }
        {
          match = {
            app_id = "^steam$";
            title = "[Bb]ig [Pp]icture";
          };
          default_output = "SUNSHINE";
          default_fullscreen = true;
        }
        {
          match.app_id = "^steam_app_";
          default_output = "SUNSHINE";
          opacity = 1.0;
          blur = false;
        }
      ];
    };
  };

  xdg.configFile."umbriel/config.toml".source = lib.mkForce (
    pkgs.runCommand "umbriel-config.toml"
      {
        source = (pkgs.formats.toml { }).generate "umbriel-config.toml" config.programs.umbriel.settings;
      }
      ''
        ${lib.getExe config.programs.umbriel.package} config validate -c "$source"
        cp "$source" "$out"
      ''
  );
}
