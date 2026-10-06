{ pkgs, ... }:
let
  inherit (import ../settings.nix) openpencilPort tailnetHostname tailnetOrigin;
  package = pkgs.callPackage ../../../pkgs/openpencil-web { };
  initialDocument = pkgs.writeText "openpencil-session.op" (
    builtins.toJSON {
      version = "0.8.4";
      name = "OpenPencil";
      children = [ ];
    }
  );
in
{
  systemd.services.openpencil = {
    description = "OpenPencil web editor and MCP server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      HOME = "/var/lib/openpencil";
      XDG_CONFIG_HOME = "/var/lib/openpencil/config";
      OPENPENCIL_WEB_ALLOWED_ORIGINS = tailnetOrigin;
    };
    preStart = ''
      if [ ! -e /var/lib/openpencil/session.op ]; then
        cp ${initialDocument} /var/lib/openpencil/session.op
        chmod 600 /var/lib/openpencil/session.op
      fi
    '';
    serviceConfig = {
      ExecStart = "${package}/bin/op-host-web-server --serve-web ${toString openpencilPort} /var/lib/openpencil/session.op --host 127.0.0.1";
      DynamicUser = true;
      StateDirectory = "openpencil";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/openpencil";
      Restart = "on-failure";
      RestartSec = "3s";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  services.nginx.appendHttpConfig = ''
    map $http_origin $openpencil_origin_allowed {
      default 0;
      "" 1;
      "${tailnetOrigin}" 1;
    }
  '';
  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /openpencil".return = "308 ${tailnetOrigin}/openpencil/";
    "= /openpencil/bootstrap.js" = {
      alias = "${package}/share/openpencil/bootstrap.js";
      extraConfig = ''
        default_type application/javascript;
        add_header Cache-Control "no-cache";
      '';
    };
    "= /openpencil/service-worker.js" = {
      alias = "${package}/share/openpencil/service-worker.js";
      extraConfig = ''
        default_type application/javascript;
        add_header Cache-Control "no-cache";
        add_header Service-Worker-Allowed "/openpencil/";
      '';
    };
    "^~ /openpencil/" = {
      proxyPass = "http://127.0.0.1:${toString openpencilPort}/";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      extraConfig = ''
        if ($openpencil_origin_allowed = 0) { return 403; }
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $tailscale_client_ip;
        proxy_set_header X-Forwarded-For $tailscale_client_ip;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Prefix /openpencil;
        proxy_set_header Accept-Encoding "";
        proxy_hide_header Access-Control-Allow-Origin;
        proxy_buffering off;
        sub_filter_once on;
        sub_filter "const mod = await import('/pkg/op_host_web.js');" "await import('/openpencil/bootstrap.js').then(m => m.ready); const mod = await import('/openpencil/pkg/op_host_web.js');";
      '';
    };
  };
}
