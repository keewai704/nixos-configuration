{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tailnetWeb;
  piWeb = pkgs.callPackage ../pkgs/pi-web/package.nix {
    withPiSubpath = true;
  };
in
{
  options.services.tailnetWeb = {
    enable = lib.mkEnableOption "the shared Tailscale Serve, nginx, and Pi Web gateway";

    tailnetHostname = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.tail1e65cd.ts.net";
      description = "Canonical MagicDNS hostname used by nginx and Pi Web.";
    };

    nginxPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Loopback-only nginx port targeted by Tailscale Serve.";
    };

    piWebPort = lib.mkOption {
      type = lib.types.port;
      default = 30141;
      description = "Loopback-only Pi Web backend port.";
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

        locations = {
          "= /pi".return = "308 https://${cfg.tailnetHostname}/pi/";

          "^~ /pi/" = {
            # Pi Web is built with Next.js basePath=/pi, so preserve the
            # complete request path instead of stripping the prefix.
            proxyPass = "http://127.0.0.1:${toString cfg.piWebPort}";
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_request_buffering off;
              proxy_buffering off;
              proxy_read_timeout 86400s;
              proxy_send_timeout 86400s;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $tailscale_client_ip;
              proxy_set_header X-Forwarded-For $tailscale_client_ip;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-Host $host;
              proxy_set_header X-Forwarded-Prefix /pi;
              proxy_set_header X-Forwarded-Server $hostname;
            '';
          };
        };
      };
    };

    systemd.services = {
      nginx = {
        wants = [ "pi-web.service" ];
        after = [ "pi-web.service" ];
      };

      pi-web = {
        description = "Pi Web coding-agent interface";
        requires = [ "home-manager-keewai.service" ];
        wants = [ "network-online.target" ];
        after = [
          "home-manager-keewai.service"
          "network-online.target"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          "/etc/profiles/per-user/keewai"
          pkgs.bash
          pkgs.coreutils
          pkgs.git
          pkgs.nodejs_24
          pkgs.ripgrep
        ];
        environment = {
          HOME = "/home/keewai";
          PI_CODING_AGENT_DIR = "/home/keewai/.pi/agent";
          PI_FFF_MODE = "override";
          PI_FFF_MULTIGREP = "1";
          PI_TELEMETRY = "0";
          PI_WEB_ALLOWED_HOSTS = cfg.tailnetHostname;
          PI_WEB_HOSTNAME = "127.0.0.1";
          PI_WEB_NO_OPEN = "1";
          PI_WEB_SKIP_VERSION_CHECK = "1";
        };
        serviceConfig = {
          User = "keewai";
          Group = "users";
          WorkingDirectory = "/home/keewai";
          ExecStart = "${piWeb}/bin/pi-web --hostname 127.0.0.1 --port ${toString cfg.piWebPort} --no-open";
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStopSec = "30s";
          UMask = "0077";
        };
      };

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
