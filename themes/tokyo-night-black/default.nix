{ pkgs }:

let
  cursor = {
    package = pkgs.colloid-cursors;
    name = "Colloid-dark-cursors";
    size = 24;
  };
  wallpaper = ./surface-laptop-ultra-dark.png;
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
  terminalColors = with base16Scheme; {
    black = base01;
    red = base08;
    green = base0B;
    yellow = base0A;
    blue = base0D;
    magenta = base0E;
    cyan = base0C;
    white = base05;
  };
in
{
  inherit
    base16Scheme
    icon
    cursor
    wallpaper
    ;

  noctaliaPalette.dark = with base16Scheme; {
    mPrimary = "#${base0D}";
    mOnPrimary = "#${base00}";
    mSecondary = "#${base0C}";
    mOnSecondary = "#${base00}";
    mTertiary = "#${base0E}";
    mOnTertiary = "#${base00}";
    mError = "#${base08}";
    mOnError = "#${base00}";
    mSurface = "#${base00}";
    mOnSurface = "#${base05}";
    mSurfaceVariant = "#${base01}";
    mOnSurfaceVariant = "#${base04}";
    mOutline = "#${base02}";
    mShadow = "#${base00}";
    mHover = "#${base02}";
    mOnHover = "#${base05}";
    terminal = {
      background = "#${base00}";
      foreground = "#${base05}";
      cursor = "#${base05}";
      cursorText = "#${base00}";
      selectionBg = "#${base02}";
      selectionFg = "#${base05}";
      normal = builtins.mapAttrs (_: color: "#${color}") terminalColors;
      bright = builtins.mapAttrs (_: color: "#${color}") (
        terminalColors
        // {
          black = base03;
          white = base07;
        }
      );
    };
  };

  stylix = {
    enable = true;
    autoEnable = false;
    image = wallpaper;
    inherit base16Scheme;
    polarity = "dark";
    inherit cursor;
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.noto-fonts-cjk-sans;
        name = "Noto Sans CJK JP";
      };
      sizes = {
        applications = 10;
        desktop = 10;
        popups = 10;
        terminal = 11;
      };
    };
    icons = {
      enable = true;
      inherit (icon) package;
      dark = icon.name;
      light = icon.name;
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
