{ pkgs, ... }:
let
  browser-harness = pkgs.callPackage ../../../pkgs/browser-harness { };
  jev-ultrafast = pkgs.callPackage ../../../pkgs/jev-ultrafast { inherit browser-harness; };
in
{
  home.packages = [
    browser-harness
    jev-ultrafast
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.networkmanagerapplet
    pkgs.pavucontrol
  ];
}
