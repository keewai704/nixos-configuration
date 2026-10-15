{ lib, pkgs, ... }:
let
  hypruse = pkgs.local.hypruse;
in
{
  home.packages = [ hypruse ];

  codingAgents.mcpServers.hypruse.command = lib.getExe hypruse;
}
