{ config, lib, ... }:
let
  tailnetHostname = "${config.networking.hostName}.tail1e65cd.ts.net";
  tailscale = lib.getExe config.services.tailscale.package;
in
{
  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    proxyTimeout = "600s";
    clientMaxBodySize = "0";
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
          port = 8000;
        }
      ];
      locations = {
        "= /".return = "302 https://${tailnetHostname}/pi/$is_args$args";
        "= /pi".return = "308 https://${tailnetHostname}/pi/$is_args$args";
        "= /pi/pi".return = "302 https://${tailnetHostname}/pi/$is_args$args";
        "= /pi/pi/".return = "302 https://${tailnetHostname}/pi/$is_args$args";
        "^~ /pi/" = {
          proxyPass = "http://127.0.0.1:30141";
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $tailscale_client_ip;
            proxy_set_header X-Forwarded-For $tailscale_client_ip;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host $host;
          '';
        };
        "/".return = "404";
      };
    };
  };

  systemd.services.tailscale-serve-nginx = {
    description = "Publish Pi Web through loopback nginx";
    requires = [
      "nginx.service"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled-set.service"
      "home-manager-keewai.service"
    ];
    after = [
      "network-online.target"
      "nginx.service"
      "tailscaled.service"
      "tailscaled-set.service"
      "home-manager-keewai.service"
    ];
    partOf = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "30s";
      ExecStart = "${tailscale} serve --bg --yes --https=443 http://127.0.0.1:8000";
      ExecStop = "${tailscale} serve --https=443 off";
    };
  };
}
