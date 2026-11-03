{ pkgs, ... }:
{
  home.packages = [
    pkgs.file
    pkgs.gws
    pkgs.nixfmt
    pkgs.openssl
    pkgs.pi-coding-agent
    pkgs.python3
    pkgs.ripgrep
    pkgs.yt-dlp
  ];
}
