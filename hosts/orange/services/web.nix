{ pkgs, ... }:

let
  inherit (import ../settings.nix)
    immichPort
    nginxPort
    tailnetHostname
    tailnetOrigin
    vaultwardenPort
    ;
  nginxProxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $tailscale_client_ip;
    proxy_set_header X-Forwarded-For $tailscale_client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $hostname;

  '';
in
{
  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    proxyTimeout = "600s";
    clientMaxBodySize = "50000M";

    appendHttpConfig = ''
      # Tailscale Serve supplies the original tailnet client in this header.
      # Fall back to the direct peer for loopback health checks.
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
      locations = {
        "= /vault".return = "308 ${tailnetOrigin}/vault/";

        "^~ /vault/" = {
          proxyPass = "http://127.0.0.1:${toString vaultwardenPort}";
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_buffering off;
            ${nginxProxyHeaders}
          '';
        };

        "/" = {
          proxyPass = "http://127.0.0.1:${toString immichPort}";
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_request_buffering off;
            proxy_buffering off;
            ${nginxProxyHeaders}
          '';
        };
      };
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
      # Clear persisted imperative mappings so no stale non-443 listener
      # survives a declarative configuration change.
      ExecStartPre = "${pkgs.tailscale}/bin/tailscale serve reset";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:${toString nginxPort}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
    };
  };
}
