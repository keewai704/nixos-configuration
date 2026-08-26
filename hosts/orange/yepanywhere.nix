{
  lib,
  pkgs,
  ...
}:

let
  yepAnywhere = pkgs.callPackage ../../pkgs/yepanywhere/package.nix { };
  tailnetHostname = "orange.tail1e65cd.ts.net";
  applicationPort = 3400;
  nginxPort = 8001;
  tailnetHttpsPort = 8446;
in
{
  environment.systemPackages = [ yepAnywhere ];

  systemd = {
    tmpfiles.rules = [
      "d /home/keewai/.yep-anywhere 0700 keewai users -"
    ];

    services = {
      yepanywhere = {
        description = "Yep Anywhere coding-agent supervisor";
        requires = [ "home-manager-keewai.service" ];
        wants = [ "network-online.target" ];
        after = [
          "home-manager-keewai.service"
          "network-online.target"
        ];
        wantedBy = [ "multi-user.target" ];

        # The mutable profile paths provide the already authenticated Codex CLI;
        # the remaining entries support Git operations started from the UI.
        path = [
          "/home/keewai/.local"
          "/home/keewai/.nix-profile"
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.openssh
        ];

        environment = {
          HOME = "/home/keewai";
          LOG_PRETTY = "false";
          YEP_DATA_DIR = "/home/keewai/.yep-anywhere";
        };

        serviceConfig = {
          User = "keewai";
          Group = "users";
          WorkingDirectory = "/home/keewai";
          ExecStart = "${lib.getExe yepAnywhere} --host 127.0.0.1 --port ${toString applicationPort}";
          Restart = "on-failure";
          RestartSec = "5s";
          KillMode = "mixed";
          TimeoutStopSec = "90s";
          UMask = "0077";
        };
      };

      tailscale-serve-nginx.serviceConfig.ExecStart = [
        "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=${toString tailnetHttpsPort} http://127.0.0.1:${toString nginxPort}"
      ];
    };
  };

  services.nginx.virtualHosts.yepanywhere = {
    serverName = tailnetHostname;
    default = true;
    listen = [
      {
        addr = "127.0.0.1";
        port = nginxPort;
      }
    ];

    # Yep Anywhere emits root-relative /api and WebSocket URLs and has no
    # external base-path setting. A dedicated tailnet HTTPS port avoids
    # colliding with Immich while retaining the required nginx proxy hop.
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString applicationPort}";
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
        proxy_set_header X-Forwarded-Port ${toString tailnetHttpsPort};
        proxy_set_header X-Forwarded-Server $hostname;
      '';
    };
  };
}
