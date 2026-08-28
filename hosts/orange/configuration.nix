{
  orangeSettings,
  pkgs,
  ...
}:

{
  imports = [
    ../../profiles/networkmanager.nix
    ../../profiles/tailnet-admin.nix
    ../../profiles/uefi-systemd-boot.nix
    ./hardware-configuration.nix
    ./camofox.nix
    ./camofox-mcp.nix
    ./maintenance.nix
    ./media-services.nix
    ./minecraft-server.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking = {
    inherit (orangeSettings) hostName;

    networkmanager.dispatcherScripts = [
      {
        source = pkgs.writeShellScript "tailscale-udp-gro-forwarding" ''
          if [ "$1" = "enp2s0" ] && [ "$2" = "up" ]; then
            ${pkgs.ethtool}/bin/ethtool -K "$1" \
              rx-udp-gro-forwarding on \
              rx-gro-list off
          fi
        '';
      }
    ];
  };

  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 10 * 1024 * 1024 * 1024;
  };

  home-manager.users.keewai.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
