{ lib, pkgs, ... }:
let
  hypruse = pkgs.callPackage ../../../pkgs/hypruse { };
in
{
  home.packages = [ hypruse ];

  codingAgents.mcpServers.hypruse.command = lib.getExe hypruse;
}
