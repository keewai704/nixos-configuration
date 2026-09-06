{
  config,
  osConfig,
  inputs,
  pkgs,
  ...
}:
let
  inherit (osConfig.lib.stylix) colors;
  stylixTheme = import ../../../hosts/citrus/theme.nix {
    inherit pkgs;
    colors = osConfig.lib.stylix.colors;
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

  islandPackage = config.programs.dynamic-island.package;

in
{
  # Preserve the CLI as well as the user service when removing the NixOS module.
  home.packages = [ config.services.hypridle.package ];
  imports = [ inputs.dynamic-island.homeManagerModules.default ];
  programs.dynamic-island = {
    enable = true;
    theme = islandTheme;
    defaultWallpaper = osConfig.stylix.image;
    settings = {
      notch = true;
      hover = true;
      dnd = false;
      reducedMotion = false;
    };
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
          path = osConfig.stylix.image;
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
          font_family = osConfig.stylix.fonts.sansSerif.name;
          font_size = 28;
          position = "0, 190";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] LC_ALL=C date +'%H:%M'";
          color = rgb colors.base05;
          font_family = osConfig.stylix.fonts.sansSerif.name;
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
    hypridle = {
      enable = true;
      settings = {
        general = {
          inhibit_sleep = 3;
          lock_cmd = "${islandPackage}/bin/island-action lock";
          before_sleep_cmd = "${islandPackage}/bin/island-action lock";
          after_sleep_cmd = "hyprctl dispatch dpms on";
          ignore_dbus_inhibit = false;
        };
        listener = [
          {
            timeout = 600;
            on-timeout = "${islandPackage}/bin/island-action lock";
          }
          {
            timeout = 660;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
        ];
      };
    };
  };
}
