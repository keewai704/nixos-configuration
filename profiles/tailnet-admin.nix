{
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  services = {
    openssh = {
      enable = true;
      openFirewall = false;
    };

    tailscale = {
      enable = true;
      extraSetFlags = [ "--ssh" ];
    };
  };
}
