{ pkgs, ... }:
{
  home.packages = [
    pkgs.ffmpeg
    pkgs.file
    pkgs.gws
    pkgs.nixfmt
    pkgs.openssl
    pkgs.python3
    pkgs.ripgrep
    pkgs.yt-dlp
  ];
}
