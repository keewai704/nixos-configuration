{
  inputs,
  lib,
  mkClientAllowlist,
  pkgs,
  ...
}:
let
  inherit (import ../settings.nix)
    gpuApiClients
    plamoPort
    tailnetHostname
    ;

  allowlist = mkClientAllowlist "$plamo_server_allowed" gpuApiClients;
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
      ExecPaths = "/var/cache/private/plamo-server";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.nginx = {
    appendHttpConfig = allowlist.map;

    virtualHosts.${tailnetHostname}.locations."^~ /plamo/" = {
      proxyPass = "http://127.0.0.1:${toString plamoPort}/";
      extraConfig = allowlist.deny;
    };
  };
}
