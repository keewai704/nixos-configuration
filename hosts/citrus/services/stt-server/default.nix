{
  cudaPkgs,
  lib,
  mkClientAllowlist,
  reuseDenoise,
  ...
}:
let
  inherit (import ../../settings.nix) gpuApiClients sttPort tailnetHostname;

  allowlist = mkClientAllowlist "$stt_server_allowed" gpuApiClients;
  cacheDirectory = "/var/cache/stt-server";

  sttServer = cudaPkgs.writers.writePython3Bin "stt-server" {
    libraries = with cudaPkgs.python3Packages; [
      fastapi
      python-multipart
      uvicorn
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./stt-server.py);
in
{
  systemd.services.stt-server = {
    description = "OpenAI-compatible speech-to-text server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      cudaPkgs.whisper-ctranslate2
      reuseDenoise
    ];
    environment = {
      STT_PORT = toString sttPort;
      STT_MODEL_DIR = cacheDirectory;
      HOME = cacheDirectory;
      XDG_CACHE_HOME = cacheDirectory;
    };
    serviceConfig = {
      ExecStart = lib.getExe sttServer;
      DynamicUser = true;
      CacheDirectory = "stt-server";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.nginx = {
    appendHttpConfig = allowlist.map;

    virtualHosts.${tailnetHostname}.locations."^~ /stt/" = {
      proxyPass = "http://127.0.0.1:${toString sttPort}/";
      extraConfig = allowlist.deny + ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
