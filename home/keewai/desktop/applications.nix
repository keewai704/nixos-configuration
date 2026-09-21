{ pkgs, ... }:
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.moonlight-qt
    pkgs.networkmanagerapplet
    pkgs.pavucontrol
  ];
}
