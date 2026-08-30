{
  config,
  orangeSettings,
  ...
}:

let
  inherit (config.services.tailnetWeb) tailnetHostname;
  inherit (orangeSettings)
    camofoxNoVncPort
    immichPort
    vaultwardenPort
    ;
  noVncViewerUrl = "https://${tailnetHostname}/browser/vnc.html?autoconnect=true&reconnect=true&reconnect_delay=1000&resize=scale&path=browser/websockify";
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
    proxyTimeout = "600s";
    clientMaxBodySize = "50000M";

    virtualHosts.${tailnetHostname} = {
      extraConfig = ''
        client_body_buffer_size 1024k;
        send_timeout 600s;
      '';
      locations = {
        # Redirect to the canonical HTTPS origin explicitly. Since nginx
        # listens on loopback HTTP, a relative return would otherwise expose
        # its internal :8000 address in the generated Location header.
        "= /browser".return = "302 ${noVncViewerUrl}";
        "= /browser/".return = "302 ${noVncViewerUrl}";

        "^~ /browser/" = {
          # The trailing slash strips /browser/ before forwarding to
          # websockify's root-mounted noVNC web application.
          proxyPass = "http://127.0.0.1:${toString camofoxNoVncPort}/";
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_buffering off;
            access_log off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            proxy_set_header Host 127.0.0.1:${toString camofoxNoVncPort};
            proxy_set_header X-Real-IP $tailscale_client_ip;
            proxy_set_header X-Forwarded-For $tailscale_client_ip;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Prefix /browser;
            proxy_set_header X-Forwarded-Server $hostname;
          '';
        };

        "= /vault".return = "308 https://${tailnetHostname}/vault/";

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
}
