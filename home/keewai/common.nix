{ pkgs, ... }:
{
  imports = [ ./shared ];

  programs.gh.enable = true;

  home.packages = [
    pkgs.git
    pkgs.gws
    pkgs.ripgrep
    pkgs.yt-dlp
  ];
}
