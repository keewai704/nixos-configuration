{ colors, pkgs }:

{
  palette = {
    background = colors.base00;
    comment = colors.base03;
    foreground = colors.base05;
    red = colors.base08;
    yellow = colors.base0A;
    green = colors.base0B;
    cyan = colors.base0C;
    blue = colors.base0D;
    magenta = colors.base0E;
  };

  cursor = {
    package = pkgs.colloid-cursors;
    name = "Colloid-dark-cursors";
    size = 24;
  };
  wallpaper = ./assets/videoframe_150744_10240x4320_clean-faithful.png;

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
