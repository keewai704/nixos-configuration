{ lib, pkgs, ... }:
let
  agentTeams = pkgs.callPackage ../../../../pkgs/pi-agent-teams { };
  piCrew = pkgs.callPackage ../../../../pkgs/pi-crew { };
  coreSubagent = pkgs.callPackage ../../../../pkgs/pi-core-subagent { };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1500 [
    {
      source = "${agentTeams}";
      extensions = [ "extensions/teams/index.ts" ];
    }
    {
      source = "${piCrew}";
      extensions = [ "extension/index.ts" ];
    }
    {
      source = "${coreSubagent}";
      extensions = [ "src/index.ts" ];
    }
  ];
}
