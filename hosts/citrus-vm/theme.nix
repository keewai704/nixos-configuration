{ pkgs }:

let
  variant = "night";

  palette = {
    background = "1a1b26";
    backgroundDark = "16161e";
    backgroundDarker = "15161e";
    backgroundHighlight = "292e42";
    backgroundVisual = "283457";
    terminalBlack = "414868";
    foreground = "c0caf5";
    foregroundDark = "a9b1d6";
    foregroundGutter = "3b4261";
    comment = "565f89";
    dark5 = "737aa2";
    blue0 = "3d59a1";
    blue = "7aa2f7";
    cyan = "7dcfff";
    blue1 = "2ac3de";
    blue2 = "0db9d7";
    blue5 = "89ddff";
    blue6 = "b4f9f8";
    blue7 = "394b70";
    magenta = "bb9af7";
    magenta2 = "ff007c";
    purple = "9d7cd8";
    orange = "ff9e64";
    yellow = "e0af68";
    green = "9ece6a";
    green1 = "73daca";
    green2 = "41a6b5";
    teal = "1abc9c";
    red = "f7768e";
    red1 = "db4b4b";
    brightRed = "ff899d";
    brightGreen = "9fe044";
    brightYellow = "faba4a";
    brightBlue = "8db0ff";
    brightMagenta = "c7a9ff";
    brightCyan = "a4daff";
    black = "000000";
  };

  hex = color: "#${color}";
  rgb = color: "rgb(${color})";
  rgba = color: alpha: "rgba(${color}${alpha})";

  semantic = {
    accent = palette.blue;
    accentAlt = palette.magenta;
    desktopBackground = palette.backgroundDarker;
    windowBackground = palette.background;
    surface = palette.backgroundHighlight;
    surfaceHigh = palette.foregroundGutter;
    track = palette.terminalBlack;
    border = palette.foregroundGutter;
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

  qtColor = color: "#ff${color}";
  qtPalette = colors: builtins.concatStringsSep ", " (map qtColor colors);
  qtActiveColors = [
    palette.foreground
    palette.backgroundHighlight
    palette.terminalBlack
    palette.foregroundGutter
    palette.backgroundDark
    palette.backgroundHighlight
    palette.foreground
    palette.foreground
    palette.foreground
    palette.background
    palette.background
    palette.black
    palette.blue
    palette.backgroundDark
    palette.cyan
    palette.magenta
    palette.backgroundHighlight
    palette.foreground
    palette.backgroundHighlight
    palette.foreground
  ];
  qtDisabledColors = [
    palette.comment
    palette.backgroundHighlight
    palette.foregroundGutter
    palette.foregroundGutter
    palette.backgroundDark
    palette.backgroundHighlight
    palette.comment
    palette.foreground
    palette.comment
    palette.background
    palette.background
    palette.black
    palette.foregroundGutter
    palette.comment
    palette.comment
    palette.comment
    palette.backgroundHighlight
    palette.foreground
    palette.backgroundHighlight
    palette.comment
  ];
  qtPlaceholderColor = "#80${palette.comment}";
  qtColorScheme =
    assert builtins.length qtActiveColors == 20;
    assert builtins.length qtDisabledColors == 20;
    ''
      [ColorScheme]
      active_colors=${qtPalette qtActiveColors}, ${qtPlaceholderColor}
      disabled_colors=${qtPalette qtDisabledColors}, ${qtPlaceholderColor}
      inactive_colors=${qtPalette qtActiveColors}, ${qtPlaceholderColor}
    '';

  gtkPackage = pkgs.callPackage ../../pkgs/tokyonight-gtk { };
in
{
  inherit
    cursor
    palette
    semantic
    variant
    ;

  scheme = "dark";

  gtk = {
    package = gtkPackage;
    name = "Tokyonight-Dark";
  };

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

  qt = {
    colorScheme = qtColorScheme;
    colorSchemeName = "tokyonight";
    styleName = "fusion";
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

  kitty.settings = {
    foreground = hex palette.foreground;
    background = hex palette.background;
    selection_foreground = hex palette.foreground;
    selection_background = hex palette.backgroundVisual;
    cursor = hex palette.foreground;
    cursor_text_color = hex palette.background;
    url_color = hex palette.green1;
    active_border_color = hex palette.blue;
    inactive_border_color = hex palette.backgroundHighlight;
    bell_border_color = hex palette.yellow;
    wayland_titlebar_color = "system";
    active_tab_foreground = hex palette.backgroundDark;
    active_tab_background = hex palette.blue;
    inactive_tab_foreground = hex palette.dark5;
    inactive_tab_background = hex palette.backgroundHighlight;
    tab_bar_background = hex palette.backgroundDarker;
    mark1_foreground = hex palette.backgroundDark;
    mark1_background = hex palette.blue;
    mark2_foreground = hex palette.backgroundDark;
    mark2_background = hex palette.magenta;
    mark3_foreground = hex palette.backgroundDark;
    mark3_background = hex palette.cyan;
    color0 = hex palette.backgroundDarker;
    color8 = hex palette.terminalBlack;
    color1 = hex palette.red;
    color9 = hex palette.brightRed;
    color2 = hex palette.green;
    color10 = hex palette.brightGreen;
    color3 = hex palette.yellow;
    color11 = hex palette.brightYellow;
    color4 = hex palette.blue;
    color12 = hex palette.brightBlue;
    color5 = hex palette.magenta;
    color13 = hex palette.brightMagenta;
    color6 = hex palette.cyan;
    color14 = hex palette.brightCyan;
    color7 = hex palette.foregroundDark;
    color15 = hex palette.foreground;
    color16 = hex palette.orange;
    color17 = hex palette.red1;
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

  console.colors = [
    palette.backgroundDarker
    palette.red
    palette.green
    palette.yellow
    palette.blue
    palette.magenta
    palette.cyan
    palette.foregroundDark
    palette.terminalBlack
    palette.brightRed
    palette.brightGreen
    palette.brightYellow
    palette.brightBlue
    palette.brightMagenta
    palette.brightCyan
    palette.foreground
  ];

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
