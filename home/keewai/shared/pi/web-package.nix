{ config, pkgs }:
pkgs.callPackage ../../../../pkgs/pi-web {
  pi-coding-agent = config.programs.pi-coding-agent.package;
  runtimePackages = config.programs.pi-coding-agent.extraPackages;
}
