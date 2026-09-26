{ pkgs, ... }:
{
  home.packages = [
    pkgs.file
    pkgs.gws
    pkgs.nixfmt
    pkgs.openssl
    pkgs.ripgrep
    pkgs.yt-dlp
  ];
}
