{
  config,
  inputs,
  lib,
  pkgs,
  theme,
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
      };
      colors = with theme.base16Scheme; {
        background = "#${base00}FF";
        accent_primary = "#${base0D}FF";
        accent_secondary = "#${base0E}FF";
        text_primary = "#${base05}FF";
      };
      input = {
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
