{ pkgs, ... }:

let
  inherit (import ./settings.nix) hostName lanInterface;
in
{
  imports = [
    ./hardware-configuration.nix
    ./health-monitor.nix
    ./maintenance.nix
    ./services/camofox.nix
    ./services/immich.nix
    ./services/minecraft.nix
    ./services/storage.nix
    ./services/vaultwarden.nix
    ./services/web.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking = {
    inherit hostName;

    networkmanager.dispatcherScripts = [
      {
        source = pkgs.writeShellScript "tailscale-udp-gro-forwarding" ''
          if [ "$1" = "${lanInterface}" ] && [ "$2" = "up" ]; then
            ${pkgs.ethtool}/bin/ethtool -K "$1" \
              rx-udp-gro-forwarding on \
              rx-gro-list off
          fi
        '';
      }
    ];
  };

  services = {
    tailscale = {
      useRoutingFeatures = "server";
      extraSetFlags = [ "--advertise-exit-node" ];
    };
  };

  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 10 * 1024 * 1024 * 1024;
  };

  system.stateVersion = "26.05";
}
