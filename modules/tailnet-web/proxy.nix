port: extraConfig: {
  proxyPass = "http://127.0.0.1:${toString port}";
  proxyWebsockets = true;
  recommendedProxySettings = false;
  extraConfig = ''
    ${extraConfig}
    proxy_buffering off;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $tailscale_client_ip;
    proxy_set_header X-Forwarded-For $tailscale_client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $hostname;
  '';
}
