{ lib, pkgs, ... }:
let
  agentTeams = pkgs.callPackage ../../../../pkgs/pi-agent-teams { };
  coreSubagent = pkgs.callPackage ../../../../pkgs/pi-core-subagent { };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1500 [
    {
      source = "${agentTeams}";
      extensions = [ "extensions/teams/index.ts" ];
    }
    {
      source = "npm:@melihmucuk/pi-crew@1.0.34";
      extensions = [ "extension/index.ts" ];
    }
    {
      source = "${coreSubagent}";
      extensions = [ "src/index.ts" ];
    }
  ];
}
