{ pkgs, ... }:
let
  inherit (import ../../settings.nix) nginxPort tailnetHostname;
in
{
  orange.healthMonitor = {
    units = [
      "nginx.service"
      "tailscale-serve-nginx.service"
    ];
    loopbackPorts = [ nginxPort ];
  };

  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    proxyTimeout = "600s";
    clientMaxBodySize = "50000M";

    appendHttpConfig = ''
      map $http_x_forwarded_for $tailscale_client_ip {
        default $http_x_forwarded_for;
        "" $remote_addr;
      }
    '';

    virtualHosts.${tailnetHostname} = {
      default = true;
      listen = [
        {
          addr = "127.0.0.1";
          port = nginxPort;
        }
      ];

      extraConfig = ''
        client_body_buffer_size 1024k;
        send_timeout 600s;
      '';
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
    wantedBy = [
      "multi-user.target"
      "nginx.service"
      "tailscaled.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.tailscale}/bin/tailscale serve reset";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:${toString nginxPort}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
    };
  };
}
