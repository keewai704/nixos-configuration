{ pkgs, ... }:
{
  home.packages = [ (pkgs.callPackage ../../../pkgs/hypruse { }) ];
}
