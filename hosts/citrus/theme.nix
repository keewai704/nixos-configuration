{ colors, pkgs }:

let
  palette = {
    background = colors.base00;
    backgroundHighlight = colors.base01;
    terminalBlack = colors.base02;
    comment = colors.base03;
    foreground = colors.base05;
    foregroundDark = colors.base04;
    red = colors.base08;
    yellow = colors.base0A;
    green = colors.base0B;
    cyan = colors.base0C;
    blue = colors.base0D;
    magenta = colors.base0E;
    black = "000000";
  };

  rgb = color: "rgb(${color})";
  rgba = color: alpha: "rgba(${color}${alpha})";

  semantic = {
    accent = palette.blue;
    accentAlt = palette.magenta;
    desktopBackground = palette.background;
    windowBackground = palette.background;
    surface = palette.backgroundHighlight;
    surfaceHigh = palette.terminalBlack;
    track = palette.terminalBlack;
    border = palette.terminalBlack;
    text = palette.foreground;
    muted = palette.foregroundDark;
    dim = palette.comment;
    shadow = palette.black;
  };

  cursor = {
    package = pkgs.colloid-cursors;
    name = "Colloid-dark-cursors";
    size = 24;
  };
  wallpaper = ./assets/videoframe_150744_10240x4320_clean-faithful.png;
in
{
  inherit
    cursor
    palette
    semantic
    wallpaper
    ;

  # A dimmer Tokyo Night palette shared by Stylix and desktop consumers.
  base16Scheme = {
    scheme = "Tokyo Night Dim";
    slug = "tokyo-night-dim";
    author = "folke, keewai";
    base00 = "14151e";
    base01 = "202435";
    base02 = "303650";
    base03 = "565f89";
    base04 = "99a1c2";
    base05 = "adb6dd";
    base06 = "7bc7e6";
    base07 = "a2e0df";
    base08 = "de6a80";
    base09 = "e68e5a";
    base0A = "ca9e5e";
    base0B = "8eba5f";
    base0C = "71bae6";
    base0D = "6e92de";
    base0E = "a88bde";
    base0F = "c54444";
  };

  icon = {
    package = pkgs.colloid-icon-theme;
    name = "Colloid-Dark";
  };

  hyprland = {
    cursor = {
      inherit (cursor) name size;
    };
    colors = {
      activeBorder = [
        (rgb semantic.accent)
        (rgb semantic.accentAlt)
      ];
      inactiveBorder = rgba semantic.border "aa";
      background = rgb semantic.desktopBackground;
      shadow = rgba semantic.shadow "66";
      shadowInactive = rgba semantic.shadow "44";
      notification = rgb semantic.accent;
    };
  };

  tuigreetTheme = builtins.concatStringsSep ";" [
    "border=blue"
    "title=magenta"
    "text=white"
    "time=cyan"
    "container=black"
    "greet=white"
    "prompt=blue"
    "input=white"
    "action=blue"
    "button=magenta"
  ];
}
