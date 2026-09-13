{ pkgs, ... }:
{
  imports = [ ./shared ];

  home.packages = [
    pkgs.git
    pkgs.gws
    pkgs.ripgrep
    pkgs.yt-dlp
  ];
}
