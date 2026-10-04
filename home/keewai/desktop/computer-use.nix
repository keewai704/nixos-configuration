{ pkgs, ... }:
{
  home.packages = [ (pkgs.callPackage ../../../pkgs/cua-driver { }) ];
}
