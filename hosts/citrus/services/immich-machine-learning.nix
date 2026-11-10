{ cudaPkgs, lib, ... }:
let
  inherit (import ../settings.nix)
    immichMachineLearningClients
    immichMachineLearningPort
    machineLearningModels
    tailnetHostname
    ;

  cacheDirectory = "/var/cache/immich-machine-learning";
in
{
  systemd.services.immich-machine-learning = {
    description = "Immich machine learning inference";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      IMMICH_HOST = "127.0.0.1";
      IMMICH_PORT = toString immichMachineLearningPort;
      MACHINE_LEARNING_CACHE_FOLDER = cacheDirectory;
      XDG_CACHE_HOME = cacheDirectory;
      HOME = cacheDirectory;
      HF_HUB_DISABLE_XET = "1";
      MACHINE_LEARNING_MODEL_REVISION = "v2";
      MACHINE_LEARNING_PRELOAD__CLIP__TEXTUAL = machineLearningModels.clip;
      MACHINE_LEARNING_PRELOAD__CLIP__VISUAL = machineLearningModels.clip;
      MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION__DETECTION = machineLearningModels.facialRecognition;
      MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION__RECOGNITION = machineLearningModels.facialRecognition;
      MACHINE_LEARNING_PRELOAD__OCR__DETECTION = machineLearningModels.ocr;
      MACHINE_LEARNING_PRELOAD__OCR__RECOGNITION = machineLearningModels.ocr;
    };
    serviceConfig = {
      ExecStart = lib.getExe cudaPkgs.immich-machine-learning;
      DynamicUser = true;
      CacheDirectory = "immich-machine-learning";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.nginx = {
    appendHttpConfig = ''
      map $tailscale_client_ip $immich_machine_learning_allowed {
        default 0;
        ${lib.concatMapStrings (client: ''
          "${client}" 1;
        '') immichMachineLearningClients}
      }
    '';

    virtualHosts.${tailnetHostname}.locations."^~ /immich-machine-learning/" = {
      proxyPass = "http://127.0.0.1:${toString immichMachineLearningPort}/";
      extraConfig = ''
        if ($immich_machine_learning_allowed = 0) {
          return 403;
        }
      '';
    };
  };
}
