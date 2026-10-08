{ config, pkgs, ... }:
let
  inherit (import ../settings.nix)
    cliproxyapiPort
    tailnetHostname
    tailnetOrigin
    ;
  secretsDir = "/var/lib/cliproxyapi-secrets";
  apiKeyFile = "${secretsDir}/api-key";
in
{
  services.cliproxyapi = {
    enable = true;
    settings = {
      server = {
        host = "127.0.0.1";
        port = cliproxyapiPort;
        trusted-proxies = [ "127.0.0.1" ];
      };
      access.api-keys = [ { _secret = apiKeyFile; } ];
    };
  };

  environment.systemPackages = [ config.services.cliproxyapi.package ];

  systemd.services = {
    cliproxyapi-secrets = {
      description = "Generate the CLIProxyAPI client API key";
      before = [ "cliproxyapi.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = baseNameOf secretsDir;
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
      script = ''
        if [ ! -s ${apiKeyFile} ]; then
          printf 'sk-%s' "$(${pkgs.openssl}/bin/openssl rand -hex 24)" > ${apiKeyFile}.tmp
          mv ${apiKeyFile}.tmp ${apiKeyFile}
        fi
      '';
    };

    cliproxyapi = {
      requires = [ "cliproxyapi-secrets.service" ];
      after = [ "cliproxyapi-secrets.service" ];
    };
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /cliproxy".return = "308 ${tailnetOrigin}/cliproxy/";
    "^~ /cliproxy/" = {
      proxyPass = "http://127.0.0.1:${toString cliproxyapiPort}/";
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
        proxy_set_header X-Forwarded-Server $hostname;
      '';
    };
  };
}
