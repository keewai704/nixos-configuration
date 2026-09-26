{ lib, pkgs, ... }:
let
  cuaDriver = pkgs.callPackage ../../../pkgs/cua-driver { };
in
{
  home.packages = [ cuaDriver ];

  programs.mcp.servers.cua-driver = {
    command = lib.getExe cuaDriver;
    args = [ "mcp" ];
  };
}
