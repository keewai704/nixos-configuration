{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tailnetWeb;
in
{
  options.services.tailnetWeb = {
    enable = lib.mkEnableOption "the shared Tailscale Serve and nginx gateway";

    tailnetHostname = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.tail1e65cd.ts.net";
      description = "Canonical MagicDNS hostname served by nginx.";
    };

    nginxPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Loopback-only nginx port targeted by Tailscale Serve.";
    };

  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      appendHttpConfig = ''
        # Tailscale Serve supplies the original tailnet client in this header.
        # Fall back to the direct peer for loopback health checks.
        map $http_x_forwarded_for $tailscale_client_ip {
          default $http_x_forwarded_for;
          "" $remote_addr;
        }
      '';

      virtualHosts.${cfg.tailnetHostname} = {
        default = true;
        listen = [
          {
            addr = "127.0.0.1";
            port = cfg.nginxPort;
          }
        ];

      };
    };

    systemd.services = {

      tailscale-serve-nginx = {
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
          ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=443 http://127.0.0.1:${toString cfg.nginxPort}";
        };
      };
    };
  };
}
