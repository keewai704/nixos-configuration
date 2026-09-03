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

  terminalColors = {
    red = hex palette.red;
    green = hex palette.green;
    yellow = hex palette.yellow;
    blue = hex palette.blue;
    magenta = hex palette.magenta;
    cyan = hex palette.cyan;
  };

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

  noctaliaPalette.dark = {
    mPrimary = hex semantic.accent;
    mOnPrimary = hex semantic.desktopBackground;
    mSecondary = hex semantic.accentAlt;
    mOnSecondary = hex semantic.desktopBackground;
    mTertiary = hex palette.cyan;
    mOnTertiary = hex semantic.desktopBackground;
    mError = hex palette.red;
    mOnError = hex semantic.desktopBackground;
    mSurface = hex semantic.desktopBackground;
    mOnSurface = hex semantic.text;
    mSurfaceVariant = hex semantic.surface;
    mOnSurfaceVariant = hex semantic.muted;
    mOutline = hex semantic.dim;
    mShadow = hex semantic.shadow;
    mHover = hex semantic.surfaceHigh;
    mOnHover = hex semantic.text;
    terminal = {
      background = hex semantic.desktopBackground;
      foreground = hex semantic.text;
      cursor = hex semantic.text;
      cursorText = hex semantic.desktopBackground;
      selectionBg = hex semantic.surfaceHigh;
      selectionFg = hex semantic.text;
      normal = terminalColors // {
        black = hex palette.background;
        white = hex palette.foreground;
      };
      bright = terminalColors // {
        black = hex palette.comment;
        white = hex colors.base07;
      };
    };
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
