{ lib, pkgs, ... }:

let
  inherit (import ../settings.nix)
    immichMediaRoot
    immichPort
    citrusWakePort
    storageMountUnit
    tailnetHostname
    tailnetOrigin
    ;
  mkProxyLocation = import ../../../modules/tailnet-web/proxy.nix;
  serverDependencies = [
    "media-storage-prepare.service"
    storageMountUnit
  ];
in
{
  orange.healthMonitor = {
    units = [
      "immich-server.service"
      "postgresql.service"
      "redis-immich.service"
    ];
    loopbackPorts = [ immichPort ];
  };

  users = {
    groups.immich-media.gid = 1000;
    users = {
      immich.extraGroups = [
        "render"
        "video"
      ];
      keewai.extraGroups = [ "immich-media" ];
    };
  };

  services = {
    immich = {
      enable = true;
      host = "127.0.0.1";
      port = immichPort;
      mediaLocation = immichMediaRoot;
      group = "immich-media";

      machine-learning.enable = false;
      environment = {
        LIBVA_DRIVER_NAME = "iHD";
      };

      accelerationDevices = [ "/dev/dri/renderD128" ];
      settings = {
        backup.database = {
          enabled = true;
          cronExpression = "0 6 * * *";
          keepLastAmount = 14;
        };
        ffmpeg = {
          accel = "qsv";
          accelDecode = true;
          transcode = "disabled";
          realtime.enabled = true;
        };
        machineLearning = {
          urls = [ "http://127.0.0.1:${toString citrusWakePort}" ];
          availabilityChecks.enabled = false;
          clip.modelName = "XLM-Roberta-Large-ViT-H-14__frozen_laion5b_s13b_b90k";
          facialRecognition = {
            modelName = "antelopev2";
            minFaces = 10;
          };
          ocr.modelName = "PP-OCRv6_small";
        };
        server.externalDomain = tailnetOrigin;
      };
    };

    postgresql.package = pkgs.postgresql_17;
  };

  systemd.tmpfiles.settings.immich.${immichMediaRoot}.e = {
    user = lib.mkForce "keewai";
    group = lib.mkForce "immich-media";
    mode = lib.mkForce "0770";
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations."/" = mkProxyLocation immichPort ''
    proxy_request_buffering off;
  '';

  systemd.services.immich-server = {
    requires = serverDependencies;
    after = serverDependencies;
    serviceConfig.ReadWritePaths = [ immichMediaRoot ];
  };
}
