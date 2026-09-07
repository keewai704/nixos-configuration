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

  # Pure black with cool gray surfaces and softened Tokyo Night accents.
  base16Scheme = {
    scheme = "Tokyo Night Black";
    slug = "tokyo-night-black";
    author = "folke, keewai";
    base00 = "000000";
    base01 = "141518";
    base02 = "2a2c33";
    base03 = "7c8192";
    base04 = "a4a9b8";
    base05 = "c0c5d4";
    base06 = "d7dbe5";
    base07 = "eceef4";
    base08 = "d98294";
    base09 = "d99a73";
    base0A = "ccb078";
    base0B = "a3bc82";
    base0C = "86bebc";
    base0D = "829fd9";
    base0E = "b19bd9";
    base0F = "c77e86";
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
