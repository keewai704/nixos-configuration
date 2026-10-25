{ config, ... }:
{
  networking = {
    networkmanager.enable = true;
    firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  };

  services = {
    openssh = {
      enable = true;
      openFirewall = false;
    };

    tailscale = {
      enable = true;
      extraSetFlags = [
        "--hostname=${config.networking.hostName}"
        "--ssh"
      ];
    };
  };

  systemd.services.tailscaled = {
    environment.TS_SSH_DISABLE_FORWARDING = "true";
    serviceConfig = {
      MemoryMax = "1G";
      MemorySwapMax = 0;
    };
  };
}
