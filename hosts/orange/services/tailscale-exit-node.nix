{ pkgs, ... }:
let
  inherit (import ../settings.nix) lanInterface;
in
{
  networking = {
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
}
