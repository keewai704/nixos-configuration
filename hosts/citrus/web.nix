{ pkgs, ... }:
{
  services.nginx = {
    enable = true;
    virtualHosts."citrus.tail1e65cd.ts.net" = {
      default = true;
      listen = [
        {
          addr = "127.0.0.1";
          port = 8000;
        }
      ];
    };
  };

  systemd.services.tailscale-serve-nginx = {
    description = "Publish loopback nginx with Tailscale Serve";
    requires = [
      "nginx.service"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled-set.service"
    ];
    after = [
      "network-online.target"
      "nginx.service"
      "tailscaled.service"
      "tailscaled-set.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.tailscale}/bin/tailscale serve reset";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:8000";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
    };
  };
}
