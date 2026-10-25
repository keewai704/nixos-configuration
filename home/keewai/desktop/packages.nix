{ pkgs, ... }:
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grim
    pkgs.slurp
    pkgs.idescriptor
    pkgs.iloader
    pkgs.moonlight-qt
    pkgs.pavucontrol
  ];
}
