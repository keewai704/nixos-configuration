{ pkgs, ... }:
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.pavucontrol
  ];
}
