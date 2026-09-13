{ pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ../../../pkgs/chatgpt-desktop { })
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.networkmanagerapplet
    pkgs.pavucontrol
  ];
}
