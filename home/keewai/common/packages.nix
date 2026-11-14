{ pkgs, ... }:
{
  home.packages = [
    pkgs.bc
    pkgs.binutils
    pkgs.dnsutils
    pkgs.ffmpeg
    pkgs.file
    pkgs.gws
    pkgs.lsof
    pkgs.nixfmt
    pkgs.openssl
    pkgs.p7zip
    pkgs.pciutils
    pkgs.python3
    pkgs.ripgrep
    pkgs.sqlite
    pkgs.unzip
    pkgs.usbutils
    pkgs.wget
    pkgs.yt-dlp
    pkgs.zip
  ];
}
