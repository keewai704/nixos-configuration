{ pkgs }:

let
  flavour = "mocha";
  accent = "blue";

  palette = {
    rosewater = "f5e0dc";
    flamingo = "f2cdcd";
    pink = "f5c2e7";
    mauve = "cba6f7";
    red = "f38ba8";
    maroon = "eba0ac";
    peach = "fab387";
    yellow = "f9e2af";
    green = "a6e3a1";
    teal = "94e2d5";
    sky = "89dceb";
    sapphire = "74c7ec";
    blue = "89b4fa";
    lavender = "b4befe";
    text = "cdd6f4";
    subtext1 = "bac2de";
    subtext0 = "a6adc8";
    overlay2 = "9399b2";
    overlay1 = "7f849c";
    overlay0 = "6c7086";
    surface2 = "585b70";
    surface1 = "45475a";
    surface0 = "313244";
    base = "1e1e2e";
    mantle = "181825";
    crust = "11111b";
    black = "000000";
  };

  hex = color: "#${color}";
  rgb = color: "rgb(${color})";
  rgba = color: alpha: "rgba(${color}${alpha})";

  semantic = {
    accent = palette.${accent};
    accentAlt = palette.mauve;
    desktopBackground = palette.crust;
    windowBackground = palette.base;
    surface = palette.surface0;
    surfaceHigh = palette.surface1;
    track = palette.surface2;
    border = palette.surface1;
    text = palette.text;
    muted = palette.subtext0;
    dim = palette.overlay0;
    shadow = palette.black;
  };

  cursor = {
    package = pkgs.colloid-cursors;
    name = "Colloid-dark-cursors";
    size = 24;
  };
in
{
  inherit
    accent
    cursor
    flavour
    palette
    semantic
    ;

  scheme = "dark";

  gtk = {
    package = pkgs.catppuccin-gtk.override {
      accents = [ accent ];
      size = "standard";
      tweaks = [ "rimless" ];
      variant = flavour;
    };
    name = "catppuccin-${flavour}-${accent}-standard+rimless";
  };

  icon = {
    package = pkgs.colloid-icon-theme.override {
      schemeVariants = [ "catppuccin" ];
    };
    name = "Colloid-Catppuccin-Dark";
  };

  fcitx5 = {
    addon = pkgs.catppuccin-fcitx5.override {
      withRoundedCorners = true;
    };
    themeName = "catppuccin-${flavour}-${accent}";
    font = "Noto Sans CJK JP 10";
    menuFont = "Noto Sans CJK JP 11";
    trayFont = "Noto Sans CJK JP Bold 10";
  };

  qt = {
    package = pkgs.catppuccin-kvantum.override {
      inherit accent;
      variant = flavour;
    };
    themeName = "catppuccin-${flavour}-${accent}";
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
    foreground = hex palette.text;
    background = hex palette.base;
    selection_foreground = hex palette.base;
    selection_background = hex palette.rosewater;
    cursor = hex palette.rosewater;
    cursor_text_color = hex palette.base;
    url_color = hex palette.rosewater;
    active_border_color = hex palette.lavender;
    inactive_border_color = hex palette.overlay0;
    bell_border_color = hex palette.yellow;
    wayland_titlebar_color = "system";
    active_tab_foreground = hex palette.crust;
    active_tab_background = hex palette.mauve;
    inactive_tab_foreground = hex palette.text;
    inactive_tab_background = hex palette.mantle;
    tab_bar_background = hex palette.crust;
    mark1_foreground = hex palette.base;
    mark1_background = hex palette.lavender;
    mark2_foreground = hex palette.base;
    mark2_background = hex palette.mauve;
    mark3_foreground = hex palette.base;
    mark3_background = hex palette.sapphire;
    color0 = hex palette.surface1;
    color8 = hex palette.surface2;
    color1 = hex palette.red;
    color9 = hex palette.red;
    color2 = hex palette.green;
    color10 = hex palette.green;
    color3 = hex palette.yellow;
    color11 = hex palette.yellow;
    color4 = hex palette.blue;
    color12 = hex palette.blue;
    color5 = hex palette.pink;
    color13 = hex palette.pink;
    color6 = hex palette.teal;
    color14 = hex palette.teal;
    color7 = hex palette.subtext1;
    color15 = hex palette.subtext0;
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
    palette.surface1
    palette.red
    palette.green
    palette.yellow
    palette.blue
    palette.pink
    palette.teal
    palette.subtext1
    palette.surface2
    palette.red
    palette.green
    palette.yellow
    palette.blue
    palette.pink
    palette.teal
    palette.subtext0
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
