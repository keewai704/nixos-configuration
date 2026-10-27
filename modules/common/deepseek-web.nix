{ config, ... }:
let
  tailnetHostname = "${config.networking.hostName}.tail1e65cd.ts.net";
in
{
  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /dsh".return = "308 https://${tailnetHostname}/dsh/";
    "^~ /dsh/" = {
      proxyPass = "http://127.0.0.1:3080/";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_forwarded_for;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
      '';
    };
  };
}
