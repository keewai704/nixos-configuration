{
  orangeSettings,
  pkgs,
  ...
}:

let
  inherit (orangeSettings) piWebPort tailnetHostname;
  piWeb = pkgs.callPackage ../../pkgs/pi-web/package.nix {
    withPiSubpath = true;
  };
in
{
  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /pi".return = "308 https://${tailnetHostname}/pi/";

    "^~ /pi/" = {
      # Pi Web is built with Next.js basePath=/pi, so preserve the complete
      # request path instead of stripping the location prefix.
      proxyPass = "http://127.0.0.1:${toString piWebPort}";
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
        PI_WEB_ALLOWED_HOSTS = tailnetHostname;
        PI_WEB_HOSTNAME = "127.0.0.1";
        PI_WEB_NO_OPEN = "1";
        PI_WEB_SKIP_VERSION_CHECK = "1";
      };
      serviceConfig = {
        User = "keewai";
        Group = "users";
        WorkingDirectory = "/home/keewai";
        ExecStart = "${piWeb}/bin/pi-web --hostname 127.0.0.1 --port ${toString piWebPort} --no-open";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "30s";
        UMask = "0077";
      };
    };
  };
}
