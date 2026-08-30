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

  hex = color: "#${color}";
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
in
{
  inherit cursor palette semantic;

  icon = {
    package = pkgs.colloid-icon-theme;
    name = "Colloid-Dark";
  };

  fcitx5 = {
    addon = pkgs.fcitx5-tokyonight;
    themeName = "Tokyonight-Storm";
    font = "Noto Sans CJK JP 10";
    menuFont = "Noto Sans CJK JP 11";
    trayFont = "Noto Sans CJK JP Bold 10";
  };

  quickShell = {
    schemaVersion = 1;
    islandBg = hex semantic.desktopBackground;
    ink = hex semantic.text;
    muted = hex semantic.muted;
    dim = hex semantic.dim;
    surface = hex semantic.surface;
    surfaceHigh = hex semantic.surfaceHigh;
    track = hex semantic.track;
    green = hex palette.green;
    red = hex palette.red;
    blue = hex palette.blue;
    yellow = hex palette.yellow;
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
