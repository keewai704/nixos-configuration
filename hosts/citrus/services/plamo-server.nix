{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../settings.nix)
    plamoClients
    plamoPort
    tailnetHostname
    ;

  cacheDirectory = "/var/cache/plamo-server";
  plamoServer = inputs.plamo-app.packages.${pkgs.stdenv.hostPlatform.system}.vllm;
in
{
  systemd.services.plamo-server = {
    description = "PLaMo 3 Translate 0.8B server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      PLAMO_PORT = toString plamoPort;
      PLAMO_MODEL_DIR = "${cacheDirectory}/models";
      HOME = cacheDirectory;
    };
    serviceConfig = {
      ExecStart = lib.getExe plamoServer;
      DynamicUser = true;
      CacheDirectory = "plamo-server";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.nginx = {
    appendHttpConfig = ''
      map $tailscale_client_ip $plamo_server_allowed {
        default 0;
        ${lib.concatMapStrings (client: ''
          "${client}" 1;
        '') plamoClients}
      }
    '';

    virtualHosts.${tailnetHostname}.locations."^~ /plamo/" = {
      proxyPass = "http://127.0.0.1:${toString plamoPort}/";
      extraConfig = ''
        if ($plamo_server_allowed = 0) {
          return 403;
        }
      '';
    };
  };
}
