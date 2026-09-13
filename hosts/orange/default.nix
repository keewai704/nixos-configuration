{ pkgs, ... }:

let
  inherit (import ./settings.nix) hostName;
in
{
  imports = [
    ./hardware-configuration.nix
    ./services/health-monitor.nix
    ./services/immich.nix
    ./services/local-backup.nix
    ./services/maintenance.nix
    ./services/minecraft.nix
    ./services/samba.nix
    ./services/smart-tests.nix
    ./services/storage.nix
    ./services/tailscale-exit-node.nix
    ./services/vaultwarden.nix
    ./services/web.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = hostName;

  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 10 * 1024 * 1024 * 1024;
  };

  system.stateVersion = "26.05";
}
